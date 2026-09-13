import XCTest
import AppKit
@testable import OpenDeskCore

final class KeysymMapTests: XCTestCase {
    func testASCIICharactersMapToTheirOwnKeysyms() {
        XCTAssertEqual(KeysymMap.keysym(forCharacter: "a"), 0x61)
        XCTAssertEqual(KeysymMap.keysym(forCharacter: "Z"), 0x5A)
        XCTAssertEqual(KeysymMap.keysym(forCharacter: "0"), 0x30)
        XCTAssertEqual(KeysymMap.keysym(forCharacter: " "), 0x20)
        XCTAssertEqual(KeysymMap.keysym(forCharacter: "~"), 0x7E)
    }

    func testLatin1RangeMapsDirectly() {
        XCTAssertEqual(KeysymMap.keysym(forCharacter: "é"), 0xE9)
    }

    func testSpecialVirtualKeys() {
        XCTAssertEqual(KeysymMap.keysym(forVirtualKey: 0x24), 0xFF0D) // return
        XCTAssertEqual(KeysymMap.keysym(forVirtualKey: 0x7E), 0xFF52) // up
        XCTAssertEqual(KeysymMap.keysym(forVirtualKey: 0x7B), 0xFF51) // left
        XCTAssertEqual(KeysymMap.keysym(forVirtualKey: 0x33), 0xFF08) // backspace
        XCTAssertEqual(KeysymMap.keysym(forVirtualKey: 0x75), 0xFFFF) // forward delete
    }

    func testFunctionKeys() {
        XCTAssertEqual(KeysymMap.keysym(forVirtualKey: 0x7A), 0xFFBE) // F1
        XCTAssertEqual(KeysymMap.keysym(forVirtualKey: 0x6F), 0xFFC9) // F12
    }

    func testCharacterPreferredOverVirtualKey() {
        // 'a' typed with shift still resolves to keysym for 'A'
        XCTAssertEqual(KeysymMap.keysym(character: "A", keyCode: 0x00), 0x41)
        // Unknown character falls back to virtual key table
        XCTAssertEqual(KeysymMap.keysym(character: "\u{F702}", keyCode: 0x7E), 0xFF52) // up arrow
    }

    func testUnknownKeyReturnsNil() {
        XCTAssertNil(KeysymMap.keysym(character: "😀", keyCode: 0xFE))
    }
}

final class FramebufferRendererTests: XCTestCase {
    func testRenderDimensionsAndPixelPlacement() throws {
        let framebuffer = Framebuffer(width: 4, height: 2)
        let red = OpenDeskCore.Pixel(red: 255, green: 0, blue: 0)
        let blue = OpenDeskCore.Pixel(red: 0, green: 0, blue: 255)
        // Fill row 0 red, row 1 blue
        for x in 0..<4 {
            framebuffer.apply(FramebufferRect(
                x: UInt16(x), y: 0, width: 1, height: 1, pixels: [red]
            ))
            framebuffer.apply(FramebufferRect(
                x: UInt16(x), y: 1, width: 1, height: 1, pixels: [blue]
            ))
        }
        let image = try FramebufferRenderer.cgImage(from: framebuffer)
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 2)

        // Verify raw pixel bytes via the data provider.
        let data = image.dataProvider!.data
        let byteCount = CFDataGetLength(data)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        CFDataGetBytes(data, CFRange(location: 0, length: byteCount), &bytes)
        // Row 0, pixel 0: RGBA = FF 00 00 FF (premultiplied opaque red)
        XCTAssertEqual(Array(bytes[0..<4]), [255, 0, 0, 255])
        // Row 1, pixel 0: RGBA = 00 00 FF FF
        let row1 = (4 * 4)
        XCTAssertEqual(Array(bytes[row1..<(row1 + 4)]), [0, 0, 255, 255])
    }

    func testInvalidDimensionsThrow() {
        let empty = Framebuffer(width: 0, height: 0)
        XCTAssertThrowsError(try FramebufferRenderer.cgImage(from: empty)) { error in
            XCTAssertEqual(error as? FramebufferRenderer.RenderError, .invalidDimensions)
        }
    }

    func testNSImageConvenience() throws {
        let framebuffer = Framebuffer(width: 2, height: 2, fill: OpenDeskCore.Pixel(red: 1, green: 2, blue: 3))
        let nsImage = try FramebufferRenderer.nsImage(from: framebuffer)
        XCTAssertEqual(nsImage.size.width, 2)
        XCTAssertEqual(nsImage.size.height, 2)
    }
}
