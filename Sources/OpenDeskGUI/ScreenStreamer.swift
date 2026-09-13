import Foundation
import AppKit
import SwiftUI
import OpenDeskCore

/// Live screen streaming session for the GUI viewer.
/// Owns a background thread running the RFB update loop and publishes
/// decoded frames to SwiftUI on the main actor.
@MainActor
final class ScreenStreamer: ObservableObject {
    @Published var frame: NSImage?
    @Published var status: String = "Idle."
    @Published var isConnected = false
    @Published var controlMode = false

    private var thread: Thread?
    private var stopFlag = false
    private let stateLock = NSLock()

    // Protocol objects accessed from both the update thread and the main
    // thread (input events) — guarded by stateLock.
    private var client: RFBClient?
    private var connection: RFBConnection?
    private var framebuffer: Framebuffer?

    let host: OpenDeskCore.Host
    let password: String?

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

    private func runUpdateLoop(host: OpenDeskCore.Host, password: String?) {
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
            framebuffer = Framebuffer(width: Int(dims.width), height: Int(dims.height))
            stateLock.unlock()

            // First update is a full request; subsequent are incremental.
            try rfb.requestFramebufferUpdate(incremental: false)

            DispatchQueue.main.async { [weak self] in
                self?.isConnected = true
                self?.status = "Connected: \(rfb.serverName.isEmpty ? host.hostname : rfb.serverName) (\(dims.width)×\(dims.height))"
            }

            var firstUpdate = true
            while !isStopped() && !Thread.current.isCancelled {
                let rects = try rfb.readFramebufferUpdate(format: .standard32)
                stateLock.lock()
                let fb = framebuffer
                stateLock.unlock()
                if let fb {
                    for rect in rects { fb.apply(rect) }
                    let image = try FramebufferRenderer.nsImage(from: fb)
                    DispatchQueue.main.async { [weak self] in
                        self?.frame = image
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

    private func isStopped() -> Bool {
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
