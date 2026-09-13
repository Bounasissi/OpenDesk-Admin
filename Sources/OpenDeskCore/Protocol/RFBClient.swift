import Foundation

/// RFB (Remote Framebuffer, RFC 6143) pixel-format descriptor.
public struct PixelFormat: Equatable, Sendable {
    public var bitsPerPixel: UInt8
    public var depth: UInt8
    public var bigEndian: UInt8
    public var trueColour: UInt8
    public var redMax: UInt16
    public var greenMax: UInt16
    public var blueMax: UInt16
    public var redShift: UInt8
    public var greenShift: UInt8
    public var blueShift: UInt8

    public init(
        bitsPerPixel: UInt8 = 32,
        depth: UInt8 = 24,
        bigEndian: UInt8 = 0,
        trueColour: UInt8 = 1,
        redMax: UInt16 = 255,
        greenMax: UInt16 = 255,
        blueMax: UInt16 = 255,
        redShift: UInt8 = 16,
        greenShift: UInt8 = 8,
        blueShift: UInt8 = 0
    ) {
        self.bitsPerPixel = bitsPerPixel
        self.depth = depth
        self.bigEndian = bigEndian
        self.trueColour = trueColour
        self.redMax = redMax
        self.greenMax = greenMax
        self.blueMax = blueMax
        self.redShift = redShift
        self.greenShift = greenShift
        self.blueShift = blueShift
    }

    public static let standard32 = PixelFormat()

    /// Serialized per RFC 6143 §7.7.1 — 16 bytes.
    public func serialized() -> Data {
        var data = Data()
        data.append(bitsPerPixel)
        data.append(depth)
        data.append(bigEndian)
        data.append(trueColour)
        data.append(contentsOf: [UInt8(redMax >> 8), UInt8(redMax & 0xFF)])
        data.append(contentsOf: [UInt8(greenMax >> 8), UInt8(greenMax & 0xFF)])
        data.append(contentsOf: [UInt8(blueMax >> 8), UInt8(blueMax & 0xFF)])
        data.append(redShift)
        data.append(greenShift)
        data.append(blueShift)
        data.append(0) // padding
        data.append(0)
        data.append(0)
        return data
    }
}

/// RFB framebuffer dimensions received during handshake.
public struct FramebufferDimensions: Equatable, Sendable {
    public var width: UInt16
    public var height: UInt16

    public init(width: UInt16, height: UInt16) {
        self.width = width
        self.height = height
    }
}

/// Error type for RFB protocol failures.
public enum RFBError: Error, Equatable {
    case invalidProtocolVersion(String)
    case unsupportedSecurityType(UInt8)
    case authenticationFailed
    case connectionClosed
    case handshakeFailed(String)
}

/// RFB version from the handshake: server's protocol string.
/// Fields are Int because Apple servers report non-standard pseudo-versions
/// (e.g. "RFB 003.889") that exceed a byte's range.
public struct RFBVersion: Equatable, Sendable {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// Parse "RFB 003.008\n" (12 bytes).
    /// Byte layout: 0-3 "RFB ", 4-6 major digits, 7 '.', 8-10 minor digits, 11 '\n'.
    public static func parse(_ data: Data) throws -> RFBVersion {
        guard data.count == 12,
              String(data: data.prefix(4), encoding: .ascii) == "RFB " else {
            throw RFBError.invalidProtocolVersion(String(data: data, encoding: .ascii) ?? "unreadable")
        }
        let bytes = [UInt8](data)

        func digit(_ byte: UInt8) throws -> Int {
            guard byte >= 48, byte <= 57 else {
                throw RFBError.invalidProtocolVersion(String(data: data, encoding: .ascii) ?? "unreadable")
            }
            return Int(byte - 48)
        }

        let major = try digit(bytes[6])
        let minorHundreds = try digit(bytes[8])
        let minorTens = try digit(bytes[9])
        let minorOnes = try digit(bytes[10])
        return RFBVersion(major: major, minor: minorHundreds * 100 + minorTens * 10 + minorOnes)
    }

    /// Serialize our client reply, e.g. "RFB 003.008\n".
    public func serialized() -> Data {
        let majorStr = String(format: "%03d", major)
        let minorStr = String(format: "%03d", minor)
        return Data("RFB \(majorStr).\(minorStr)\n".utf8)
    }

    /// True if the server speaks at least RFB 3.8 semantics.
    /// Apple's pseudo-versions (e.g. 889) are treated as 3.8-capable.
    public var supportsRFB38: Bool {
        major >= 4 || (major == 3 && minor >= 8)
    }
}

/// RFB security type constants (RFC 6143 §7.2.2 + Apple extensions).
public enum RFBSecurityType: UInt8, Sendable {
    case invalid = 0
    case none = 1
    case vncAuthentication = 2
    case appleRemoteDesktop = 30 // Apple's proprietary auth — reported, not implemented
}

