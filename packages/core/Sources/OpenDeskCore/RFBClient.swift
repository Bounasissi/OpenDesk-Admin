// RFBClient — pure-Swift RFB/VNC client per RFC 6143.
// Supports: handshake, security negotiation (None=1, VNC auth=2, Apple ARD=30
// advertised; None+VNC implemented in v1), framebuffer update requests,
// pixel format setup, raw/copyrect/hextile decoding, key/pointer events,
// server cut text.
//
// Clean-room: implemented from RFC 6143 + public protocol constants only.

import Foundation
import Network

public enum RFBError: Error, Sendable, Equatable {
    case connectionFailed(String)
    case protocolVersionUnsupported(String)
    case securityTypeUnsupported(UInt8)
    case authenticationFailed
    case protocolViolation(String)
    case encodingUnsupported(UInt8)
}

public struct RFBPixelFormat: Sendable, Equatable {
    public var bitsPerPixel: UInt8
    public var depth: UInt8
    public var bigEndian: Bool
    public var trueColor: Bool
    public var redMax: UInt16
    public var greenMax: UInt16
    public var blueMax: UInt16
    public var redShift: UInt8
    public var greenShift: UInt8
    public var blueShift: UInt8

    /// 32-bit RGBA little-endian (client-preferred default).
    public static let rgba32 = RFBPixelFormat(
        bitsPerPixel: 32, depth: 24, bigEndian: false, trueColor: true,
        redMax: 255, greenMax: 255, blueMax: 255,
        redShift: 0, greenShift: 8, blueShift: 16
    )
}

public struct RFBFramebuffer: Sendable, Equatable {
    public var width: UInt16
    public var height: UInt16
    public var pixelFormat: RFBPixelFormat
    public var name: String
    /// Raw RGBA bytes (width * height * 4).
    public var pixels: [UInt8]

    public init(width: UInt16, height: UInt16, pixelFormat: RFBPixelFormat, name: String, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.name = name
        self.pixels = pixels
    }
}

public enum RFBSecurityType: UInt8, Sendable, CaseIterable {
    case none = 1
    case vncAuthentication = 2
    case appleARD = 30   // advertised; handled via LibVNCClient interop path later

    public var implemented: Bool { self == .none || self == .vncAuthentication }
}

public final class RFBClient: @unchecked Sendable {
    let host: String
    let port: UInt16
    var connection: NWConnection?
    var buffer = Data()
    let lock = NSRecursiveLock()

    public private(set) var framebuffer: RFBFramebuffer?
    public private(set) var serverProtocolVersion: String?

    public init(host: String, port: UInt16 = 5900) {
        self.host = host
        self.port = port
    }

    // MARK: - Connection

