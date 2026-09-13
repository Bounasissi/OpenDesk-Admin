import XCTest
@testable import OpenDeskCore

/// Full-stack tests against a real loopback TCP server: handshake, VNC DES
/// auth, pixel decoding, and input events — the complete client protocol
/// path, without touching any macOS settings.
final class LoopbackEndToEndTests: XCTestCase {
    /// Runs the client-side closure on a background queue and joins it.
    private func runClient(_ work: @escaping () throws -> Void) -> Error? {
        let group = DispatchGroup()
        group.enter()
        var caught: Error?
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try work()
            } catch {
                caught = error
            }
        }
        group.wait()
        return caught
    }

    func testAuthenticatedHandshakeAndRawPixelDecode() throws {
        let server = LoopbackRFBServer(password: "secret123")
        let port = try server.start()
        defer { server.stop() }

        // Connect + handshake first (server completes handshake concurrently).
        var handshakeError: Error?
        var clientConnection: TCPConnection?
        var client: RFBClient?

        let handshakeGroup = DispatchGroup()
        handshakeGroup.enter()
        DispatchQueue.global().async {
            defer { handshakeGroup.leave() }
            do {
                let tcp = try TCPConnection(host: "127.0.0.1", port: port)
                let rfb = RFBClient(connection: tcp)
                try rfb.handshake(password: "secret123")
                clientConnection = tcp
                client = rfb
            } catch {
                handshakeError = error
            }
        }

        try server.waitForConnection()
        try server.performServerHandshake(dimensions: (8, 8), name: "LoopbackTest")
        handshakeGroup.wait()
        XCTAssertNil(handshakeError)
        XCTAssertEqual(client?.serverName, "LoopbackTest")

        // Client requests a full update; server delivers a solid red frame.
        let updateGroup = DispatchGroup()
        updateGroup.enter()
        var decodedRects: [FramebufferRect] = []
        var updateError: Error?
        DispatchQueue.global().async {
            defer { updateGroup.leave() }
            do {
                guard let client else { throw LoopbackRFBServer.ServerError.notConnected }
                try client.requestFramebufferUpdate(incremental: false)
                decodedRects = try client.readFramebufferUpdate(format: .standard32)
                clientConnection?.close()
            } catch {
                updateError = error
            }
        }
        Thread.sleep(forTimeInterval: 0.2) // let the request reach the server
        try server.sendSolidRawUpdate(width: 8, height: 8, pixel: Pixel(red: 255, green: 0, blue: 0))
        updateGroup.wait()

        XCTAssertNil(updateError)
        XCTAssertEqual(decodedRects.count, 1)
        XCTAssertEqual(decodedRects[0].width, 8)
        XCTAssertEqual(decodedRects[0].height, 8)
        for pixel in decodedRects[0].pixels {
            XCTAssertEqual(pixel, Pixel(red: 255, green: 0, blue: 0))
        }
    }

    func testNoAuthHandshakeSucceeds() throws {
        let server = LoopbackRFBServer(password: nil)
        let port = try server.start()
        defer { server.stop() }

        var handshakeError: Error?
        var connectedName = ""

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                let tcp = try TCPConnection(host: "127.0.0.1", port: port)
                let client = RFBClient(connection: tcp)
                try client.handshake(password: nil)
                connectedName = client.serverName
                tcp.close()
            } catch {
                handshakeError = error
            }
        }
        try server.waitForConnection()
        try server.performServerHandshake(dimensions: (16, 16))
        group.wait()

        XCTAssertNil(handshakeError)
        XCTAssertEqual(connectedName, "LoopbackTest")
    }

    func testWrongPasswordIsRejected() throws {
        let server = LoopbackRFBServer(password: "correct-password")
        let port = try server.start()
        defer { server.stop() }

        var handshakeError: Error?
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                let tcp = try TCPConnection(host: "127.0.0.1", port: port)
                let client = RFBClient(connection: tcp)
                try client.handshake(password: "wrong-password")
                tcp.close()
            } catch {
                handshakeError = error
            }
        }

        try server.waitForConnection()
        // Server-side auth check fails → close without SecurityResult OK.
        do {
            try server.performServerHandshake(dimensions: (8, 8))
        } catch {
            // expected: auth mismatch on the server side
        }
        server.stop() // drop the connection
        group.wait()

        XCTAssertNotNil(handshakeError, "client must see an error for a wrong password")
    }

    func testInputEventsReachTheServer() throws {
        let server = LoopbackRFBServer(password: "pw")
        let port = try server.start()
        defer { server.stop() }

        var handshakeError: Error?
        let sendGroup = DispatchGroup()
        sendGroup.enter()
        DispatchQueue.global().async {
            defer { sendGroup.leave() }
            do {
                let tcp = try TCPConnection(host: "127.0.0.1", port: port)
                let client = RFBClient(connection: tcp)
                try client.handshake(password: "pw")
                try client.sendKeyEvent(keysym: 0x61, down: true)      // 'a' down
                try client.sendKeyEvent(keysym: 0x61, down: false)     // 'a' up
                try client.sendPointerEvent(x: 100, y: 50, buttonMask: 1)
                try client.sendCutText("hello")
                Thread.sleep(forTimeInterval: 0.3)
                tcp.close()
            } catch {
                handshakeError = error
            }
        }

        try server.waitForConnection()
        try server.performServerHandshake(dimensions: (32, 32))

        let keyDown = try server.receive(8)
        let keyUp = try server.receive(8)
        let pointer = try server.receive(6)
        // CutText wire format (§25 gap #11): type 0x06, padding(3),
        // length(4, big-endian), then the text.
        let cutHeader = try server.receive(8)
        let cutText = try server.receive(5)
        sendGroup.wait()

        XCTAssertNil(handshakeError)
        XCTAssertEqual(keyDown.first, 0x04)
        XCTAssertEqual(keyDown[1], 1)
        XCTAssertEqual(Array(keyDown[4...7]), [0, 0, 0, 0x61])
        XCTAssertEqual(keyUp.first, 0x04)
        XCTAssertEqual(keyUp[1], 0)
        XCTAssertEqual(pointer.first, 0x05)
        XCTAssertEqual(pointer[1], 1)
        XCTAssertEqual(Array(pointer[2...3]), [0, 100])
        XCTAssertEqual(Array(pointer[4...5]), [0, 50])
        XCTAssertEqual(cutHeader.first, 0x06, "ServerCutText message type")
        XCTAssertEqual(Array(cutHeader[1...3]), [0, 0, 0], "padding")
        let cutLength = (UInt32(cutHeader[4]) << 24) | (UInt32(cutHeader[5]) << 16) | (UInt32(cutHeader[6]) << 8) | UInt32(cutHeader[7])
        XCTAssertEqual(cutLength, 5)
        XCTAssertEqual(cutText, Data("hello".utf8))
        _ = server.recordedInputBytes()
    }
}
