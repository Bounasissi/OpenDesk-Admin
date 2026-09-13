import XCTest
@testable import OpenDeskCore

final class HextileDecoderTests: XCTestCase {
    /// Buffered incremental reader for tests.
    private func reader(for data: Data) -> (Int) throws -> Data {
        var cursor = 0
        let bytes = data
        return { count in
            guard cursor + count <= bytes.count else { throw HextileDecoder.HextileError.truncatedTile }
            let chunk = bytes.subdata(in: cursor..<(cursor + count))
            cursor += count
            return chunk
        }
    }

    private var format: PixelFormat { .standard32 }

    /// BGRA pixel bytes for little-endian 32bpp shifts r16 g8 b0.
    private func pixelBytes(_ pixel: Pixel) -> [UInt8] {
        [pixel.blue, pixel.green, pixel.red, 0]
    }

    func testSolidTileFillsWholeRect() throws {
        let green = Pixel(red: 0, green: 255, blue: 0)
        var encoded = Data()
        encoded.append(0x02) // BackgroundSpecified
        encoded.append(contentsOf: pixelBytes(green))
        let pixels = try HextileDecoder.decode(width: 16, height: 16, format: format, read: reader(for: encoded))
        XCTAssertEqual(pixels.count, 256)
        for pixel in pixels { XCTAssertEqual(pixel, green) }
    }

    func testBackgroundPlusColouredSubrects() throws {
        let blue = Pixel(red: 0, green: 0, blue: 255)
        let yellow = Pixel(red: 255, green: 255, blue: 0)
        let magenta = Pixel(red: 255, green: 0, blue: 255)
        var encoded = Data()
        encoded.append(0x02 | 0x04 | 0x08 | 0x10) // bg + fg + subrects + coloured
        encoded.append(contentsOf: pixelBytes(blue))   // background
        encoded.append(contentsOf: pixelBytes(yellow)) // foreground (unused here)
        encoded.append(2) // two subrects
        // Subrect 1: coloured yellow at (0,0), size 8x8 → position 0x00, size (7<<4)|7 = 0x77
        encoded.append(contentsOf: pixelBytes(yellow))
        encoded.append(0x00)
        encoded.append(0x77)
        // Subrect 2: coloured magenta at (8,8), size 8x8 → position (8<<4)|8 = 0x88
        encoded.append(contentsOf: pixelBytes(magenta))
        encoded.append(0x88)
        encoded.append(0x77)

        let pixels = try HextileDecoder.decode(width: 16, height: 16, format: format, read: reader(for: encoded))
        XCTAssertEqual(pixels[0], yellow)          // inside subrect 1
        XCTAssertEqual(pixels[15 * 16 + 15], magenta) // bottom-right inside subrect 2
        XCTAssertEqual(pixels[8 * 16 + 0], blue)   // left edge outside subrects
        XCTAssertEqual(pixels[0 * 16 + 15], blue)  // right edge outside subrects
        XCTAssertEqual(pixels[15 * 16 + 0], blue)  // bottom-left outside subrects
    }

    func testForegroundSubrectsUseLastForeground() throws {
        let black = Pixel(red: 0, green: 0, blue: 0)
        let white = Pixel(red: 255, green: 255, blue: 255)
        var encoded = Data()
        encoded.append(0x04 | 0x08) // ForegroundSpecified + AnySubrects (no background spec → default black)
        encoded.append(contentsOf: pixelBytes(white))
        encoded.append(1)
        encoded.append(0x00) // at (0,0)
        encoded.append(0xFF) // size 16x16 → (15<<4)|15

        let pixels = try HextileDecoder.decode(width: 16, height: 16, format: format, read: reader(for: encoded))
        for pixel in pixels { XCTAssertEqual(pixel, white) }
        _ = black
    }

    func testRawTilePath() throws {
        let red = Pixel(red: 255, green: 0, blue: 0)
        var encoded = Data()
        encoded.append(0x01) // Raw
        for _ in 0..<16 * 16 {
            encoded.append(contentsOf: pixelBytes(red))
        }
        let pixels = try HextileDecoder.decode(width: 16, height: 16, format: format, read: reader(for: encoded))
        XCTAssertEqual(pixels.count, 256)
        for pixel in pixels { XCTAssertEqual(pixel, red) }
    }

    func testEdgeTilesSmallerThan16() throws {
        // 20x12 rect → tiles: (0,0) 16x12, (16,0) 4x12
        let cyan = Pixel(red: 0, green: 255, blue: 255)
        let orange = Pixel(red: 255, green: 165, blue: 0)
        var encoded = Data()
        // Tile 1: solid cyan
        encoded.append(0x02)
        encoded.append(contentsOf: pixelBytes(cyan))
        // Tile 2: raw orange
        encoded.append(0x01)
        for _ in 0..<4 * 12 {
            encoded.append(contentsOf: pixelBytes(orange))
        }
        let pixels = try HextileDecoder.decode(width: 20, height: 12, format: format, read: reader(for: encoded))
        XCTAssertEqual(pixels.count, 20 * 12)
        XCTAssertEqual(pixels[0], cyan)
        XCTAssertEqual(pixels[11 * 20 + 0], cyan)    // bottom-left (tile 1)
        XCTAssertEqual(pixels[0 * 20 + 16], orange)  // top of tile 2
        XCTAssertEqual(pixels[11 * 20 + 19], orange) // bottom-right (tile 2)
    }