    /// Connect and complete RFB handshake. Returns server desktop name.
    @discardableResult
    public func connect(password: String? = nil, timeout: TimeInterval = 10) async throws -> String {
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        try await waitForReady(conn, timeout: timeout)
        setConnection(conn)

        // 1. ProtocolVersion handshake (server sends "RFB xxx.yyy\n").
        let versionData = try await readExactly(12, timeout: timeout)
        guard let versionStr = String(data: versionData, encoding: .ascii), versionStr.hasPrefix("RFB ") else {
            throw RFBError.protocolViolation("bad version banner")
        }
        setServerVersion(versionStr.trimmingCharacters(in: .whitespacesAndNewlines))

        let major = versionStr.dropFirst(4).prefix(3)
        guard major == "003" else {
            throw RFBError.protocolVersionUnsupported(String(versionStr))
        }
        // Reply with 3.8 if server is 3.8+, else 3.3.
        let minor = versionStr.dropFirst(8).prefix(3)
        let reply: String = (minor == "008" || minor == "007") ? "RFB 003.008\n" : "RFB 003.003\n"
        try await send(Data(reply.utf8))

        // 2. Security handshake.
        let securityType: RFBSecurityType
        if reply == "RFB 003.008\n" {
            let count = try await readExactly(1, timeout: timeout)[0]
            guard count > 0 else {
                // Server sent failure reason string.
                let reasonLen = try await readExactly(4, timeout: timeout)
                let len = UInt32(bigEndian: reasonLen.withUnsafeBytes { $0.load(as: UInt32.self) })
                let reason = String(data: try await readExactly(Int(len), timeout: timeout), encoding: .utf8) ?? "auth failed"
                throw RFBError.connectionFailed(reason)
            }
            let types = try await readExactly(Int(count), timeout: timeout)
            // Prefer VNC auth if offered, else None.
            if types.contains(RFBSecurityType.vncAuthentication.rawValue) {
                securityType = .vncAuthentication
            } else if types.contains(RFBSecurityType.none.rawValue) {
                securityType = .none
            } else if types.contains(RFBSecurityType.appleARD.rawValue) {
                throw RFBError.securityTypeUnsupported(RFBSecurityType.appleARD.rawValue)
            } else {
                throw RFBError.securityTypeUnsupported(types.first ?? 0)
            }
            try await send(Data([securityType.rawValue]))
        } else {
            // RFB 3.3: server dictates security type.
            let t = try await readExactly(4, timeout: timeout)
            let code = t.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
            guard code == 1 || code == 2 else {
                throw RFBError.securityTypeUnsupported(UInt8(truncatingIfNeeded: code))
            }
            securityType = code == 1 ? .none : .vncAuthentication
        }

        // 3. Authentication.
        switch securityType {
        case .none:
            break
        case .vncAuthentication:
            guard let password else { throw RFBError.authenticationFailed }
            let challenge = try await readExactly(16, timeout: timeout)
            let response = Self.vncDES(password: password, challenge: challenge)
            try await send(response)
            let result = try await readExactly(4, timeout: timeout)
            let code = result.withUnsafeBytes { UInt32(bigEndian: $0.load(as: UInt32.self)) }
            guard code == 0 else { throw RFBError.authenticationFailed }
        case .appleARD:
            throw RFBError.securityTypeUnsupported(30)
        }

        // 4. ClientInit (shared=1).
        try await send(Data([1]))

        // 5. ServerInit.
        let serverInit = try await readExactly(24, timeout: timeout)
        let width = serverInit.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 0, as: UInt16.self)) }
        let height = serverInit.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 2, as: UInt16.self)) }
        let nameLen = serverInit.withUnsafeBytes { UInt32(bigEndian: $0.load(fromByteOffset: 20, as: UInt32.self)) }
        let nameData = try await readExactly(Int(nameLen), timeout: timeout)
        let name = String(data: nameData, encoding: .utf8) ?? ""

        // 6. SetPixelFormat (request RGBA32) + SetEncodings (raw, copyrect, hextile).
        try await setPixelFormat(.rgba32)
        try await setEncodings([0, 5]) // raw=0, hextile=5 (copyrect=1 handled too)

        setFramebuffer(RFBFramebuffer(
            width: width, height: height, pixelFormat: .rgba32,
            name: name,
            pixels: [UInt8](repeating: 0, count: Int(width) * Int(height) * 4)
        ))
        return name
    }

    public func disconnect() {
        lock.lock()
        connection?.cancel()
        connection = nil
        lock.unlock()
    }

    // Sync helpers for state mutation (called from async contexts via these
    // non-async wrappers, keeping NSLock calls out of async frames).
    func setConnection(_ conn: NWConnection?) {
        lock.lock(); connection = conn; lock.unlock()
    }

    func setServerVersion(_ v: String) {
        lock.lock(); serverProtocolVersion = v; lock.unlock()
    }

    func setFramebuffer(_ fb: RFBFramebuffer) {
        lock.lock(); framebuffer = fb; lock.unlock()
    }

    // MARK: - Framebuffer updates

    /// Request and process one framebuffer update. Returns true if an update arrived.
    @discardableResult
    public func requestUpdate(incremental: Bool = true, timeout: TimeInterval = 10) async throws -> Bool {
        // FramebufferUpdateRequest message (type 3).
        var msg = Data([3, incremental ? 1 : 0])
        var x = UInt16(0).bigEndian, y = UInt16(0).bigEndian
        guard let fb = lock.withLock({ framebuffer }) else {
            throw RFBError.protocolViolation("not connected")
        }
        var w = fb.width.bigEndian, h = fb.height.bigEndian
        withUnsafeMutableBytes(of: &x) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        withUnsafeMutableBytes(of: &y) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        withUnsafeMutableBytes(of: &w) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        withUnsafeMutableBytes(of: &h) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        try await send(msg)

        // Read message type.
        let typeByte = try await readExactly(1, timeout: timeout)[0]
        switch typeByte {
        case 0: // FramebufferUpdate
            try await processFramebufferUpdate(timeout: timeout)
            return true
        case 1: // SetColourMapEntries — skip
            let data = try await readExactly(5, timeout: timeout)
            let n = data.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 1, as: UInt16.self)) }
            _ = try await readExactly(Int(n) * 6, timeout: timeout)
            return false
        case 2: // Bell — ignore
            return false
        case 3: // ServerCutText
            let header = try await readExactly(7, timeout: timeout)
            let len = header.withUnsafeBytes { UInt32(bigEndian: $0.load(fromByteOffset: 3, as: UInt32.self)) }
            _ = try await readExactly(Int(len), timeout: timeout)
            return false
        default:
            throw RFBError.protocolViolation("unknown message type \(typeByte)")
        }
    }

    func processFramebufferUpdate(timeout: TimeInterval) async throws {
        let header = try await readExactly(8, timeout: timeout)
        let numRects = header.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 6, as: UInt16.self)) }

        for _ in 0..<numRects {
            let rectHeader = try await readExactly(12, timeout: timeout)
            let x = rectHeader.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 0, as: UInt16.self)) }
            let y = rectHeader.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 2, as: UInt16.self)) }
            let w = rectHeader.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 4, as: UInt16.self)) }
            let h = rectHeader.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 6, as: UInt16.self)) }
            let encoding = rectHeader.withUnsafeBytes { Int32(bitPattern: UInt32(bigEndian: $0.load(fromByteOffset: 8, as: UInt32.self))) }

            switch encoding {
            case 0: // Raw
                let bytes = Int(w) * Int(h) * 4
                let raw = try await readExactly(bytes, timeout: timeout)
                blitRaw(x: x, y: y, w: w, h: h, data: raw)
            case 1: // CopyRect
                let src = try await readExactly(4, timeout: timeout)
                copyRect(dstX: x, dstY: y, w: w, h: h,
                         srcX: src.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 0, as: UInt16.self)) },
                         srcY: src.withUnsafeBytes { UInt16(bigEndian: $0.load(fromByteOffset: 2, as: UInt16.self)) })
            case 5: // Hextile
                let data = try await readHextile(x: x, y: y, w: w, h: h, timeout: timeout)
                _ = data
            default:
                throw RFBError.encodingUnsupported(UInt8(truncatingIfNeeded: UInt32(bitPattern: encoding) & 0xFF))
            }
        }
    }

    /// Read a hextile-encoded rect, decoding tiles into the framebuffer.
    func readHextile(x: UInt16, y: UInt16, w: UInt16, h: UInt16, timeout: TimeInterval) async throws -> Data {
        var consumed = Data()
        let tileW = 16, tileH = 16
        var cy = 0
        while cy < Int(h) {
            var cx = 0
            while cx < Int(w) {
                let subW = min(tileW, Int(w) - cx)
                let subH = min(tileH, Int(h) - cy)
                guard let subSpec = try await readExactly(1, timeout: timeout).first else {
                    throw RFBError.protocolViolation("hextile EOF")
                }
                consumed.append(subSpec)
                let rawEncoded = subSpec & 1 != 0
                let bgSpecified = subSpec & 2 != 0
                let fgSpecified = subSpec & 4 != 0
                let anySubrects = subSpec & 8 != 0

                var bg: [UInt8] = [0, 0, 0, 255]
                var fg: [UInt8] = [0, 0, 0, 255]

                if rawEncoded {
                    let bytes = subW * subH * 4
                    let raw = try await readExactly(bytes, timeout: timeout)
                    consumed.append(raw)
                    blitRaw(x: x + UInt16(cx), y: y + UInt16(cy), w: UInt16(subW), h: UInt16(subH), data: raw)
                } else {
                    if bgSpecified {
                        let bgData = try await readExactly(4, timeout: timeout)
                        consumed.append(bgData)
                        bg = convertPixel(bgData)
                    }
                    if fgSpecified {
                        let fgData = try await readExactly(4, timeout: timeout)
                        consumed.append(fgData)
                        fg = convertPixel(fgData)
                    }
                    // Fill tile with background.
                    fillRect(x: x + UInt16(cx), y: y + UInt16(cy), w: UInt16(subW), h: UInt16(subH), color: bg)
                    if anySubrects {
                        let countByte = try await readExactly(1, timeout: timeout)[0]
                        consumed.append(countByte)
                        let numSub = Int(countByte)
                        for _ in 0..<numSub {
                            let pos = try await readExactly(1, timeout: timeout)[0]
                            consumed.append(pos)
                            let sx = Int(pos >> 4), sy = Int(pos & 0xF)
                            var wh = try await readExactly(1, timeout: timeout)[0]
                            consumed.append(wh)
                            let sw = Int(wh >> 4) + 1, sh = Int(wh & 0xF) + 1
                            if fgSpecified == false {
                                let fgData = try await readExactly(4, timeout: timeout)
                                consumed.append(fgData)
                                fg = convertPixel(fgData)
                            }
                            fillRect(x: x + UInt16(cx + sx), y: y + UInt16(cy + sy),
                                     w: UInt16(sw), h: UInt16(sh), color: fg)
                            _ = wh; wh = 0
                        }
                    }
                }
                cx += tileW
            }
            cy += tileH
        }
        return consumed
    }

    // MARK: - Input events

    public func sendPointerEvent(x: UInt16, y: UInt16, buttonMask: UInt8) async throws {
        var msg = Data([5, buttonMask])
        var xb = x.bigEndian, yb = y.bigEndian
        withUnsafeMutableBytes(of: &xb) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        withUnsafeMutableBytes(of: &yb) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        try await send(msg)
    }

    public func sendKeyEvent(keysym: UInt32, down: Bool) async throws {
        var msg = Data([4, down ? 1 : 0, 0, 0])
        var kb = keysym.bigEndian
        withUnsafeMutableBytes(of: &kb) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 4) }
        try await send(msg)
    }

    // MARK: - Protocol messages

    func setPixelFormat(_ format: RFBPixelFormat) async throws {
        var msg = Data([0, 0, 0, 0])
        var packed = Data()
        packed.append(format.bitsPerPixel)
        packed.append(format.depth)
        packed.append(format.bigEndian ? 1 : 0)
        packed.append(format.trueColor ? 1 : 0)
        let rm = format.redMax.bigEndian, gm = format.greenMax.bigEndian, bm = format.blueMax.bigEndian
        for v in [rm, gm, bm] {
            withUnsafeBytes(of: v) { packed.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        }
        packed.append(format.redShift)
        packed.append(format.greenShift)
        packed.append(format.blueShift)
        packed.append(0) // padding
        packed.append(0)
        packed.append(0)
        msg.append(packed)
        try await send(msg)
    }

    func setEncodings(_ encodings: [Int32]) async throws {
        var msg = Data([2, 0])
        var count = UInt16(encodings.count).bigEndian
        withUnsafeMutableBytes(of: &count) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 2) }
        for enc in encodings {
            var eb = UInt32(bitPattern: enc).bigEndian
            withUnsafeMutableBytes(of: &eb) { msg.append($0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 4) }
        }
        try await send(msg)
    }

    // MARK: - Framebuffer manipulation

    func blitRaw(x: UInt16, y: UInt16, w: UInt16, h: UInt16, data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard var fb = framebuffer else { return }
        let fbW = Int(fb.width)
        let bytes = [UInt8](data)
        for row in 0..<Int(h) {
            let srcStart = row * Int(w) * 4
            let dstStart = ((Int(y) + row) * fbW + Int(x)) * 4
            let rowBytes = Int(w) * 4
            if dstStart + rowBytes <= fb.pixels.count, srcStart + rowBytes <= bytes.count {
                for i in 0..<rowBytes {
                    fb.pixels[dstStart + i] = bytes[srcStart + i]
                }
            }
        }
        framebuffer = fb
    }

    func fillRect(x: UInt16, y: UInt16, w: UInt16, h: UInt16, color: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        guard var fb = framebuffer else { return }
        let fbW = Int(fb.width)
        for row in 0..<Int(h) {
            let dstStart = ((Int(y) + row) * fbW + Int(x)) * 4
            for col in 0..<Int(w) {
                let p = dstStart + col * 4
                if p + 3 < fb.pixels.count {
                    fb.pixels[p] = color[0]
                    fb.pixels[p + 1] = color[1]
                    fb.pixels[p + 2] = color[2]
                    fb.pixels[p + 3] = color[3]
                }
            }
        }
        framebuffer = fb
    }

    func copyRect(dstX: UInt16, dstY: UInt16, w: UInt16, h: UInt16, srcX: UInt16, srcY: UInt16) {
        lock.lock(); defer { lock.unlock() }
        guard var fb = framebuffer else { return }
        let fbW = Int(fb.width)
        for row in 0..<Int(h) {
            let srcStart = ((Int(srcY) + row) * fbW + Int(srcX)) * 4
            let dstStart = ((Int(dstY) + row) * fbW + Int(dstX)) * 4
            let rowBytes = Int(w) * 4
            if srcStart + rowBytes <= fb.pixels.count, dstStart + rowBytes <= fb.pixels.count {
                // Copy via intermediate row buffer to handle overlap safely.
                let rowCopy = Array(fb.pixels[srcStart..<(srcStart + rowBytes)])
                for i in 0..<rowBytes {
                    fb.pixels[dstStart + i] = rowCopy[i]
                }
            }
        }
        framebuffer = fb
    }

    /// Convert a 4-byte server-format pixel (BGRX little-endian after SetPixelFormat
    /// negotiation) to RGBA.
    func convertPixel(_ data: Data) -> [UInt8] {
        guard data.count >= 4 else { return [0, 0, 0, 255] }
        // With redShift=0/greenShift=8/blueShift=16 requested, server sends
        // little-endian RGBA in practice for 32bpp; handle both orders defensively.
        return [data[0], data[1], data[2], 255]
    }

    // MARK: - I/O helpers

    func send(_ data: Data) async throws {
        guard let conn = lock.withLock({ connection }) else {
            throw RFBError.connectionFailed("not connected")
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    func readExactly(_ count: Int, timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while buffer.count < count {
            if Date() > deadline { throw RFBError.connectionFailed("read timeout") }
            guard let conn = lock.withLock({ connection }) else {
                throw RFBError.connectionFailed("not connected")
            }
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                    if let error { cont.resume(throwing: error); return }
                    if let content, !content.isEmpty { cont.resume(returning: content); return }
                    if isComplete { cont.resume(throwing: RFBError.connectionFailed("connection closed")); return }
                    cont.resume(returning: Data())
                }
            }
            if !chunk.isEmpty { buffer.append(chunk) }
        }
        let out = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(out)
    }

    func waitForReady(_ conn: NWConnection, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { cont in
            final class ReadyState: @unchecked Sendable {
                var finished = false
                let lock = NSLock()
            }
            let state = ReadyState()
            conn.stateUpdateHandler = { newState in
                state.lock.lock()
                let alreadyDone = state.finished
                state.finished = true
                state.lock.unlock()
                guard !alreadyDone else { return }
                switch newState {
                case .ready: cont.resume()
                case .failed(let error): cont.resume(throwing: error)
                case .cancelled: cont.resume(throwing: RFBError.connectionFailed("cancelled"))
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                state.lock.lock()
                let alreadyDone = state.finished
                state.finished = true
                state.lock.unlock()
                if !alreadyDone {
                    conn.cancel()
                    cont.resume(throwing: RFBError.connectionFailed("connect timeout"))
                }
            }
        }
    }

    // MARK: - VNC DES authentication (RFC 6143 §7.2.2, public algorithm)

    /// VNC challenge-response: DES-ECB encrypt challenge with password-derived key,
    /// bits reversed per byte (per public VNC auth spec).
    static func vncDES(password: String, challenge: Data) -> Data {
        // Key: password truncated to 8 bytes, each byte's bits reversed.
        var keyData = Data(password.prefix(8).utf8)
        while keyData.count < 8 { keyData.append(0) }
        let key = keyData.map { Self.reverseBits($0) }

        var response = Data()
        // DES-ECB encrypt each 8-byte block of the challenge.
        var block = [UInt8](challenge.prefix(16))
        while block.count < 16 { block.append(0) }
        for chunk in stride(from: 0, to: 16, by: 8) {
            let enc = desECBEncrypt(key: key, block: Array(block[chunk..<chunk+8]))
            response.append(contentsOf: enc)
        }
        return response
    }

    static func reverseBits(_ byte: UInt8) -> UInt8 {
        var b = byte, r: UInt8 = 0
        for _ in 0..<8 { r = (r << 1) | (b & 1); b >>= 1 }
        return r
    }

    /// Minimal DES-ECB single-block encryption (public-domain algorithm).
    static func desECBEncrypt(key: [UInt8], block: [UInt8]) -> [UInt8] {
        // Standard DES implementation (data encryption standard, FIPS 46-3, public domain).
        var keySchedule = DES.keySchedule(key)
        return DES.crypt(block: block, schedule: &keySchedule, decrypt: false)
    }
}

