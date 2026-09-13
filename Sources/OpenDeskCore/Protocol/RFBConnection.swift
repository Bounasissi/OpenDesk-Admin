import Foundation

/// Transport abstraction for the RFB client so the handshake state machine
/// can be unit-tested against a mock (see OpenDeskCoreTests/MockRFBConnection).
public protocol RFBConnection {
    func readExactly(_ count: Int) throws -> Data
    func write(_ data: Data) throws
    func close()
}

/// TCP-based RFB connection to a client's VNC server (default port 5900).
public final class TCPConnection: RFBConnection {
    private var socketFD: Int32 = -1
    private let host: String
    private let port: UInt16

    public init(host: String, port: UInt16) throws {
        self.host = host
        self.port = port
        self.socketFD = try TCPConnection.connect(host: host, port: port)
    }

    private static func connect(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let first = result else {
            throw RFBError.handshakeFailed("DNS resolution failed for \(host)")
        }
        defer { freeaddrinfo(result) }

        var fd: Int32 = -1
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let ai = cursor {
            fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if fd >= 0, Darwin.connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 {
                return fd
            }
            if fd >= 0 { Darwin.close(fd) }
            cursor = ai.pointee.ai_next
        }
        throw RFBError.handshakeFailed("TCP connect failed for \(host):\(port)")
    }

    public func readExactly(_ count: Int) throws -> Data {
        var data = Data(capacity: count)
        var buffer = [UInt8](repeating: 0, count: count)
        var received = 0
        while received < count {
            let n = buffer.withUnsafeMutableBytes { raw in
                recv(socketFD, raw.baseAddress!.advanced(by: received), count - received, 0)
            }
            if n <= 0 { throw RFBError.connectionClosed }
            received += n
        }
        data.append(contentsOf: buffer[0..<count])
        return data
    }

    public func write(_ data: Data) throws {
        let bytes = [UInt8](data)
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { raw in
                send(socketFD, raw.baseAddress!.advanced(by: sent), bytes.count - sent, 0)
            }
            if n <= 0 { throw RFBError.connectionClosed }
            sent += n
        }
    }

    public func close() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    deinit { close() }
}

/// VNC authentication: DES-encrypt the 16-byte server challenge with a
/// password-derived key (standard VNC auth, RFC 6143 §7.2.2).
public enum VNCAuth {
    /// VNC uses DES with a key derived by reversing the bits of each password byte.
    static func encryptChallenge(_ challenge: Data, password: String) -> Data {
        let key = derivedKey(from: password)
        var response = Data()
        // Challenge is encrypted in two 8-byte DES blocks (ECB, no padding).
        for blockStart in stride(from: 0, to: 16, by: 8) {
            let block = challenge.subdata(in: blockStart..<(blockStart + 8))
            response.append(DESEngine.encryptBlock(block: [UInt8](block), key: key))
        }
        return response
    }

    /// Reverse bits of each byte of the password, pad/truncate to 8 bytes.
    static func derivedKey(from password: String) -> [UInt8] {
        var key = [UInt8](repeating: 0, count: 8)
        let bytes = [UInt8](password.utf8.prefix(8))
        for (i, byte) in bytes.enumerated() {
            key[i] = byte.reversedBits()
        }
        return key
    }
}

extension UInt8 {
    /// Reverse the bit order of a byte.
    func reversedBits() -> UInt8 {
        var v = self
        var r: UInt8 = 0
        for _ in 0..<8 {
            r = (r << 1) | (v & 1)
            v >>= 1
        }
        return r
    }
}

