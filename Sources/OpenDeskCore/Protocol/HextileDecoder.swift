import Foundation

/// Hextile encoding decoder (RFC 6143 §7.7.4, encoding number 5).
/// Rectangles are split into 16×16 tiles; each tile is either raw pixels,
/// a solid background colour, or background + optional coloured/solid
/// subrectangles. Bitwise subencoding flags:
///   1 Raw, 2 BackgroundSpecified, 4 ForegroundSpecified,
///   8 AnySubrects, 16 SubrectsColoured
public enum HextileDecoder {
    public enum HextileError: Error, Equatable {
        case truncatedTile
        case invalidSubrect
        case tileTooLarge
    }

    /// Subencoding flag values.
    enum Flags: UInt8 {
        case raw = 0x01
        case backgroundSpecified = 0x02
        case foregroundSpecified = 0x04
        case anySubrects = 0x08
        case subrectsColoured = 0x10
    }

    /// Tile edge length (RFC 6143: 16).
    static let tileSize = 16

    /// Decode a hextile-encoded rectangle into row-major pixels.
    /// - Parameters:
    ///   - width/height: the rectangle dimensions.
    ///   - format: the negotiated pixel format.
    ///   - read: incremental reader over the encoded bytes (returns exactly `n` bytes or throws).
    public static func decode(width: Int, height: Int, format: PixelFormat, read: (Int) throws -> Data) throws -> [Pixel] {
        guard width > 0, height > 0 else { return [] }
        let bytesPerPixel = Int(format.bitsPerPixel) / 8
        var output = [Pixel](repeating: Pixel(red: 0, green: 0, blue: 0), count: width * height)

        var background = Pixel(red: 0, green: 0, blue: 0)
        var foreground = Pixel(red: 0, green: 0, blue: 0)

        // Tile raster order: left to right, top to bottom; edge tiles smaller.
        var tileY = 0
        while tileY < height {
            var tileX = 0
            while tileX < width {
                let tileW = Swift.min(tileSize, width - tileX)
                let tileH = Swift.min(tileSize, height - tileY)

                guard let subencodingByte = try read(1).first else { throw HextileError.truncatedTile }
                try decodeTile(
                    subencoding: subencodingByte,
                    tileWidth: tileW, tileHeight: tileH,
                    tileX: tileX, tileY: tileY,
                    width: width, bytesPerPixel: bytesPerPixel,
                    format: format,
                    background: &background, foreground: &foreground,
                    output: &output,
                    read: read
                )
                tileX += tileSize
            }
            tileY += tileSize
        }
        return output
    }

    private static func decodeTile(
        subencoding: UInt8,
        tileWidth: Int, tileHeight: Int,
        tileX: Int, tileY: Int,
        width: Int, bytesPerPixel: Int,
        format: PixelFormat,
        background: inout Pixel,
        foreground: inout Pixel,
        output: inout [Pixel],
        read: (Int) throws -> Data
    ) throws {
        if subencoding & Flags.raw.rawValue != 0 {
            // Raw tile: exact tile dimensions of uncompressed pixels.
            let count = tileWidth * tileHeight
            let data = try read(count * bytesPerPixel)
            let bytes = [UInt8](data)
            guard bytes.count == count * bytesPerPixel else { throw HextileError.truncatedTile }
            for i in 0..<count {
                let pixel = FramebufferUpdateDecoder.decodePixel(bytes, base: i * bytesPerPixel, format: format)
                let row = i / tileWidth
                let col = i % tileWidth
                let outIndex = (tileY + row) * width + (tileX + col)
                if outIndex < output.count { output[outIndex] = pixel }
            }
            return
        }

        if subencoding & Flags.backgroundSpecified.rawValue != 0 {
            let bgData = try read(bytesPerPixel)
            background = FramebufferUpdateDecoder.decodePixel([UInt8](bgData), base: 0, format: format)
        }

        // Fill the tile with the background first (solid tile fast path).
        for row in 0..<tileHeight {
            for col in 0..<tileWidth {
                let outIndex = (tileY + row) * width + (tileX + col)
                if outIndex < output.count { output[outIndex] = background }
            }
        }

        if subencoding & Flags.foregroundSpecified.rawValue != 0 {
            let fgData = try read(bytesPerPixel)
            foreground = FramebufferUpdateDecoder.decodePixel([UInt8](fgData), base: 0, format: format)
        }

        if subencoding & Flags.anySubrects.rawValue != 0 {
            guard let countByte = try read(1).first else { throw HextileError.truncatedTile }
            let subrectCount = Int(countByte)
            let coloured = subencoding & Flags.subrectsColoured.rawValue != 0

            for _ in 0..<subrectCount {
                var colour = foreground
                if coloured {
                    let colourData = try read(bytesPerPixel)
                    colour = FramebufferUpdateDecoder.decodePixel([UInt8](colourData), base: 0, format: format)
                }
                guard let position = try read(1).first, let size = try read(1).first else {
                    throw HextileError.truncatedTile
                }
                let sx = Int(position >> 4)        // x offset within tile
                let sy = Int(position & 0x0F)      // y offset within tile
                let sw = Int(size >> 4) + 1        // stored as w-1
                let sh = Int(size & 0x0F) + 1      // stored as h-1
                guard sx < tileWidth, sy < tileHeight, sx + sw <= tileWidth, sy + sh <= tileHeight else {
                    throw HextileError.invalidSubrect
                }
                for row in 0..<sh {
                    for col in 0..<sw {
                        let outIndex = (tileY + sy + row) * width + (tileX + sx + col)
                        if outIndex < output.count { output[outIndex] = colour }
                    }
                }
            }
        }
    }
}
