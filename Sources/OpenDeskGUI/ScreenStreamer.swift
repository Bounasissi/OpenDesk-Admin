import Foundation
@preconcurrency import AppKit
import SwiftUI
@preconcurrency import OpenDeskCore

/// Live screen streaming session for the GUI viewer.
/// Owns a background thread running the RFB update loop and publishes
/// decoded frames to SwiftUI on the main actor.
@MainActor
final class ScreenStreamer: ObservableObject {    @Published var frame: NSImage?
    @Published var status: String = "Idle."
    @Published var isConnected = false
    @Published var controlMode = false

    private var thread: Thread?
    // Lock-guarded shared state: written by the RFB update thread and read/
    // written on the main thread. stateLock is the synchronization point.
    private nonisolated(unsafe) var stopFlag = false
    private let stateLock = NSLock()

    private nonisolated(unsafe) var client: RFBClient?
    private nonisolated(unsafe) var connection: RFBConnection?
    private nonisolated(unsafe) var framebuffer: Framebuffer?

    let host: OpenDeskCore.Host
    let password: String?
    /// Quality tier pacing (Plan 10 §3): throttles frame-request cadence
    /// without reconnecting (tier change preserves the connection).
    /// nonisolated(unsafe): written on the main actor via applyQualityTier,
    /// read by the update thread; the tier value is a simple enum write.
    private nonisolated(unsafe) var qualityTier: QualityTier = .focused

    init(host: OpenDeskCore.Host, password: String? = nil) {
        self.host = host
        self.password = password
    }

    deinit {
        // Main-actor isolation: hop to the main queue for teardown.
        let backgroundThread = thread
        let lock = stateLock
        lock.lock()
        stopFlag = true
        lock.unlock()
        backgroundThread?.cancel()
        DispatchQueue.main.async { [weak self] in
            self?.connection?.close()
        }
    }

    func startStreaming() {
        guard !isConnected else { return }
        stopFlag = false
        status = "Connecting to \(host.hostname):\(host.screenPort)…"
        let target = host
        let password = self.password
        let thread = Thread { [weak self] in
            self?.runUpdateLoop(host: target, password: password)
        }
        thread.name = "opendesk.rfb.\(host.hostname)"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stopStreaming() {
        stateLock.lock()
        stopFlag = true
        stateLock.unlock()
        thread?.cancel()
        stateLock.lock()
        connection?.close()
        stateLock.unlock()
    }

    // MARK: - Update loop (background thread)

    private nonisolated func runUpdateLoop(host: OpenDeskCore.Host, password: String?) {
        do {
            let tcp = try TCPConnection(host: host.hostname, port: UInt16(host.screenPort))
            stateLock.lock()
            connection = tcp
            stateLock.unlock()

            let rfb = RFBClient(connection: tcp)
            try rfb.handshake(password: password)
            try rfb.setPixelFormat(.standard32)
            try rfb.setEncodings()

            guard let dims = rfb.dimensions else {
                throw RFBError.handshakeFailed("no framebuffer dimensions")
            }
            stateLock.lock()
            client = rfb
            framebuffer = try Framebuffer(width: Int(dims.width), height: Int(dims.height))
            stateLock.unlock()

            // First update is a full request; subsequent are incremental.
            try rfb.requestFramebufferUpdate(incremental: false)

            let displayHost = rfb.serverName.isEmpty ? host.hostname : rfb.serverName
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = true
                self?.status = "Connected: \(displayHost) (\(dims.width)×\(dims.height))"
            }

            var firstUpdate = true
            while !isStopped() && !Thread.current.isCancelled {
                // Tier pacing: sleep between requests per tier cap (no reconnect).
                let interval = qualityTier.frameRequestIntervalMs
                if interval != .max, interval > 0 {
                    Thread.sleep(forTimeInterval: Double(interval) / 1000.0)
                }
                let rects = try rfb.readFramebufferUpdate(format: .standard32)
                stateLock.lock()
                let fb = framebuffer
                stateLock.unlock()
                if let fb {
                    for rect in rects { fb.apply(rect) }
                    let image = try FramebufferRenderer.nsImage(from: fb)
                    // Single-producer (update thread) → single-consumer (main
                    // thread) frame handoff. NSImage is not Sendable on every
                    // SDK, so the handoff crosses the queue through an
                    // explicitly unchecked box instead of a raw capture.
                    let handoff = FrameHandoff(image)
                    DispatchQueue.main.async { [weak self] in
                        self?.frame = handoff.image
                    }
                }
                if firstUpdate {
                    firstUpdate = false
                }
                try rfb.requestFramebufferUpdate(incremental: !firstUpdate)
            }
        } catch {
            stateLock.lock()
            connection?.close()
            stateLock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.status = "Streaming stopped: \(error)"
            }
        }
    }

    /// Apply a quality tier without reconnect (Plan 10 §5).
    func applyQualityTier(_ tier: QualityTier) {
        qualityTier = tier
    }

    private nonisolated func isStopped() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopFlag
    }

    // MARK: - Input injection (control mode)

    func sendKeyEvent(keysym: UInt32, down: Bool) {
        stateLock.lock()
        let client = self.client
        stateLock.unlock()
        guard let client else { return }
        do {
            try client.sendKeyEvent(keysym: keysym, down: down)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.status = "key event failed: \(error)"
            }
        }
    }

    func sendPointerEvent(x: UInt16, y: UInt16, buttonMask: UInt8) {
        stateLock.lock()
        let client = self.client
        stateLock.unlock()
        guard let client else { return }
        do {
            try client.sendPointerEvent(x: x, y: y, buttonMask: buttonMask)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.status = "pointer event failed: \(error)"
            }
        }
    }
}

/// Explicit handoff box for frame images crossing the update-thread → main-
/// thread queue boundary. NSImage is not marked Sendable on all SDKs; the
/// handoff is single-producer/single-consumer and the ownership transfer is
/// total (the update thread never touches the image after publication), so
/// the unchecked Sendable conformance is sound.
final class FrameHandoff: @unchecked Sendable {
    let image: NSImage?
    init(_ image: NSImage?) { self.image = image }
}
