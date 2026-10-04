import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import OpenDeskCore
@preconcurrency import ScreenCaptureKit

/// ScreenCaptureKit frame storage remains IOSurface-backed; the wrapper is
/// unchecked Sendable because consumers must process the buffer before the
/// ScreenCaptureKit output queue advances/recycles it.
public final class CapturedScreenFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let metadata: CaptureFrameMetadata

    public init(pixelBuffer: CVPixelBuffer, metadata: CaptureFrameMetadata) {
        self.pixelBuffer = pixelBuffer
        self.metadata = metadata
    }
}

/// Retained optional system-audio sample for a downstream encoder/multiplexer.
public final class CapturedAudioSample: @unchecked Sendable {
    public let sampleBuffer: CMSampleBuffer

    public init(sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}

public enum ScreenCaptureServiceEvent: Sendable, Equatable {
    case started(displayID: Int)
    case interrupted(displayID: Int, message: String)
    case resumed(displayID: Int)
    case permissionRevoked(displayID: Int)
    case displayRemoved(displayID: Int)
    case stopped(displayID: Int)
}

public enum ScreenCaptureServiceError: Error, Equatable {
    case permissionRequired
    case noDisplays
    case displayUnavailable(Int)
    case invalidSample
}

/// Agent-side ScreenCaptureKit owner. This belongs in the user-session agent,
/// never the privileged daemon: macOS screen-recording consent is per user.
@MainActor
public final class ScreenCaptureService {
    public typealias FrameHandler = @Sendable (CapturedScreenFrame) -> Void
    public typealias AudioHandler = @Sendable (CapturedAudioSample) -> Void
    public typealias EventHandler = @Sendable (ScreenCaptureServiceEvent) -> Void

    private struct ActiveDisplay {
        let stream: SCStream
        let output: ScreenCaptureOutput
        var audioAttached: Bool
    }

    private var activeDisplays: [Int: ActiveDisplay] = [:]
    private var request: CaptureConfiguration?
    private var frameHandler: FrameHandler?
    private var audioHandler: AudioHandler?
    private var eventHandler: EventHandler?
    private var isRunning = false
    private var displayMonitor: Task<Void, Never>?

    public init() {}

    /// Explicitly call from a user-initiated action. Starting capture never
    /// silently triggers the macOS consent prompt.
    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func availableDisplays() async throws -> [CaptureDisplayDescriptor] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays.map(Self.descriptor(for:))
    }

    /// Starts one independently selectable stream per display. Partial start
    /// failures roll back every stream already opened by this invocation.
    public func start(
        configuration: CaptureConfiguration,
        onFrame: @escaping FrameHandler,
        onAudio: AudioHandler? = nil,
        onEvent: EventHandler? = nil
    ) async throws {
        guard !isRunning else { throw ConfigurationError.invalidValue(key: "capture", reason: "already running") }
        guard hasScreenRecordingPermission else { throw ScreenCaptureServiceError.permissionRequired }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let descriptors = content.displays.map(Self.descriptor(for:))
        let plans = try configuration.streamPlans(available: descriptors)
        let displaysByID = Dictionary(uniqueKeysWithValues: content.displays.map { (Int($0.displayID), $0) })

        request = configuration
        frameHandler = onFrame
        audioHandler = onAudio
        eventHandler = onEvent
        do {
            for plan in plans {
                guard let display = displaysByID[plan.display.id] else {
                    throw ScreenCaptureServiceError.displayUnavailable(plan.display.id)
                }
                try await start(
                    display: display,
                    plan: plan,
                    frameHandler: onFrame,
                    audioHandler: onAudio ?? { _ in },
                    eventHandler: onEvent ?? { _ in }
                )
            }
            isRunning = true
            beginDisplayMonitoring()
        } catch {
            await stopAll(emitEvents: false)
            request = nil
            frameHandler = nil
            audioHandler = nil
            eventHandler = nil
            throw error
        }
    }

