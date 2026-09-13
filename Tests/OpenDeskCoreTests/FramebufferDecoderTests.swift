import XCTest
@testable import OpenDeskCore

final class FramebufferDecoderTests: XCTestCase {
    /// Build a synthetic single-rect Raw update: 2x2 red pixels.
    private func redRectUpdate(width: UInt16 = 2, height: UInt16 = 2, atX x: UInt16 = 0, atY y: UInt16 = 0) -> Data {
        var message = Data([0x00, 0x00, 0x00, 0x01]) // update, 1 rect
        message.append(contentsOf: [UInt8(x >> 8), UInt8(x & 0xFF)])
        message.append(contentsOf: [UInt8(y >> 8), UInt8(y & 0xFF)])
        message.append(contentsOf: [UInt8(width >> 8), UInt8(width & 0xFF)])
        message.append(contentsOf: [UInt8(height >> 8), UInt8(height & 0xFF)])
        message.append(contentsOf: [0, 0, 0, 0]) // Raw encoding
        // little-endian 32bpp, shifts r16 g8 b0: bytes = B G R pad
        for _ in 0..<Int(width) * Int(height) {
            message.append(contentsOf: [0x00, 0x00, 0xFF, 0x00]) // red
        }
        return message
    }

    func testDecodeSingleRect() throws {
        let (rects, consumed) = try FramebufferUpdateDecoder.decodeUpdate(from: redRectUpdate())
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(consumed, redRectUpdate().count)
        let rect = rects[0]
        XCTAssertEqual(rect.width, 2)
        XCTAssertEqual(rect.height, 2)
        XCTAssertEqual(rect.pixels.count, 4)
        for pixel in rect.pixels {
            XCTAssertEqual(pixel, Pixel(red: 255, green: 0, blue: 0))
        }
    }

    func testDecodeGreenAndBluePixels() throws {
        var message = Data([0x00, 0x00, 0x00, 0x02])
        // Rect 1: 1x1 green at (0,0)
        message.append(contentsOf: [0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0])
        message.append(contentsOf: [0x00, 0xFF, 0x00, 0x00])
        // Rect 2: 1x1 blue at (1,0)
        message.append(contentsOf: [0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0])
        message.append(contentsOf: [0xFF, 0x00, 0x00, 0x00])
        let (rects, _) = try FramebufferUpdateDecoder.decodeUpdate(from: message)
        XCTAssertEqual(rects[0].pixels[0], Pixel(red: 0, green: 255, blue: 0))
        XCTAssertEqual(rects[1].pixels[0], Pixel(red: 0, green: 0, blue: 255))
    }

    func testTruncatedMessageThrows() {
        let full = redRectUpdate()
        let truncated = full.prefix(30) // cut mid-pixel data
        XCTAssertThrowsError(try FramebufferUpdateDecoder.decodeUpdate(from: truncated))
    }

    func testNonUpdateMessageThrows() {
        XCTAssertThrowsError(try FramebufferUpdateDecoder.decodeUpdate(from: Data([0x01, 0, 0, 0])))
    }

    func testUnsupportedEncodingThrows() {
        var message = Data([0x00, 0x00, 0x00, 0x01])
        message.append(contentsOf: [0, 0, 0, 1, 0, 1, 0, 1])
        message.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xF1]) // -15
        XCTAssertThrowsError(try FramebufferUpdateDecoder.decodeUpdate(from: message)) { error in
            XCTAssertEqual(error as? FramebufferUpdateDecoder.DecodeError, .unsupportedEncoding(-15))
        }
    }

    func testFramebufferApplyAndComposite() throws {
        let framebuffer = try Framebuffer(width: 4, height: 4)
        let (rects, _) = try FramebufferUpdateDecoder.decodeUpdate(from: redRectUpdate(width: 2, height: 2, atX: 2, atY: 2))
        framebuffer.apply(rects[0])
        XCTAssertEqual(framebuffer.pixel(x: 0, y: 0), Pixel(red: 0, green: 0, blue: 0))
        XCTAssertEqual(framebuffer.pixel(x: 2, y: 2), Pixel(red: 255, green: 0, blue: 0))
        XCTAssertEqual(framebuffer.pixel(x: 3, y: 3), Pixel(red: 255, green: 0, blue: 0))
        // Rectangle clipping: pixel at (4, 4) would be out of bounds — no crash
    }

    func testScaleChannelRoundTrip() {
        XCTAssertEqual(FramebufferUpdateDecoder.scaleChannel(255, max: 255), 255)
        XCTAssertEqual(FramebufferUpdateDecoder.scaleChannel(128, max: 255), 128)
        XCTAssertEqual(FramebufferUpdateDecoder.scaleChannel(0, max: 0), 0)
    }
}

final class InputEventTests: XCTestCase {
    func testKeyEventMessageLayout() throws {
        let mock = MockRFBConnection()
        let client = RFBClient(connection: mock)
        try client.handshake(password: nil)
        mock.received.removeAll()
        try client.sendKeyEvent(keysym: 0x61, down: true) // 'a'
        let message = mock.received.last!
        XCTAssertEqual(message.count, 8)
        XCTAssertEqual(message[0], 0x04) // type
        XCTAssertEqual(message[1], 1) // down
        XCTAssertEqual(message[7], 0x61) // keysym LSB (bytes 4-7 hold the keysym)
        XCTAssertEqual(Array(message[4...7]), [0, 0, 0, 0x61])
    }

    func testPointerEventMessageLayout() throws {
        let mock = MockRFBConnection()
        let client = RFBClient(connection: mock)
        try client.handshake(password: nil)
        mock.received.removeAll()
        try client.sendPointerEvent(x: 1024, y: 768, buttonMask: 0x01)
        let message = mock.received.last!
        XCTAssertEqual(message.count, 6)
        XCTAssertEqual(message[0], 0x05) // type
        XCTAssertEqual(message[1], 0x01) // left button
        XCTAssertEqual(message[2], 4) // 1024 >> 8
        XCTAssertEqual(message[4], 3) // 768 >> 8
    }
}
