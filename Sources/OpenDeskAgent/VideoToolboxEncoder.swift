import CoreMedia
import CoreVideo
import Foundation
import OpenDeskCore
import VideoToolbox

/// Encoded H.264/HEVC access unit and the format description needed by a
/// downstream decoder or transport when codec parameters change.
public final class EncodedVideoFrame: @unchecked Sendable {
    public let codec: StreamCodec
    public let presentationTimeNanoseconds: Int64
    public let width: Int
    public let height: Int
    public let isKeyFrame: Bool
    public let payload: Data
    public let formatDescription: CMFormatDescription

    init(
        codec: StreamCodec,
        presentationTimeNanoseconds: Int64,
        width: Int,
        height: Int,
        isKeyFrame: Bool,
        payload: Data,
        formatDescription: CMFormatDescription
    ) {
        self.codec = codec
        self.presentationTimeNanoseconds = presentationTimeNanoseconds
        self.width = width
        self.height = height
        self.isKeyFrame = isKeyFrame
        self.payload = payload
        self.formatDescription = formatDescription
    }
}

public enum VideoToolboxEncoderError: Error, Equatable {
    case invalidConfiguration(String)
    case sessionCreationFailed(OSStatus)
    case propertyConfigurationFailed(name: String, status: OSStatus)
    case prepareFailed(OSStatus)
    case encodeFailed(OSStatus)
    case finishFailed(OSStatus)
    case missingCompressedData
    case copyCompressedDataFailed(OSStatus)
    case encoderStopped
}

/// Low-latency VideoToolbox compression stage. Inputs are ScreenCaptureKit
/// IOSurface-backed pixel buffers; output callbacks carry compressed access
/// units and their CMFormatDescription. A dimension change drains and rebuilds
/// the compression session before accepting the resized frame.
public final class VideoToolboxEncoder: @unchecked Sendable {
    public typealias OutputHandler = @Sendable (EncodedVideoFrame) -> Void
    public typealias FailureHandler = @Sendable (VideoToolboxEncoderError) -> Void

    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(label: "com.opendesk.videotoolbox.output", qos: .userInitiated)
    private var configuration: EncodeConfiguration
    private let framesPerSecond: Int
    private let outputHandler: OutputHandler
    private let failureHandler: FailureHandler
    private var session: VTCompressionSession?
    private var callbackContext: Unmanaged<EncoderCallbackContext>?
    private var currentWidth: Int
    private var currentHeight: Int
    private var isFinished = false

    public init(
        configuration: EncodeConfiguration = EncodeConfiguration(),
        width: Int,
        height: Int,
        framesPerSecond: Int = 30,
        onEncodedFrame: @escaping OutputHandler,
        onFailure: @escaping FailureHandler = { _ in }
    ) throws {
        try configuration.validate(width: width, height: height, framesPerSecond: framesPerSecond)
        self.configuration = configuration
        self.currentWidth = width
        self.currentHeight = height
        self.framesPerSecond = framesPerSecond
        self.outputHandler = onEncodedFrame
        self.failureHandler = onFailure
        try createSession(width: width, height: height)
    }

    deinit {
        finish()
    }

    /// Encodes one captured frame. PTS comes from ScreenCaptureKit metadata;
    /// a resized display automatically establishes a new compression session.
    public func encode(_ frame: CapturedScreenFrame, forceKeyFrame: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, self.session != nil else { throw VideoToolboxEncoderError.encoderStopped }
        let width = frame.metadata.width
        let height = frame.metadata.height
        guard width > 0, height > 0,
              CVPixelBufferGetWidth(frame.pixelBuffer) == width,
              CVPixelBufferGetHeight(frame.pixelBuffer) == height,
              CVPixelBufferGetPixelFormatType(frame.pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            throw VideoToolboxEncoderError.invalidConfiguration("pixel buffer geometry or pixel format is incompatible with the configured capture format")
        }
        if width != currentWidth || height != currentHeight {
            try recreateSession(width: width, height: height)
        }
        guard let activeSession = self.session else { throw VideoToolboxEncoderError.encoderStopped }

        var flags = VTEncodeInfoFlags()
        let frameProperties: CFDictionary? = forceKeyFrame
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil
        let status = VTCompressionSessionEncodeFrame(
            activeSession,
            imageBuffer: frame.pixelBuffer,
            presentationTimeStamp: CMTime(value: frame.metadata.timestampNanoseconds, timescale: 1_000_000_000),
            duration: .invalid,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        guard status == noErr else { throw VideoToolboxEncoderError.encodeFailed(status) }
    }

    /// Applies the adaptive-quality controller's bitrate output without
    /// recreating the compression session. The value persists across resize.
    public func setAverageBitrate(kbps: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished, let session else { throw VideoToolboxEncoderError.encoderStopped }
        var updated = configuration
        updated.averageBitrateKbps = kbps
        do {
            try updated.validate(width: currentWidth, height: currentHeight, framesPerSecond: framesPerSecond)
        } catch {
            throw VideoToolboxEncoderError.invalidConfiguration(String(describing: error))
        }
        try set(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: NSNumber(value: kbps * 1_000),
            name: "AverageBitRate"
        )
        configuration = updated
    }

    public var averageBitrateKbps: Int {
        lock.lock()
        defer { lock.unlock() }
        return configuration.averageBitrateKbps
    }

    /// Completes pending VideoToolbox callbacks, then invalidates and releases
    /// session resources. User output callbacks remain asynchronous and may
    /// finish after this method returns. Safe to call more than once.
    public func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        finishSession()
    }