/// A minimal, dependency-free RFB 3.8 protocol state machine used by the
/// screen observation/control module. Transport is injected so it can be
/// unit-tested against a mock socket.
public final class RFBClient {
    public private(set) var dimensions: FramebufferDimensions?
    public private(set) var serverName: String = ""
    public private(set) var negotiatedSecurity: RFBSecurityType?

    private let connection: RFBConnection

    public init(connection: RFBConnection) {
        self.connection = connection
    }

    /// Perform version + security + initialisation handshake.
    /// - Parameter password: VNC auth password (DES challenge/response), if required.
    public func handshake(password: String? = nil) throws {
        // 1. Version handshake (§7.1)
        let serverVersionData = try connection.readExactly(12)
        let serverVersion = try RFBVersion.parse(serverVersionData)
        // We support 3.8; fall back to 3.3 if the server is older.
        // Apple pseudo-versions (minor > 255) are treated as 3.8-capable.
        let clientVersion = serverVersion.supportsRFB38 ? RFBVersion(major: 3, minor: 8) : RFBVersion(major: 3, minor: 3)
        try connection.write(clientVersion.serialized())

        // 2. Security negotiation (§7.2)
        if clientVersion.minor >= 8 {
            let countData = try connection.readExactly(1)
            guard let typeCount = countData.first, typeCount > 0 else {
                throw RFBError.handshakeFailed("server offered no security types")
            }
            let typesData = try connection.readExactly(Int(typeCount))
            let offered = [UInt8](typesData)
            if offered.contains(RFBSecurityType.none.rawValue) {
                negotiatedSecurity = .none
                try connection.write(Data([RFBSecurityType.none.rawValue]))
            } else if offered.contains(RFBSecurityType.vncAuthentication.rawValue) {
                negotiatedSecurity = .vncAuthentication
                try connection.write(Data([RFBSecurityType.vncAuthentication.rawValue]))
                try performVNCAuth(password: password)
            } else {
                throw RFBError.unsupportedSecurityType(offered.first ?? 0)
            }
            // 3.8: SecurityResult (§7.2.4)
            let resultData = try connection.readExactly(4)
            let result = UInt32(resultData[0]) << 24 | UInt32(resultData[1]) << 16 | UInt32(resultData[2]) << 8 | UInt32(resultData[3])
            guard result == 0 else { throw RFBError.authenticationFailed }
        } else {
            // 3.3: server picks the security type unilaterally
            let typeData = try connection.readExactly(4)
            let type = UInt32(typeData[0]) << 24 | UInt32(typeData[1]) << 16 | UInt32(typeData[2]) << 8 | UInt32(typeData[3])
            switch type {
            case 0: negotiatedSecurity = .none
            case 1: negotiatedSecurity = .none
            case 2:
                negotiatedSecurity = .vncAuthentication
                try performVNCAuth(password: password)
            default:
                throw RFBError.unsupportedSecurityType(UInt8(clamping: type))
            }
        }

        // 3. ClientInit (§7.3) — share=1 (observe alongside other viewers)
        try connection.write(Data([0x01]))

        // 4. ServerInit (§7.4)
        let serverInit = try connection.readExactly(24)
        let width = UInt16(serverInit[0]) << 8 | UInt16(serverInit[1])
        let height = UInt16(serverInit[2]) << 8 | UInt16(serverInit[3])
        dimensions = FramebufferDimensions(width: width, height: height)
        let nameLength = Int(serverInit[20]) << 24 | Int(serverInit[21]) << 16 | Int(serverInit[22]) << 8 | Int(serverInit[23])
        if nameLength > 0, nameLength < 4096 {
            let nameData = try connection.readExactly(nameLength)
            serverName = String(data: nameData, encoding: .utf8) ?? ""
        }
    }

    /// VNC authentication (§7.2.2): 16-byte challenge, DES-encrypted response.
    /// DES implementation lives in `VNCAuth`; credentials are never logged.
    private func performVNCAuth(password: String?) throws {
        let challenge = try connection.readExactly(16)
        guard let password, !password.isEmpty else {
            throw RFBError.authenticationFailed
        }
        let response = VNCAuth.encryptChallenge(challenge, password: password)
        try connection.write(response)
    }

    /// Send SetPixelFormat (§7.5.1) with our preferred 32bpp true-colour format.
    public func setPixelFormat(_ format: PixelFormat = .standard32) throws {
        var message = Data([0x00])
        message.append(contentsOf: [0, 0, 0]) // padding
        message.append(format.serialized())
        try connection.write(message)
    }

