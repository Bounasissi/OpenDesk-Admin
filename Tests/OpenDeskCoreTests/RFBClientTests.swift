import XCTest
@testable import OpenDeskCore

/// Mock RFB transport that replays a scripted server-side handshake.
final class MockRFBConnection: RFBConnection {
    var toSend: [Data] = []
    var received: [Data] = []

    init(serverVersion: String = "RFB 003.008\n", securityTypes: [UInt8] = [1]) {
        toSend.append(Data(serverVersion.utf8))
        toSend.append(Data([UInt8(securityTypes.count)]))
        toSend.append(Data(securityTypes))
        // SecurityResult OK (4 bytes)
        toSend.append(Data([0, 0, 0, 0]))
        // ServerInit: width 1920, height 1080, pixel format 16 bytes, name len 4, "Test"
        var serverInit = Data()
        serverInit.append(contentsOf: [0x07, 0x80]) // 1920
        serverInit.append(contentsOf: [0x04, 0x38]) // 1080
        serverInit.append(contentsOf: [UInt8](repeating: 0, count: 16))
        serverInit.append(contentsOf: [0, 0, 0, 4])
        toSend.append(serverInit)
        toSend.append(Data("Test".utf8))
    }

    func readExactly(_ count: Int) throws -> Data {
        guard !toSend.isEmpty else { throw RFBError.connectionClosed }
        var data = Data()
        while data.count < count {
            guard !toSend.isEmpty else { throw RFBError.connectionClosed }
            let next = toSend.removeFirst()
            if data.count + next.count <= count {
                data.append(next)
            } else {
                let needed = count - data.count
                data.append(next.prefix(needed))
                toSend[0] = next.dropFirst(needed)
            }
        }
        return data
    }

    func write(_ data: Data) throws {
        received.append(data)
    }

    func close() {}
}

final class RFBClientTests: XCTestCase {
    func testVersionParse() throws {
        let version = try RFBVersion.parse(Data("RFB 003.008\n".utf8))
        XCTAssertEqual(version.major, 3)
        XCTAssertEqual(version.minor, 8)
    }

    func testVersionParseRejectsGarbage() {
        XCTAssertThrowsError(try RFBVersion.parse(Data("garbage".utf8)))
    }

    func testVersionSerializeRoundTrip() throws {
        let original = RFBVersion(major: 3, minor: 8)
        let parsed = try RFBVersion.parse(original.serialized())
        XCTAssertEqual(original, parsed)
    }

    func testHandshakeWithNoneSecurity() throws {
        let mock = MockRFBConnection(securityTypes: [RFBSecurityType.none.rawValue])
        let client = RFBClient(connection: mock)
        try client.handshake(password: nil)

        XCTAssertEqual(client.dimensions, FramebufferDimensions(width: 1920, height: 1080))
        XCTAssertEqual(client.serverName, "Test")
        XCTAssertEqual(client.negotiatedSecurity, .none)

        // Verify client replied with version, chosen security type, and ClientInit share=1
        XCTAssertEqual(mock.received.count, 3)
        XCTAssertEqual(mock.received[0], Data("RFB 003.008\n".utf8))
        XCTAssertEqual(mock.received[1], Data([1])) // security: none
        XCTAssertEqual(mock.received[2], Data([0x01])) // share
    }

    func testHandshakeRejectsUnsupportedSecurity() {
        let mock = MockRFBConnection(securityTypes: [30]) // Apple's proprietary auth
        let client = RFBConnectionless(client: mock)
        XCTAssertThrowsError(try client.handshake(password: nil)) { error in
            XCTAssertEqual(error as? RFBError, .unsupportedSecurityType(30))
        }
    }

    func testPixelFormatSerialization() {
        let data = PixelFormat.standard32.serialized()
        XCTAssertEqual(data.count, 16)
        XCTAssertEqual(data[0], 32) // bits per pixel
        XCTAssertEqual(data[3], 1) // true colour
    }

    func testFramebufferUpdateRequestMessage() throws {
        let mock = MockRFBConnection()
        let client = RFBClient(connection: mock)
        try client.handshake(password: nil)
        try client.requestFramebufferUpdate(incremental: true)
        let request = mock.received.last!
        XCTAssertEqual(request[0], 0x03) // message type
        XCTAssertEqual(request[1], 1) // incremental
        XCTAssertEqual(request.count, 10)
    }

    /// Helper to keep test name short; equivalent to RFBClient.
    private func RFBConnectionless(client mock: MockRFBConnection) -> RFBClient {
        RFBClient(connection: mock)
    }
}
