import CoreMedia
import CoreVideo
import Darwin
import XCTest
@testable import OpenDeskAgent
import OpenDeskCore

final class VideoToolboxEncoderTests: XCTestCase {
    func testH264EncodesFramesAndReconfiguresAfterResolutionChange() throws {
        let collector = EncodedFrameCollector()
        let outputReceived = expectation(description: "three encoded frame callbacks")
        outputReceived.expectedFulfillmentCount = 3
        let encoder = try VideoToolboxEncoder(
            configuration: EncodeConfiguration(codec: .h264, hardwareAcceleration: true, averageBitrateKbps: 500),
            width: 320,
            height: 240,
            framesPerSecond: 30,
            onEncodedFrame: {
                collector.append($0)
                outputReceived.fulfill()
            },
            onFailure: { XCTFail("VideoToolbox callback failed: \($0)") }
        )

        try encoder.encode(try Self.capturedFrame(width: 320, height: 240, pts: 0), forceKeyFrame: true)
        try encoder.setAverageBitrate(kbps: 700)
        XCTAssertEqual(encoder.averageBitrateKbps, 700)
        try encoder.encode(try Self.capturedFrame(width: 320, height: 240, pts: 33_333_333))
        try encoder.encode(try Self.capturedFrame(width: 640, height: 360, pts: 66_666_666))
        XCTAssertEqual(encoder.dimensions.width, 640)
        XCTAssertEqual(encoder.dimensions.height, 360)
        encoder.finish()
        wait(for: [outputReceived], timeout: 5)

        let frames = collector.frames
        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(frames.allSatisfy { $0.codec == .h264 && !$0.payload.isEmpty })
        XCTAssertTrue(frames.allSatisfy { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCMVideoCodecType_H264 })
        XCTAssertEqual(frames.map(\.width), [320, 320, 640])
        XCTAssertEqual(frames.map(\.height), [240, 240, 360])
        XCTAssertTrue(frames[0].isKeyFrame, "a new encode session starts with a decodable keyframe")
        XCTAssertTrue(frames[2].isKeyFrame, "a resolution-driven new session must begin with a keyframe")
        XCTAssertEqual(frames.map(\.presentationTimeNanoseconds), [0, 33_333_333, 66_666_666])
    }

    func testEncodeRejectsDimensionMetadataMismatch() throws {
        let encoder = try VideoToolboxEncoder(width: 320, height: 240, onEncodedFrame: { _ in })
        let badFrame = try Self.capturedFrame(width: 320, height: 240, pts: 0, metadataWidth: 640)
        XCTAssertThrowsError(try encoder.encode(badFrame))
        encoder.finish()
    }

    func testEncodeAfterFinishFailsExplicitly() throws {
        let encoder = try VideoToolboxEncoder(width: 320, height: 240, onEncodedFrame: { _ in })
        encoder.finish()
        XCTAssertThrowsError(try encoder.encode(try Self.capturedFrame(width: 320, height: 240, pts: 0))) { error in
            XCTAssertEqual(error as? VideoToolboxEncoderError, .encoderStopped)
        }
    }

    func testAdaptiveBitrateUpdateRejectsOutOfRangeValues() throws {
        let encoder = try VideoToolboxEncoder(width: 320, height: 240, onEncodedFrame: { _ in })
        XCTAssertThrowsError(try encoder.setAverageBitrate(kbps: 20))
        XCTAssertEqual(encoder.averageBitrateKbps, 6_000)
        encoder.finish()
    }

    func testOutputHandlerCanFinishEncoderWithoutCallbackDeadlock() throws {
        let reference = VideoEncoderReference()
        let outputReceived = expectation(description: "callback may finish encoder")
        let encoder = try VideoToolboxEncoder(width: 320, height: 240, onEncodedFrame: { _ in
            reference.finish()
            outputReceived.fulfill()
        })
        reference.encoder = encoder
        try encoder.encode(try Self.capturedFrame(width: 320, height: 240, pts: 0), forceKeyFrame: true)
        wait(for: [outputReceived], timeout: 5)
        XCTAssertThrowsError(try encoder.encode(try Self.capturedFrame(width: 320, height: 240, pts: 33_333_333)))
    }

    func testOutputHandlerCanUpdateBitrateAndEncodeResizedFrame() throws {
        let reference = VideoEncoderReference()
        let collector = EncodedFrameCollector()
        let outputReceived = expectation(description: "reentrant resize reaches output")
        outputReceived.expectedFulfillmentCount = 2
        let encoder = try VideoToolboxEncoder(width: 320, height: 240, onEncodedFrame: { frame in
            collector.append(frame)
            outputReceived.fulfill()
            if frame.width == 320 {
                do {
                    try reference.updateBitrateAndEncodeResize()
                } catch {
                    XCTFail("reentrant bitrate/resize failed: \(error)")
                }
            }
        })
        reference.encoder = encoder
        try encoder.encode(try Self.capturedFrame(width: 320, height: 240, pts: 0), forceKeyFrame: true)
        wait(for: [outputReceived], timeout: 5)
        encoder.finish()

        XCTAssertEqual(encoder.averageBitrateKbps, 800)
        XCTAssertEqual(collector.frames.map(\.width), [320, 640])
    }

    fileprivate static func capturedFrame(
        width: Int,
        height: Int,
        pts: Int64,
        metadataWidth: Int? = nil
    ) throws -> CapturedScreenFrame {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attributes as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess, let pixelBuffer = output else {
            throw NSError(domain: "VideoToolboxEncoderTests", code: Int(status))
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else { continue }
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
            let planeHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            memset(base, plane == 0 ? 96 : 128, rowBytes * planeHeight)
        }
        let metadata = CaptureFrameMetadata(
            displayID: 1,
            width: metadataWidth ?? width,
            height: height,
            timestampNanoseconds: pts,
            contentX: 0,
            contentY: 0,
            contentWidth: Double(width),
            contentHeight: Double(height),
            scaleFactor: 1
        )
        return CapturedScreenFrame(pixelBuffer: pixelBuffer, metadata: metadata)
    }
}

private final class EncodedFrameCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [EncodedVideoFrame] = []

    var frames: [EncodedVideoFrame] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ frame: EncodedVideoFrame) {
        lock.lock()
        stored.append(frame)
        lock.unlock()
    }
}

private final class VideoEncoderReference: @unchecked Sendable {
    private let lock = NSLock()
    private weak var storedEncoder: VideoToolboxEncoder?

    var encoder: VideoToolboxEncoder? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedEncoder
        }
        set {
            lock.lock()
            storedEncoder = newValue
            lock.unlock()
        }
    }

    func finish() {
        encoder?.finish()
    }

    func updateBitrateAndEncodeResize() throws {
        guard let encoder else { throw VideoToolboxEncoderError.encoderStopped }
        try encoder.setAverageBitrate(kbps: 800)
        try encoder.encode(try VideoToolboxEncoderTests.capturedFrame(width: 640, height: 360, pts: 33_333_333))
    }
}
