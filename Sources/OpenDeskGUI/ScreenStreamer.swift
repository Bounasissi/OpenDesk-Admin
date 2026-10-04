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
    /// A streamer represents one connection attempt. Reconnection creates a
    /// fresh instance so a late worker from a cancelled attempt cannot revive.
    private var hasStarted = false
    // Lock-guarded shared state: written by the RFB update thread and read/
    // written on the main thread. stateLock is the synchronization point.
    private nonisolated(unsafe) var stopFlag = false
    private let stateLock = NSLock()

    private nonisolated(unsafe) var client: RFBClient?
    private nonisolated(unsafe) var connection: RFBConnection?
    private nonisolated(unsafe) var framebuffer: Framebuffer?
    /// RFB writes originate on both the update thread and UI event path.
    /// Serialize complete protocol messages so bytes cannot interleave.
    private let protocolWriteLock = NSLock()

    let host: OpenDeskCore.Host
    let password: String?
    /// Quality tier pacing (Plan 10 §3): throttles frame-request cadence
    /// without reconnecting (tier change preserves the connection).
    /// Access is serialized by stateLock because the update thread reads it
    /// while the main actor may change tiers.
    private nonisolated(unsafe) var qualityTier: QualityTier

    init(host: OpenDeskCore.Host, password: String? = nil, qualityTier: QualityTier = .focused) {
        self.host = host
        self.password = password
        self.qualityTier = qualityTier
    }

    deinit {
        // Main-actor isolation: hop to the main queue for teardown.
        let backgroundThread = thread
        let lock = stateLock
        lock.lock()
        stopFlag = true
        lock.unlock()
        backgroundThread?.cancel()
        protocolWriteLock.lock()
        stateLock.lock()
        connection?.close()
        stateLock.unlock()
        protocolWriteLock.unlock()
    }

    func startStreaming() {
        guard !hasStarted else { return }
        hasStarted = true
        stateLock.lock()
        stopFlag = false
        stateLock.unlock()
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
        protocolWriteLock.lock()
        stateLock.lock()
        connection?.close()
        stateLock.unlock()
        protocolWriteLock.unlock()
        isConnected = false
        status = "Disconnected."
    }

    // MARK: - Update loop (background thread)

    private nonisolated func runUpdateLoop(host: OpenDeskCore.Host, password: String?) {
        do {
            let tcp = try TCPConnection(host: host.hostname, port: UInt16(host.screenPort))
            stateLock.lock()
            guard !stopFlag else {
                stateLock.unlock()
                tcp.close()
                return
            }
            connection = tcp
            stateLock.unlock()

            let rfb = RFBClient(connection: tcp)
            try rfb.handshake(password: password)
            try rfb.setPixelFormat(.standard32)
            try rfb.setEncodings()
            guard !isStopped(), !Thread.current.isCancelled else { return }

            guard let dims = rfb.dimensions else {
                throw RFBError.handshakeFailed("no framebuffer dimensions")
            }
            stateLock.lock()
            client = rfb
            framebuffer = try Framebuffer(width: Int(dims.width), height: Int(dims.height))
            stateLock.unlock()

            // First update is a full request. Later requests are issued only
            // after the selected tier's cadence interval, and never while
            // suspended. This avoids accumulating unsolicited framebuffer
            // updates in the socket receive buffer.
            protocolWriteLock.lock()
            do {
                try rfb.requestFramebufferUpdate(incremental: false)
                protocolWriteLock.unlock()
            } catch {
                protocolWriteLock.unlock()
                throw error
            }

            let displayHost = rfb.serverName.isEmpty ? host.hostname : rfb.serverName
            guard !isStopped(), !Thread.current.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isStopped() else { return }
                self.isConnected = true
                self.status = "Connected: \(displayHost) (\(dims.width)×\(dims.height))"
            }

            while !isStopped() && !Thread.current.isCancelled {
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
                // Wait in short slices so Stop/Suspend takes effect promptly.
                while !isStopped() && !Thread.current.isCancelled {
                    let intervalMs = currentFrameRequestIntervalMs()
                    if intervalMs == Int.max {
                        Thread.sleep(forTimeInterval: 0.1)
                        continue
                    }
                    let deadline = ProcessInfo.processInfo.systemUptime + Double(intervalMs) / 1000.0
                    while !isStopped() && !Thread.current.isCancelled {
                        let remaining = deadline - ProcessInfo.processInfo.systemUptime
                        if remaining <= 0 { break }
                        if currentFrameRequestIntervalMs() == Int.max { break }
                        Thread.sleep(forTimeInterval: min(remaining, 0.05))
                    }
                    break
                }
                guard !isStopped(), !Thread.current.isCancelled else { break }
                protocolWriteLock.lock()
                do {
                    try rfb.requestFramebufferUpdate(incremental: true)
                    protocolWriteLock.unlock()
                } catch {
                    protocolWriteLock.unlock()
                    throw error
                }
            }
        } catch {
            protocolWriteLock.lock()
            stateLock.lock()
            connection?.close()
            stateLock.unlock()
            protocolWriteLock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.status = "Streaming stopped: \(error)"
            }
        }
    }

    /// Apply a quality tier without reconnect (Plan 10 §5).
    func applyQualityTier(_ tier: QualityTier) {
        stateLock.lock()
        qualityTier = tier
        stateLock.unlock()
    }

    private nonisolated func currentFrameRequestIntervalMs() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return qualityTier.frameRequestIntervalMs
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
            protocolWriteLock.lock()
            try client.sendKeyEvent(keysym: keysym, down: down)
            protocolWriteLock.unlock()
        } catch {
            protocolWriteLock.unlock()
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
            protocolWriteLock.lock()
            try client.sendPointerEvent(x: x, y: y, buttonMask: buttonMask)
            protocolWriteLock.unlock()
        } catch {
            protocolWriteLock.unlock()
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