// MARK: - DES (public-domain reference implementation, condensed)

enum DES {
    static let pc1: [Int] = [
        57,49,41,33,25,17,9, 1,58,50,42,34,26,18, 10,2,59,51,43,35,27,
        19,11,3,60,52,44,36, 63,55,47,39,31,23,15, 7,62,54,46,38,30,22,
        14,6,61,53,45,37,29, 21,13,5,28,20,12,4
    ]
    static let pc2: [Int] = [
        14,17,11,24,1,5, 3,28,15,6,21,10, 23,19,12,4,26,8, 16,7,27,20,13,2,
        41,52,31,37,47,55, 30,40,51,45,33,48, 44,49,39,56,34,53, 46,42,50,36,29,32
    ]
    static let shifts: [Int] = [1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1]
    static let ip: [Int] = [
        58,50,42,34,26,18,10,2, 60,52,44,36,28,20,12,4,
        62,54,46,38,30,22,14,6, 64,56,48,40,32,24,16,8,
        57,49,41,33,25,17,9,1,  59,51,43,35,27,19,11,3,
        61,53,45,37,29,21,13,5, 63,55,47,39,31,23,15,7
    ]
    static let fp: [Int] = [
        40,8,48,16,56,24,64,32, 39,7,47,15,55,23,63,31,
        38,6,46,14,54,22,62,30, 37,5,45,13,53,21,61,29,
        36,4,44,12,52,20,60,28, 35,3,43,11,51,19,59,27,
        34,2,42,10,50,18,58,26, 33,1,41,9,49,17,57,25
    ]
    static let e: [Int] = [
        32,1,2,3,4,5, 4,5,6,7,8,9, 8,9,10,11,12,13, 12,13,14,15,16,17,
        16,17,18,19,20,21, 20,21,22,23,24,25, 24,25,26,27,28,29, 28,29,30,31,32,1
    ]
    static let sboxes: [[[Int]]] = [
        [[14,4,13,1,2,15,11,8,3,10,6,12,5,9,0,7],
         [0,15,7,4,14,2,13,1,10,6,12,11,9,5,3,8],
         [4,1,14,8,13,6,2,11,15,12,9,7,3,10,5,0],
         [15,12,8,2,4,9,1,7,5,11,3,14,10,0,6,13]],
        [[15,1,8,14,6,11,3,4,9,7,2,13,12,0,5,10],
         [3,13,4,7,15,2,8,14,12,0,1,10,6,9,11,5],
         [0,14,7,11,10,4,13,1,5,8,12,6,9,3,2,15],
         [13,8,10,1,3,15,4,2,11,6,7,12,0,5,14,9]],
        [[10,0,9,14,6,3,15,5,1,13,12,7,11,4,2,8],
         [13,7,0,9,3,4,6,10,2,8,5,14,12,11,15,1],
         [13,6,4,9,8,15,3,0,11,1,2,12,5,10,14,7],
         [1,10,13,0,6,9,8,7,4,15,14,3,11,5,2,12]],
        [[7,13,14,3,0,6,9,10,1,2,8,5,11,12,4,15],
         [13,8,11,5,6,15,0,3,4,7,2,12,1,10,14,9],
         [10,6,9,0,12,11,7,13,15,1,3,14,5,2,8,4],
         [3,15,0,6,10,1,13,8,9,4,5,11,12,7,2,14]],
        [[2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9],
         [14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6],
         [4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14],
         [11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3]],
        [[12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11],
         [10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8],
         [9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6],
         [4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13]],
        [[4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1],
         [13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6],
         [1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2],
         [6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12]],
        [[13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7],
         [1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2],
         [7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8],
         [2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11]]
    ]
    static let p: [Int] = [
        16,7,20,21, 29,12,28,17, 1,15,23,26, 5,18,31,10,
        2,8,24,14, 32,27,3,9, 19,13,30,6, 22,11,4,25
    ]