    /// Send SetEncodings (§7.5.2) — raw only for MVP; Tight/Hextile later.
    public func setEncodings() throws {
        var message = Data([0x02])
        message.append(0) // padding
        message.append(contentsOf: [0, 1]) // number of encodings
        // Raw encoding = 0
        message.append(contentsOf: [0, 0, 0, 0])
        try connection.write(message)
    }

    /// Send FramebufferUpdateRequest (§7.5.3) — incremental by default.
    /// Message: type(1) + incremental(1) + x(2) + y(2) + width(2) + height(2) = 10 bytes.
    public func requestFramebufferUpdate(incremental: Bool = true) throws {
        var message = Data([0x03])
        message.append(incremental ? 1 : 0)
        guard let dims = dimensions else { throw RFBError.handshakeFailed("handshake incomplete") }
        let w = dims.width, h = dims.height
        message.append(contentsOf: [0, 0]) // x-position
        message.append(contentsOf: [0, 0]) // y-position
        message.append(contentsOf: [UInt8(w >> 8), UInt8(w & 0xFF)])
        message.append(contentsOf: [UInt8(h >> 8), UInt8(h & 0xFF)])
        try connection.write(message)
    }

    /// Send a KeyEvent (§7.5.4): type(1) + down-flag(1) + padding(2) + keysym(4).
    /// Keysyms follow the X11 keysym convention (0x20-0x7E are ASCII).
    public func sendKeyEvent(keysym: UInt32, down: Bool) throws {
        var message = Data([0x04])
        message.append(down ? 1 : 0)
        message.append(contentsOf: [0, 0]) // padding
        message.append(contentsOf: [
            UInt8(keysym >> 24 & 0xFF), UInt8(keysym >> 16 & 0xFF),
            UInt8(keysym >> 8 & 0xFF), UInt8(keysym & 0xFF),
        ])
        try connection.write(message)
    }

    /// Send a PointerEvent (§7.5.5): type(1) + button-mask(1) + x(2) + y(2).
    public func sendPointerEvent(x: UInt16, y: UInt16, buttonMask: UInt8) throws {
        var message = Data([0x05])
        message.append(buttonMask)
        message.append(contentsOf: [UInt8(x >> 8), UInt8(x & 0xFF)])
        message.append(contentsOf: [UInt8(y >> 8), UInt8(y & 0xFF)])
        try connection.write(message)
    }

    /// Send a client cut-text message (§7.5.6).
    public func sendCutText(_ text: String) throws {
        var message = Data([0x06])
        message.append(contentsOf: [0, 0, 0]) // padding
        let bytes = [UInt8](text.utf8)
        let length = UInt32(bytes.count)
        message.append(contentsOf: [
            UInt8(length >> 24 & 0xFF), UInt8(length >> 16 & 0xFF),
            UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF),
        ])
        message.append(contentsOf: bytes)
        try connection.write(message)
    }

    /// Read one server message header and, for FramebufferUpdate, decode it.
    /// Blocks until a full update message is available on the connection.
    public func readFramebufferUpdate(format: PixelFormat = .standard32) throws -> [FramebufferRect] {
        let header = try connection.readExactly(4)
        guard header[0] == 0x00 else {
            throw RFBError.handshakeFailed("unexpected server message type \(header[0])")
        }
        let rectCount = Int(header[2]) << 8 | Int(header[3])
        guard rectCount > 0 else { return [] }

        // Each rect: 12 bytes header + raw pixel data. Read incrementally.
        var buffer = Data(header)
        var rects: [FramebufferRect] = []
        var pendingRects = rectCount
        while pendingRects > 0 {
            // Read rectangle header
            let rectHeader = try connection.readExactly(12)
            let w = UInt16(rectHeader[4]) << 8 | UInt16(rectHeader[5])
            let h = UInt16(rectHeader[6]) << 8 | UInt16(rectHeader[7])
            let encoding = Int32(truncatingIfNeeded:
                UInt32(rectHeader[8]) << 24 | UInt32(rectHeader[9]) << 16
                | UInt32(rectHeader[10]) << 8 | UInt32(rectHeader[11]))
            guard encoding == 0 else { throw RFBError.handshakeFailed("unsupported encoding \(encoding)") }
            let bytesPerPixel = Int(format.bitsPerPixel) / 8
            let pixelData = try connection.readExactly(Int(w) * Int(h) * bytesPerPixel)

            var fullRect = Data(rectHeader)
            fullRect.append(pixelData)
            // Parse via the shared decoder: build a synthetic single-rect update.
            var synthetic = Data([0x00, 0x00, 0x00, 0x01])
            synthetic.append(fullRect)
            let decoded = try FramebufferUpdateDecoder.decodeUpdate(from: synthetic, format: format)
            rects.append(contentsOf: decoded.rects)
            pendingRects -= 1
        }
        _ = buffer // header already parsed
        return rects
    }
}
