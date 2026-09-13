import Foundation

/// A decoded framebuffer pixel (true-colour RGB).
public struct Pixel: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// A decoded rectangle from a FramebufferUpdate message.
public struct FramebufferRect: Equatable, Sendable {
    public var x: UInt16
    public var y: UInt16
    public var width: UInt16
    public var height: UInt16
    public var pixels: [Pixel]

    public init(x: UInt16, y: UInt16, width: UInt16, height: UInt16, pixels: [Pixel]) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// In-memory framebuffer composed from received updates.
public final class Framebuffer {
    public let width: Int
    public let height: Int
    private(set) var pixels: [Pixel]

    /// Oversized-framebuffer defense (Addendum §9): reject allocations that
    /// could exhaust memory from a malicious/errant server before they happen.
    public static let maximumDimension = 16_384

    public convenience init(width: Int, height: Int, fill: Pixel = Pixel(red: 0, green: 0, blue: 0)) throws {
        guard width > 0, height > 0, width <= Framebuffer.maximumDimension, height <= Framebuffer.maximumDimension else {
            throw ProtocolError.violation("framebuffer dimensions out of bounds: \(width)x\(height)")
        }
        self.init(uncheckedWidth: width, height: height, fill: fill)
    }

    init(uncheckedWidth: Int, height: Int, fill: Pixel = Pixel(red: 0, green: 0, blue: 0)) {
        self.width = uncheckedWidth
        self.height = height
        self.pixels = [Pixel](repeating: fill, count: uncheckedWidth * height)
    }

    /// Apply a decoded rectangle in place.
    public func apply(_ rect: FramebufferRect) {
        let rw = Int(rect.width)
        let rh = Int(rect.height)
        guard rect.pixels.count == rw * rh else { return }
        for row in 0..<rh {
            let destY = Int(rect.y) + row
            guard destY >= 0, destY < height else { continue }
            let srcStart = row * rw
            for col in 0..<rw {
                let destX = Int(rect.x) + col
                guard destX >= 0, destX < width else { continue }
                pixels[destY * width + destX] = rect.pixels[srcStart + col]
            }
        }
    }

    public func pixel(x: Int, y: Int) -> Pixel {
        pixels[y * width + x]
    }
}

/// Decoder for RFB FramebufferUpdate messages (§7.6) supporting the Raw
/// encoding (0). Apple's RectangularEncoding (RREE, -239) is a follow-up.
public enum FramebufferUpdateDecoder {
    public enum DecodeError: Error, Equatable {
        case truncatedMessage
        case unsupportedEncoding(Int32)
        case badRectangleDimensions
    }

    /// Decode one complete FramebufferUpdate message from a buffer.
    /// - Returns: the decoded rectangles and the number of bytes consumed.
    public static func decodeUpdate(from data: Data, format: PixelFormat = .standard32) throws -> (rects: [FramebufferRect], consumed: Int) {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { throw DecodeError.truncatedMessage }
        guard bytes[0] == 0x00 else { throw DecodeError.truncatedMessage } // not an update message

        let rectCount = Int(bytes[2]) << 8 | Int(bytes[3])
        var offset = 4
        var rects: [FramebufferRect] = []

        for _ in 0..<rectCount {
            guard bytes.count >= offset + 12 else { throw DecodeError.truncatedMessage }
            let x = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            let y = UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3])
            let w = UInt16(bytes[offset + 4]) << 8 | UInt16(bytes[offset + 5])
            let h = UInt16(bytes[offset + 6]) << 8 | UInt16(bytes[offset + 7])
            let encoding = Int32(truncatingIfNeeded:
                UInt32(bytes[offset + 8]) << 24 | UInt32(bytes[offset + 9]) << 16
                | UInt32(bytes[offset + 10]) << 8 | UInt32(bytes[offset + 11]))
            offset += 12

            guard encoding == 0 else { throw DecodeError.unsupportedEncoding(encoding) }
            let pixelCount = Int(w) * Int(h)
            guard pixelCount > 0 else { throw DecodeError.badRectangleDimensions }
            let bytesPerPixel = Int(format.bitsPerPixel) / 8
            let pixelBytes = pixelCount * bytesPerPixel
            guard bytes.count >= offset + pixelBytes else { throw DecodeError.truncatedMessage }

            var pixels: [Pixel] = []
            pixels.reserveCapacity(pixelCount)
            for i in 0..<pixelCount {
                let base = offset + i * bytesPerPixel
                pixels.append(decodePixel(bytes, base: base, format: format))
            }
            rects.append(FramebufferRect(x: x, y: y, width: w, height: h, pixels: pixels))
            offset += pixelBytes
        }
        return (rects, offset)
    }

    /// Decode one raw pixel per the negotiated pixel format (§7.7.1).
    static func decodePixel(_ bytes: [UInt8], base: Int, format: PixelFormat) -> Pixel {
        // Assemble the pixel value in native byte order.
        var value: UInt32 = 0
        if format.bigEndian == 1 {
            for i in 0..<4 {
                value = (value << 8) | UInt32(bytes[base + i])
            }
        } else {
            for i in stride(from: 3, through: 0, by: -1) {
                value = (value << 8) | UInt32(bytes[base + i])
            }
        }
        let r = scaleChannel(value >> format.redShift, max: format.redMax)
        let g = scaleChannel(value >> format.greenShift, max: format.greenMax)
        let b = scaleChannel(value >> format.blueShift, max: format.blueMax)
        return Pixel(red: r, green: g, blue: b)
    }

    /// Scale a channel from its max value back to 0-255.
    static func scaleChannel(_ raw: UInt32, max: UInt16) -> UInt8 {
        guard max > 0 else { return 0 }
        let channel = raw & UInt32(max)
        return UInt8((channel * 255 + UInt32(max) / 2) / UInt32(max))
    }
}