    /// Re-reads display geometry and updates active stream configuration. A
    /// removed display is stopped and reported; surviving display streams keep
    /// their session and do not reconnect.
    public func refreshDisplayConfiguration() async throws {
        guard let request else { return }
        guard hasScreenRecordingPermission else {
            await handlePermissionRevocation()
            return
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let descriptors = content.displays.map(Self.descriptor(for:))
        let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        var audioAssigned = false
        let plans = request.displayIDs.compactMap { id -> CaptureStreamPlan? in
            guard let display = descriptorsByID[id] else { return nil }
            let capturesAudio = request.audioEnabled && !audioAssigned
            if capturesAudio { audioAssigned = true }
            return CaptureStreamPlan(
                display: display,
                framesPerSecond: request.framesPerSecond,
                capturesAudio: capturesAudio,
                dynamicResolution: request.dynamicResolution
            )
        }
        let availableIDs = Set(plans.map { $0.display.id })

        for id in Array(activeDisplays.keys) where !availableIDs.contains(id) {
            guard let active = activeDisplays.removeValue(forKey: id) else { continue }
            try? await active.stream.stopCapture()
            eventHandler?(.displayRemoved(displayID: id))
        }

        let displaysByID = Dictionary(uniqueKeysWithValues: content.displays.map { (Int($0.displayID), $0) })
        for plan in plans {
            guard let display = displaysByID[plan.display.id] else { continue }
            if var active = activeDisplays[plan.display.id] {
                do {
                    if plan.dynamicResolution || plan.capturesAudio != active.audioAttached {
                        try await active.stream.updateConfiguration(Self.makeStreamConfiguration(for: plan))
                    }
                    if plan.capturesAudio && !active.audioAttached {
                        try active.stream.addStreamOutput(active.output, type: .audio, sampleHandlerQueue: active.output.sampleQueue)
                        active.audioAttached = true
                    } else if !plan.capturesAudio && active.audioAttached {
                        try active.stream.removeStreamOutput(active.output, type: .audio)
                        active.audioAttached = false
                    }
                } catch {
                    activeDisplays.removeValue(forKey: plan.display.id)
                    try? await active.stream.stopCapture()
                    throw error
                }
                activeDisplays[plan.display.id] = active
            } else {
                try await start(
                    display: display,
                    plan: plan,
                    frameHandler: frameHandler ?? { _ in },
                    audioHandler: audioHandler ?? { _ in },
                    eventHandler: eventHandler ?? { _ in }
                )
            }
        }
        isRunning = !activeDisplays.isEmpty
    }

    public func stop() async {
        displayMonitor?.cancel()
        displayMonitor = nil
        await stopAll(emitEvents: true)
        isRunning = false
        request = nil
        frameHandler = nil
        audioHandler = nil
        eventHandler = nil
    }

    private func beginDisplayMonitoring() {
        displayMonitor?.cancel()
        displayMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard let self else { return }
                    try await self.refreshDisplayConfiguration()
                } catch is CancellationError {
                    return
                } catch {
                    // A transient shareable-content query failure is reported
                    // on the next poll; a failed active stream reports itself.
                    continue
                }
            }
        }
    }

    private func handlePermissionRevocation(additionalDisplayID: Int? = nil) async {
        var ids = Array(activeDisplays.keys)
        if let additionalDisplayID, !ids.contains(additionalDisplayID) { ids.append(additionalDisplayID) }
        await stopAll(emitEvents: false)
        isRunning = false
        request = nil
        displayMonitor?.cancel()
        displayMonitor = nil
        for id in ids { eventHandler?(.permissionRevoked(displayID: id)) }
    }

    private func handleStreamFailure(stream: SCStream, displayID: Int, message: String) async {
        guard let active = activeDisplays[displayID], active.stream === stream else { return }
        activeDisplays.removeValue(forKey: displayID)
        if !hasScreenRecordingPermission {
            await handlePermissionRevocation(additionalDisplayID: displayID)
            return
        }
        eventHandler?(.interrupted(displayID: displayID, message: message))
        isRunning = !activeDisplays.isEmpty
    }

    private func start(
        display: SCDisplay,
        plan: CaptureStreamPlan,
        frameHandler: @escaping FrameHandler,
        audioHandler: @escaping AudioHandler,
        eventHandler: @escaping EventHandler
    ) async throws {
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let streamConfiguration = Self.makeStreamConfiguration(for: plan)
        let output = ScreenCaptureOutput(
            displayID: plan.display.id,
            frameHandler: frameHandler,
            audioHandler: audioHandler,
            eventHandler: eventHandler,
            failureHandler: { [weak self] stream, displayID, message in
                Task { @MainActor [weak self] in
                    await self?.handleStreamFailure(stream: stream, displayID: displayID, message: message)
                }
            }
        )
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.sampleQueue)
        if plan.capturesAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.sampleQueue)
        }
        activeDisplays[plan.display.id] = ActiveDisplay(stream: stream, output: output, audioAttached: plan.capturesAudio)
        do {
            try await stream.startCapture()
        } catch {
            activeDisplays.removeValue(forKey: plan.display.id)
            try? await stream.stopCapture()
            isRunning = !activeDisplays.isEmpty
            throw error
        }
        eventHandler(.started(displayID: plan.display.id))
    }

    private func stopAll(emitEvents: Bool) async {
        let current = activeDisplays
        activeDisplays.removeAll()
        for (id, active) in current {
            try? await active.stream.stopCapture()
            if emitEvents { eventHandler?(.stopped(displayID: id)) }
        }
    }

    private static func makeStreamConfiguration(for plan: CaptureStreamPlan) -> SCStreamConfiguration {
        let result = SCStreamConfiguration()
        // Keep the display's native pixel geometry; a later quality controller
        // may add a max-dimension scale while retaining aspect ratio.
        result.width = max(1, plan.display.width)
        result.height = max(1, plan.display.height)
        result.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(plan.framesPerSecond))
        result.queueDepth = 5
        result.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        result.capturesAudio = plan.capturesAudio
        return result
    }

    private static func descriptor(for display: SCDisplay) -> CaptureDisplayDescriptor {
        CaptureDisplayDescriptor(
            id: Int(display.displayID),
            width: Int(CGDisplayPixelsWide(display.displayID)),
            height: Int(CGDisplayPixelsHigh(display.displayID))
        )
    }
}