    func testSubrectBeyondTileThrows() {
        let blue = Pixel(red: 0, green: 0, blue: 255)
        var encoded = Data()
        encoded.append(0x02 | 0x04 | 0x08 | 0x10)
        encoded.append(contentsOf: pixelBytes(blue))
        encoded.append(contentsOf: pixelBytes(blue))
        encoded.append(1)
        encoded.append(contentsOf: pixelBytes(blue))
        encoded.append(0x0F) // at (0,15)
        encoded.append(0x77) // size 8x8 → extends past 16
        XCTAssertThrowsError(try HextileDecoder.decode(width: 16, height: 16, format: format, read: reader(for: encoded)))
    }

    func testTruncatedStreamThrows() {
        var encoded = Data()
        encoded.append(0x02)
        encoded.append(0x00) // truncated background pixel
        XCTAssertThrowsError(try HextileDecoder.decode(width: 16, height: 16, format: format, read: reader(for: encoded)))
    }

    func testZeroSizedRectReturnsEmpty() throws {
        let pixels = try HextileDecoder.decode(width: 0, height: 0, format: format, read: reader(for: Data()))
        XCTAssertTrue(pixels.isEmpty)
    }
}

final class HextileBandwidthTests: XCTestCase {
    /// Validates the WAN claim: on desktop-like content (solid background +
    /// scattered windows), hextile encoding is dramatically smaller than raw.
    func testHextileIsFarSmallerThanRawForDesktopContent() throws {
        // 64x64 synthetic desktop: solid gray background, 4 "windows" as
        // coloured subrects per tile pattern.
        let width = 64, height = 64
        let background = Pixel(red: 128, green: 128, blue: 128)

        // --- Encode as hextile: 16 solid tiles + one coloured subrect each
        var hextile = Data()
        let tilesPerRow = width / 16
        for _ in 0..<(tilesPerRow * (height / 16)) {
            hextile.append(0x02 | 0x08)              // BackgroundSpecified + AnySubrects
            hextile.append(contentsOf: [UInt8(background.blue), UInt8(background.green), UInt8(background.red), 0])
            hextile.append(1)                        // one subrect ("window")
            hextile.append(0x44)                     // position (4,4)
            hextile.append(0x88)                     // size 9x9
        }
        let hextileSize = hextile.count

        // Raw size for the same rectangle
        let rawSize = width * height * 4

        XCTAssertLessThan(hextileSize, rawSize / 10,
                          "hextile should be >10x smaller for desktop-like content")
        // For 64x64: raw 16384 bytes vs 16 tiles × 8 bytes = 128 bytes
        // (subencoding + bg pixel + subrect count + position + size).
        XCTAssertEqual(hextileSize, 16 * 8)
        XCTAssertEqual(rawSize, 16_384)

        // Correctness: decode the encoded stream and verify solid + subrect
        var cursor = 0
        let pixels = try HextileDecoder.decode(width: width, height: height, format: .standard32) { count in
            let chunk = hextile.subdata(in: cursor..<(cursor + count))
            cursor += count
            return chunk
        }
        XCTAssertEqual(pixels.count, width * height)
        XCTAssertEqual(pixels[0], background)                       // outside subrect
        let insideSubrect = pixels[(4 + 1) * width + (4 + 1)]       // inside first subrect
        // Subrect colour is the tile foreground; not specified here (no 0x04 flag),
        // so it uses the foreground default (black after bg spec w/o fg flag).
        XCTAssertEqual(insideSubrect, Pixel(red: 0, green: 0, blue: 0))
    }
}

final class HextileEndToEndTests: XCTestCase {
    /// A full FramebufferUpdate with a hextile rect, parsed through
    /// RFBClient.readFramebufferUpdate against a scripted mock socket.
    func testReadFramebufferUpdateDecodesHextile() throws {
        // Server script: version, security, result, server-init, then update.
        let mock = MockRFBConnection(securityTypes: [1])

        // Append the update message AFTER ServerInit/name chunks.
        var update = Data([0x00, 0x00, 0x00, 0x01]) // 1 rect
        update.append(contentsOf: [0, 0, 0, 0, 0, 8, 0, 8]) // rect 0,0 8x8
        update.append(contentsOf: [0, 0, 0, 5])             // hextile
        let red = Pixel(red: 255, green: 0, blue: 0)
        update.append(0x02)                                  // solid bg tile
        update.append(contentsOf: [0x00, 0x00, 0xFF, 0x00])  // BGRA red
        mock.toSend.append(update)

        let client = RFBClient(connection: mock)
        try client.handshake(password: nil)
        let rects = try client.readFramebufferUpdate(format: .standard32)

        XCTAssertEqual(rects.count, 1)
        let rect = rects[0]
        XCTAssertEqual(rect.x, 0)
        XCTAssertEqual(rect.y, 0)
        XCTAssertEqual(rect.width, 8)
        XCTAssertEqual(rect.height, 8)
        for pixel in rect.pixels {
            XCTAssertEqual(pixel, red)
        }
    }

    func testSetEncodingsRequestsRawAndHextile() throws {
        let mock = MockRFBConnection()
        let client = RFBClient(connection: mock)
        try client.handshake(password: nil)
        mock.received.removeAll()
        try client.setEncodings()
        let message = mock.received.last!
        XCTAssertEqual(message[0], 0x02) // SetEncodings type
        let count = Int(message[3]) << 8 | Int(message[4])
        XCTAssertEqual(count, 2)
        // First encoding listed should be hextile (5), then raw (0).
        let enc1 = Int32(truncatingIfNeeded: UInt32(message[5]) << 24 | UInt32(message[6]) << 16 | UInt32(message[7]) << 8 | UInt32(message[8]))
        let enc2 = Int32(truncatingIfNeeded: UInt32(message[9]) << 24 | UInt32(message[10]) << 16 | UInt32(message[11]) << 8 | UInt32(message[12]))
        XCTAssertEqual(enc1, 5)
        XCTAssertEqual(enc2, 0)
    }
}