/// Full DES engine (FIPS 46-3 tables + Feistel network), used only for the
/// legacy VNC challenge/response handshake. 64-bit block, ECB single block.
enum DESEngine {
    // Initial permutation table (FIPS 46-3)
    static let initialPermutation: [Int] = [
        58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
        62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
        57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
        61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
    ]
    // Key schedule shift table
    static let shifts: [Int] = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]
    // PC-1 permutation
    static let pc1: [Int] = [
        57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, 10, 2,
        59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36, 63, 55, 47, 39,
        31, 23, 15, 7, 62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37,
        29, 21, 13, 5, 28, 20, 12, 4,
    ]
    // PC-2 permutation
    static let pc2: [Int] = [
        14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
        23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
        41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
        44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
    ]
    // Expansion permutation
    static let expansion: [Int] = [
        32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9,
        8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 16, 17,
        16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25,
        24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
    ]
    // S-boxes
    static let sboxes: [[[Int]]] = [
        [[14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
         [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
         [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
         [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13]],
        [[15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
         [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
         [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
         [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9]],
        [[10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
         [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
         [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
         [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12]],
        [[7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
         [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
         [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
         [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14]],
        [[2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
         [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
         [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
         [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3]],
        [[12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
         [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
         [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
         [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13]],
        [[4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
         [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
         [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
         [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12]],
        [[13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
         [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
         [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
         [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]],
    ]
    // P permutation after S-boxes
    static let pbox: [Int] = [
        16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
        2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
    ]
    // Final permutation (IP inverse, FIPS 46-3) — NOT the reverse of IP.
    static let finalPermutation: [Int] = [
        40, 8, 48, 16, 56, 24, 64, 32,
        39, 7, 47, 15, 55, 23, 63, 31,
        38, 6, 46, 14, 54, 22, 62, 30,
        37, 5, 45, 13, 53, 21, 61, 29,
        36, 4, 44, 12, 52, 20, 60, 28,
        35, 3, 43, 11, 51, 19, 59, 27,
        34, 2, 42, 10, 50, 18, 58, 26,
        33, 1, 41, 9, 49, 17, 57, 25,
    ]

    static func encryptBlock(block: [UInt8], key: [UInt8]) -> Data {
        var bits = toBits(block)
        bits = permute(bits, initialPermutation)
        var left = Array(bits[0..<32])
        var right = Array(bits[32..<64])
        let subkeys = generateSubkeys(key: key)
        for round in 0..<16 {
            let newRight = xor(left, feistel(right, subkeys[round]))
            left = right
            right = newRight
        }
        var combined = right + left
        combined = permute(combined, finalPermutation)
        return fromBits(combined)
    }

    static func generateSubkeys(key: [UInt8]) -> [[Int]] {
        var keyBits = toBits(key)
        keyBits = permute(keyBits, pc1)
        var c = Array(keyBits[0..<28])
        var d = Array(keyBits[28..<56])
        var subkeys: [[Int]] = []
        for round in 0..<16 {
            for _ in 0..<shifts[round] {
                c.append(c.removeFirst())
                d.append(d.removeFirst())
            }
            subkeys.append(permute(c + d, pc2))
        }
        return subkeys
    }

    static func feistel(_ right: [Int], _ subkey: [Int]) -> [Int] {
        let expanded = permute(right, expansion)
        let xored = xor(expanded, subkey)
        var sboxed: [Int] = []
        for i in 0..<8 {
            let chunk = Array(xored[i * 6..<(i * 6 + 6)])
            let row = chunk[0] * 2 + chunk[5]
            let col = chunk[1] * 8 + chunk[2] * 4 + chunk[3] * 2 + chunk[4]
            let value = sboxes[i][row][col]
            for bit in stride(from: 3, through: 0, by: -1) {
                sboxed.append((value >> bit) & 1)
            }
        }
        return permute(sboxed, pbox)
    }

    static func permute(_ bits: [Int], _ table: [Int]) -> [Int] {
        table.map { bits[$0 - 1] }
    }

    static func xor(_ a: [Int], _ b: [Int]) -> [Int] {
        a.enumerated().map { $0.element ^ b[$0.offset] }
    }

    static func toBits(_ bytes: [UInt8]) -> [Int] {
        bytes.flatMap { byte in (0..<8).map { Int((byte >> (7 - $0)) & 1) } }
    }

    static func fromBits(_ bits: [Int]) -> Data {
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                byte = (byte << 1) | UInt8(bits[i + j])
            }
            bytes.append(byte)
        }
        return Data(bytes)
    }
}
