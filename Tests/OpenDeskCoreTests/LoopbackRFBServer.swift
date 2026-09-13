import Foundation
@testable import OpenDeskCore

/// A real loopback RFB/VNC server used to exercise the client over actual TCP.
/// Scripted, not shipped: validates handshake, VNC DES auth, framebuffer
/// updates, and input events without touching any macOS settings.
final class LoopbackRFBServer {
    enum ServerError: Error {
        case notConnected
        case authMismatch
        case socketFailure
    }

    let password: String?
    private var listenFD: Int32 = -1
    private var clientFD: Int32 = -1
    private(set) var port: UInt16 = 0
    private(set) var receivedInput: [Data] = []
    private let lock = NSLock()

    init(password: String? = nil) {
        self.password = password
    }

    /// Bind on loopback, start accepting in the background, return the port.
    @discardableResult
    func start() throws -> UInt16 {
        listenFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw ServerError.socketFailure }

        var reuse: Int32 = 1
        setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bindOK = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0 else { throw ServerError.socketFailure }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let gotName = withUnsafeMutablePointer(to: &bound) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(listenFD, sockPtr, &len)
            }
        }
        guard gotName == 0 else { throw ServerError.socketFailure }
        port = UInt16(bigEndian: bound.sin_port)

        guard listen(listenFD, 1) == 0 else { throw ServerError.socketFailure }

        // Accept in the background so the test can connect immediately.
        let fd = listenFD
        Thread.detachNewThread { [weak self] in
            let accepted = accept(fd, nil, nil)
            self?.lock.lock()
            self?.clientFD = accepted
            self?.lock.unlock()
        }
        return port
    }

    /// Block until a client is connected.
    func waitForConnection(timeout: TimeInterval = 5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let fd = clientFD
            lock.unlock()
            if fd >= 0 { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw ServerError.notConnected
    }

    // MARK: - Wire I/O

    func send(_ data: Data) throws {
        lock.lock()
        let fd = clientFD
        lock.unlock()
        guard fd >= 0 else { throw ServerError.notConnected }
        var bytes = [UInt8](data)
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { raw in
                Darwin.send(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
            }
            if n <= 0 { throw ServerError.socketFailure }
            sent += n
        }
    }

    func receive(_ count: Int, timeout: TimeInterval = 5) throws -> Data {
        lock.lock()
        let fd = clientFD
        lock.unlock()
        guard fd >= 0 else { throw ServerError.notConnected }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: count)
        let deadline = Date().addingTimeInterval(timeout)
        while data.count < count && Date() < deadline {
            let n = buffer.withUnsafeMutableBytes { raw in
                recv(fd, raw.baseAddress!.advanced(by: data.count), count - data.count, 0)
            }
            if n > 0 {
                data.append(contentsOf: buffer[0..<n])
            } else if n == 0 {
                throw ServerError.socketFailure
            }
            // n < 0: would-block (no socket timeout set on this FD) — poll.
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard data.count == count else { throw ServerError.notConnected }
        return data
    }

    /// Perform the server side of the 3.8 handshake with VNC auth.
    func performServerHandshake(dimensions: (UInt16, UInt16) = (64, 48), name: String = "LoopbackTest") throws {
        try send(Data("RFB 003.008\n".utf8))
        let clientVersion = try receive(12)
        guard String(data: clientVersion, encoding: .ascii) == "RFB 003.008\n" else {
            throw ServerError.authMismatch
        }

        if let password, !password.isEmpty {
            try send(Data([1, RFBSecurityType.vncAuthentication.rawValue]))
            let choice = try receive(1)
            guard choice.first == RFBSecurityType.vncAuthentication.rawValue else {
                throw ServerError.authMismatch
            }
            // Challenge/response using the same DES as the client library.
            let challenge = Data((0..<16).map { UInt8(truncatingIfNeeded: $0 * 17 + 3) })
            try send(challenge)
            let response = try receive(16)
            let expected = VNCAuth.encryptChallenge(challenge, password: password)
            guard response == expected else { throw ServerError.authMismatch }
            try send(Data([0, 0, 0, 0])) // SecurityResult OK
        } else {
            try send(Data([1, RFBSecurityType.none.rawValue]))
            let choice = try receive(1)
            guard choice.first == RFBSecurityType.none.rawValue else {
                throw ServerError.authMismatch
            }
            try send(Data([0, 0, 0, 0]))
        }

        // ClientInit: share flag
        _ = try receive(1)

        // ServerInit
        var serverInit = Data()
        serverInit.append(contentsOf: [UInt8(dimensions.0 >> 8), UInt8(dimensions.0 & 0xFF)])
        serverInit.append(contentsOf: [UInt8(dimensions.1 >> 8), UInt8(dimensions.1 & 0xFF)])
        serverInit.append(contentsOf: PixelFormat.standard32.serialized())
        let nameBytes = Array(name.utf8)
        serverInit.append(contentsOf: [
            UInt8(nameBytes.count >> 24 & 0xFF), UInt8(nameBytes.count >> 16 & 0xFF),
            UInt8(nameBytes.count >> 8 & 0xFF), UInt8(nameBytes.count & 0xFF),
        ])
        serverInit.append(contentsOf: nameBytes)
        try send(serverInit)
    }

    /// Send a solid-colour Raw framebuffer update covering the full framebuffer.
    func sendSolidRawUpdate(width: UInt16, height: UInt16, pixel: Pixel) throws {
        var update = Data([0x00, 0x00, 0x00, 0x01])
        update.append(contentsOf: [0, 0, 0, 0]) // x, y = 0
        update.append(contentsOf: [UInt8(width >> 8), UInt8(width & 0xFF)])
        update.append(contentsOf: [UInt8(height >> 8), UInt8(height & 0xFF)])
        update.append(contentsOf: [0, 0, 0, 0]) // Raw
        for _ in 0..<Int(width) * Int(height) {
            update.append(contentsOf: [pixel.blue, pixel.green, pixel.red, 0])
        }
        try send(update)
    }

    /// Capture raw input bytes as the client sends them.
    func startInputCapture() {
        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            while true {
                do {
                    let chunk = try self.receive(1, timeout: 0.5)
                    self.lock.lock()
                    self.receivedInput.append(chunk)
                    self.lock.unlock()
                } catch {
                    break
                }
            }
        }
    }

    func recordedInputBytes() -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        return receivedInput.flatMap { [UInt8]($0) }
    }

    func stop() {
        lock.lock()
        let fd = clientFD
        clientFD = -1
        lock.unlock()
        if fd >= 0 { Darwin.close(fd) }
        if listenFD >= 0 { Darwin.close(listenFD); listenFD = -1 }
    }
}