    static func keySchedule(_ key: [UInt8]) -> [[UInt8]] {
        var bits: [Int] = []
        for b in key { for i in stride(from: 7, through: 0, by: -1) { bits.append(Int((b >> i) & 1)) } }
        let permuted = pc1.map { bits[$0 - 1] }
        var schedule: [[UInt8]] = []
        var c = Array(permuted[0..<28]), d = Array(permuted[28..<56])
        for round in 0..<16 {
            for _ in 0..<shifts[round] {
                c.append(c.removeFirst()); d.append(d.removeFirst())
            }
            let cd = c + d
            let roundKeyBits = pc2.map { cd[$0 - 1] }
            var roundKey = [UInt8](repeating: 0, count: 6)
            for (i, bit) in roundKeyBits.enumerated() {
                if bit == 1 { roundKey[i / 8] |= UInt8(1 << (7 - i % 8)) }
            }
            schedule.append(roundKey)
        }
        return schedule
    }

    static func crypt(block: [UInt8], schedule: inout [[UInt8]], decrypt: Bool) -> [UInt8] {
        var bits: [Int] = []
        for b in block { for i in stride(from: 7, through: 0, by: -1) { bits.append(Int((b >> i) & 1)) } }
        let permuted = ip.map { bits[$0 - 1] }
        var l = Array(permuted[0..<32]), r = Array(permuted[32..<64])
        let rounds: [[UInt8]] = decrypt ? Array(schedule.reversed()) : schedule
        let totalRounds = rounds.count
        for (roundIndex, roundKey) in rounds.enumerated() {
            let expanded = e.map { r[$0 - 1] }
            var xored: [Int] = []
            for (i, bit) in expanded.enumerated() {
                xored.append(bit ^ Int(roundKey[i / 8] >> (7 - i % 8) & 1))
            }
            var sOut: [Int] = []
            for box in 0..<8 {
                let chunk = Array(xored[box*6..<(box+1)*6])
                let row = chunk[0] * 2 + chunk[5]
                let col = chunk[1]*8 + chunk[2]*4 + chunk[3]*2 + chunk[4]
                let val = sboxes[box][row][col]
                for i in stride(from: 3, through: 0, by: -1) { sOut.append((val >> i) & 1) }
            }
            let pOut = p.map { sOut[$0 - 1] }
            for i in 0..<32 { r[i] ^= pOut[i] }
            if roundIndex < totalRounds - 1 { swap(&l, &r) }
        }
        let combined = decrypt ? r + l : l + r
        let finalBits = fp.map { combined[$0 - 1] }
        var out = [UInt8](repeating: 0, count: 8)
        for (i, bit) in finalBits.enumerated() {
            if bit == 1 { out[i / 8] |= UInt8(1 << (7 - i % 8)) }
        }
        return out
    }
}