    public var dimensions: (width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (currentWidth, currentHeight)
    }

    private func recreateSession(width: Int, height: Int) throws {
        finishSession()
        currentWidth = width
        currentHeight = height
        try createSession(width: width, height: height)
    }

    private func createSession(width: Int, height: Int) throws {
        do {
            try configuration.validate(width: width, height: height, framesPerSecond: framesPerSecond)
        } catch {
            throw VideoToolboxEncoderError.invalidConfiguration(String(describing: error))
        }

        let context = EncoderCallbackContext(
            codec: configuration.codec,
            outputHandler: outputHandler,
            failureHandler: failureHandler,
            callbackQueue: callbackQueue
        )
        let retainedContext = Unmanaged.passRetained(context)
        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: configuration.hardwareAcceleration,
        ]
        let imageAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        var created: VTCompressionSession?
        let codecType = configuration.codec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: codecType,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: imageAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: videoToolboxOutputCallback,
            refcon: retainedContext.toOpaque(),
            compressionSessionOut: &created
        )
        guard status == noErr, let created else {
            retainedContext.release()
            throw VideoToolboxEncoderError.sessionCreationFailed(status)
        }
        session = created
        callbackContext = retainedContext

        do {
            try set(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue, name: "RealTime")
            try set(
                created,
                key: kVTCompressionPropertyKey_ExpectedFrameRate,
                value: NSNumber(value: framesPerSecond),
                name: "ExpectedFrameRate"
            )
            try set(
                created,
                key: kVTCompressionPropertyKey_AverageBitRate,
                value: NSNumber(value: configuration.averageBitrateKbps * 1_000),
                name: "AverageBitRate"
            )
            try set(
                created,
                key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                value: NSNumber(value: configuration.maxKeyframeIntervalSeconds * framesPerSecond),
                name: "MaxKeyFrameInterval"
            )
            try set(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse, name: "AllowFrameReordering")
            let profile = configuration.codec == .h264
                ? kVTProfileLevel_H264_Main_AutoLevel
                : kVTProfileLevel_HEVC_Main_AutoLevel
            try set(created, key: kVTCompressionPropertyKey_ProfileLevel, value: profile, name: "ProfileLevel")

            let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(created)
            guard prepareStatus == noErr else { throw VideoToolboxEncoderError.prepareFailed(prepareStatus) }
        } catch {
            finishSession()
            throw error
        }
    }

    private func set(_ session: VTCompressionSession, key: CFString, value: CFTypeRef, name: String) throws {
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else {
            throw VideoToolboxEncoderError.propertyConfigurationFailed(name: name, status: status)
        }
    }

    private func finishSession() {
        guard let session else { return }
        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        if status != noErr { reportFailure(.finishFailed(status)) }
        VTCompressionSessionInvalidate(session)
        self.session = nil
        if let callbackContext {
            callbackContext.release()
            self.callbackContext = nil
        }
    }

    private func reportFailure(_ error: VideoToolboxEncoderError) {
        callbackQueue.async { [failureHandler] in failureHandler(error) }
    }
}

private final class EncoderCallbackContext: @unchecked Sendable {
    let codec: StreamCodec
    private let outputHandler: VideoToolboxEncoder.OutputHandler
    private let failureHandler: VideoToolboxEncoder.FailureHandler
    private let callbackQueue: DispatchQueue

    init(
        codec: StreamCodec,
        outputHandler: @escaping VideoToolboxEncoder.OutputHandler,
        failureHandler: @escaping VideoToolboxEncoder.FailureHandler,
        callbackQueue: DispatchQueue
    ) {
        self.codec = codec
        self.outputHandler = outputHandler
        self.failureHandler = failureHandler
        self.callbackQueue = callbackQueue
    }

    func output(_ frame: EncodedVideoFrame) {
        callbackQueue.async { self.outputHandler(frame) }
    }

    func fail(_ error: VideoToolboxEncoderError) {
        callbackQueue.async { self.failureHandler(error) }
    }

}

private func videoToolboxOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard let outputCallbackRefCon else { return }
    let context = Unmanaged<EncoderCallbackContext>.fromOpaque(outputCallbackRefCon).takeUnretainedValue()
    guard status == noErr else {
        context.fail(.encodeFailed(status))
        return
    }
    guard let sampleBuffer,
          let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
          let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
        context.fail(.missingCompressedData)
        return
    }

    let byteCount = CMBlockBufferGetDataLength(blockBuffer)
    var payload = Data(count: byteCount)
    let copyStatus = payload.withUnsafeMutableBytes { bytes -> OSStatus in
        guard let baseAddress = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
        return CMBlockBufferCopyDataBytes(
            blockBuffer,
            atOffset: 0,
            dataLength: byteCount,
            destination: baseAddress.assumingMemoryBound(to: UInt8.self)
        )
    }
    guard copyStatus == noErr else {
        context.fail(.copyCompressedDataFailed(copyStatus))
        return
    }

    let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
    let isKeyFrame = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) != true
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
    let encoded = EncodedVideoFrame(
        codec: context.codec,
        presentationTimeNanoseconds: pts.isValid ? Int64(CMTimeGetSeconds(pts) * 1_000_000_000) : 0,
        width: Int(dimensions.width),
        height: Int(dimensions.height),
        isKeyFrame: isKeyFrame,
        payload: payload,
        formatDescription: formatDescription
    )
    context.output(encoded)
}