private final class ScreenCaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let sampleQueue: DispatchQueue
    private let displayID: Int
    private let frameHandler: @Sendable (CapturedScreenFrame) -> Void
    private let audioHandler: @Sendable (CapturedAudioSample) -> Void
    private let eventHandler: @Sendable (ScreenCaptureServiceEvent) -> Void
    private let failureHandler: @Sendable (SCStream, Int, String) -> Void
    private var lastNonCompleteStatus: SCFrameStatus?

    init(
        displayID: Int,
        frameHandler: @escaping @Sendable (CapturedScreenFrame) -> Void,
        audioHandler: @escaping @Sendable (CapturedAudioSample) -> Void,
        eventHandler: @escaping @Sendable (ScreenCaptureServiceEvent) -> Void,
        failureHandler: @escaping @Sendable (SCStream, Int, String) -> Void
    ) {
        self.displayID = displayID
        self.frameHandler = frameHandler
        self.audioHandler = audioHandler
        self.eventHandler = eventHandler
        self.failureHandler = failureHandler
        self.sampleQueue = DispatchQueue(label: "com.opendesk.capture.\(displayID)", qos: .userInteractive)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .audio:
            audioHandler(CapturedAudioSample(sampleBuffer: sampleBuffer))
        case .microphone:
            // Microphone capture is not enabled by this screen-share path.
            return
        case .screen:
            guard CMSampleBufferIsValid(sampleBuffer),
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let first = attachments.first,
                  let statusValue = first[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusValue) else { return }
            guard status == .complete else {
                if (status == .blank || status == .suspended), status != lastNonCompleteStatus {
                    lastNonCompleteStatus = status
                    eventHandler(.interrupted(displayID: displayID, message: "ScreenCaptureKit frame status: \(status.rawValue)"))
                }
                return
            }
            if lastNonCompleteStatus != nil {
                lastNonCompleteStatus = nil
                eventHandler(.resumed(displayID: displayID))
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let rect = first[.contentRect] as? CGRect ?? CGRect(
                origin: .zero,
                size: CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            )
            let scale = first[.scaleFactor] as? Double ?? 1
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let timestamp = pts.isValid ? Int64(CMTimeGetSeconds(pts) * 1_000_000_000) : 0
            let metadata = CaptureFrameMetadata(
                displayID: displayID,
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                timestampNanoseconds: timestamp,
                contentX: rect.origin.x,
                contentY: rect.origin.y,
                contentWidth: rect.width,
                contentHeight: rect.height,
                scaleFactor: scale
            )
            guard metadata.hasValidGeometry else { return }
            frameHandler(CapturedScreenFrame(pixelBuffer: pixelBuffer, metadata: metadata))
        @unknown default:
            return
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        failureHandler(stream, displayID, error.localizedDescription)
    }
}

final class CaptureSmokeMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var frameCount = 0
    private var width = 0
    private var height = 0

    func record(_ metadata: CaptureFrameMetadata) {
        lock.lock()
        frameCount += 1
        width = metadata.width
        height = metadata.height
        lock.unlock()
    }

    func snapshot(durationSeconds: Int) -> (frameCount: Int, framesPerSecond: Double, width: Int, height: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (frameCount, Double(frameCount) / Double(durationSeconds), width, height)
    }
}
