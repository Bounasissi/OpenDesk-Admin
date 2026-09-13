import Foundation

/// Orchestrates a screen observation/control session with a client Mac.
/// Wraps RFBClient with session lifecycle management.
public final class ScreenSession {
    public enum Mode: String, Sendable {
        case observe
        case control
    }

    public enum SessionError: Error, Equatable {
        case notConnected
        case handshakeFailed(String)
    }

    public private(set) var host: Host
    public private(set) var mode: Mode
    public private(set) var client: RFBClient?
    public private(set) var connection: RFBConnection?
    public private(set) var isConnected: Bool = false

    public init(host: Host, mode: Mode = .observe) {
        self.host = host
        self.mode = mode
    }

    /// Connect and perform the RFB handshake.
    /// - Parameter password: VNC password if the client requires VNC auth.
    public func connect(password: String? = nil) throws {
        let tcp = try TCPConnection(host: host.hostname, port: UInt16(host.screenPort))
        connection = tcp
        let rfb = RFBClient(connection: tcp)
        do {
            try rfb.handshake(password: password)
        } catch {
            tcp.close()
            isConnected = false
            throw SessionError.handshakeFailed(String(describing: error))
        }
        client = rfb
        isConnected = true
    }

    /// Prepare the session for pixel streaming (pixel format + encodings + first full update request).
    public func beginStreaming() throws {
        guard let client, isConnected else { throw SessionError.notConnected }
        try client.setPixelFormat(.standard32)
        try client.setEncodings()
        try client.requestFramebufferUpdate(incremental: false)
    }

    public func disconnect() {
        connection?.close()
        connection = nil
        client = nil
        isConnected = false
    }

    deinit { disconnect() }
}
