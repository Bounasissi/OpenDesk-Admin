import Foundation
import CoreGraphics
import AppKit

/// Renders a decoded Framebuffer into a CGImage for display.
public enum FramebufferRenderer {
    public enum RenderError: Error, Equatable {
        case contextCreationFailed
        case invalidDimensions
    }

    /// Convert a framebuffer to a 32bpp RGBA (premultiplied, fully opaque) CGImage.
    public static func cgImage(from framebuffer: Framebuffer) throws -> CGImage {
        guard framebuffer.width > 0, framebuffer.height > 0 else {
            throw RenderError.invalidDimensions
        }
        let width = framebuffer.width
        let height = framebuffer.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for (index, pixel) in framebuffer.pixels.enumerated() {
            rgba[index * 4 + 0] = pixel.red
            rgba[index * 4 + 1] = pixel.green
            rgba[index * 4 + 2] = pixel.blue
            rgba[index * 4 + 3] = 255
        }

        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw RenderError.contextCreationFailed
        }
        guard let image = context.makeImage() else {
            throw RenderError.contextCreationFailed
        }
        return image
    }

    /// NSImage convenience for SwiftUI/AppKit display paths.
    public static func nsImage(from framebuffer: Framebuffer) throws -> NSImage {
        let image = try cgImage(from: framebuffer)
        return NSImage(cgImage: image, size: NSSize(width: framebuffer.width, height: framebuffer.height))
    }
}
