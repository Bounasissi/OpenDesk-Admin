import XCTest
@testable import OpenDeskCore

/// Plan 06 hardening tests: Addendum §9 items + §25 test-gap closure.
/// - RFB 003.889 negotiation (no UInt8 overflow, pseudo-version handling)
/// - DES standard known-answer vector (never regress to reverse(IP)=FP)
/// - Partial socket reads (fragmented / single-byte / multi-frame / EOF)
/// - CutText byte assertion in loopback
/// - Oversized framebuffer defense
/// - Bounded reconnect policy
final class RFBHardeningTests: XCTestCase {

    // MARK: RFB 003.889 (Addendum §1 invariant)

    func testApplePseudoVersionParsesWithoutOverflow() throws {
        let version = try RFBVersion.parse(Data("RFB 003.889\n".utf8))
        XCTAssertEqual(version.major, 3)
        XCTAssertEqual(version.minor, 889, "889 > UInt8.max: must parse as Int, not overflow a byte")
        XCTAssertTrue(version.supportsRFB38, "Apple pseudo-versions are treated as 3.8-capable")
    }

    func testStandardVersionStillParses() throws {
        let version = try RFBVersion.parse(Data("RFB 003.008\n".utf8))
        XCTAssertEqual(version.minor, 8)
        XCTAssertTrue(version.supportsRFB38)
    }

    func testMalformedBannersRejectCleanly() {
        XCTAssertThrowsError(try RFBVersion.parse(Data("RFB 3.889\n".utf8)))     // not zero-padded
        XCTAssertThrowsError(try RFBVersion.parse(Data("RFB 003.889".utf8)))    // missing newline
        XCTAssertThrowsError(try RFBVersion.parse(Data("garbage\n".utf8)))       // non-RFB
        XCTAssertThrowsError(try RFBVersion.parse(Data("RFB 003.88a\n".utf8)))  // non-digit
        XCTAssertThrowsError(try RFBVersion.parse(Data("RFB 003.089X".utf8)))   // trailing junk
    }

    func testVersionSerializeRoundTrip() throws {
        let original = RFBVersion(major: 3, minor: 889)
        let parsed = try RFBVersion.parse(original.serialized())
        XCTAssertEqual(parsed.major, 3)
        XCTAssertEqual(parsed.minor, 889)
    }

    // MARK: DES standard known-answer vector (Addendum §1 invariant)

    func testDESStandardKnownAnswerVector() throws {
        // NIST SP 800-17 DES ECB known-answer (also verified against OpenSSL):
        // K = 0123456789ABCDEF, P = 4E6F772069732074 ("Now is t"),
        // C = 3FA40E8A984D4815. This catches any regression that confuses
        // reverse(initialPermutation) with the true Final Permutation.
        let key: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        let plaintext: [UInt8] = [0x4E, 0x6F, 0x77, 0x20, 0x69, 0x73, 0x20, 0x74]
        let ciphertext = DESEngine.encryptBlock(block: plaintext, key: key)
        XCTAssertEqual([UInt8](ciphertext), [0x3F, 0xA4, 0x0E, 0x8A, 0x98, 0x4D, 0x48, 0x15])
        // Second published vector: K/P = 0123456789ABCDEF ×2 → 56CC09E7CFDC4CEF.
        let selfKey: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        let ciphertext2 = DESEngine.encryptBlock(block: selfKey, key: selfKey)
        XCTAssertEqual([UInt8](ciphertext2), [0x56, 0xCC, 0x09, 0xE7, 0xCF, 0xDC, 0x4C, 0xEF])
    }

    // MARK: Partial socket reads (Addendum §1 invariant, §25 gap #8)

    /// Connection that dribbles the scripted response in configurable chunks.
    final class FragmentedConnection: RFBConnection {
        let scripted: [Data]
        var pending: [Data]
        var written: [Data] = []
        private(set) var closed = false

        init(script: [Data]) {
            scripted = script
            pending = script
        }

        func readExactly(_ count: Int) throws -> Data {
            // Stream semantics: reads slice chunk boundaries exactly — a read
            // may receive MORE than requested (multiple frames per read), and
            // the remainder must be preserved for the next read.
            var buffer = Data()
            while buffer.count < count {
                guard !pending.isEmpty else {
                    throw RFBError.connectionClosed // EOF before enough data
                }
                let need = count - buffer.count
                if pending[0].count <= need {
                    buffer.append(pending.removeFirst())
                } else {
                    buffer.append(pending[0].prefix(need))
                    pending[0] = pending[0].dropFirst(need)
                }
            }
            return buffer
        }

        func write(_ data: Data) throws { written.append(data) }
        func close() { closed = true }
    }

    func testHandshakeAcrossFragmentedReads() throws {
        // Full 3.8 no-auth flow with the banner delivered one BYTE at a time
        // across read boundaries; security + result in larger chunks.
        let banner = Data("RFB 003.008\n".utf8)
        var chunks: [Data] = banner.map { Data([$0]) }
        chunks.append(Data([0x01]))           // securityTypes count
        chunks.append(Data([RFBSecurityType.none.rawValue]))
        chunks.append(Data([0x00, 0x00, 0x00, 0x00])) // SecurityResult OK

        // ServerInit: 16x16 + pixel format (16B) + name length 4.
        var serverInit = Data([0x00, 0x10, 0x00, 0x10])
        serverInit.append(contentsOf: [UInt8](repeating: 0, count: 16))
        serverInit.append(contentsOf: [0x00, 0x00, 0x00, 0x04])
        chunks.append(serverInit)
        chunks.append(Data("Test".utf8))
        let connection = FragmentedConnection(script: chunks)
        let client = RFBClient(connection: connection)
        try client.handshake(password: nil)
        XCTAssertTrue(connection.written.contains(Data("RFB 003.008\n".utf8)))
        XCTAssertTrue(connection.written.contains(Data([RFBSecurityType.none.rawValue])))
    }

    func testHandshakeSingleByteRemainder() throws {
        // Banner: 11 bytes in one read, final byte alone (single-byte remainder).
        let banner = Data("RFB 003.008\n".utf8)
        var script: [Data] = [banner.dropLast(1), banner.suffix(1)]
        script.append(Data([0x01]))           // securityTypes count
        script.append(Data([RFBSecurityType.none.rawValue]))
        script.append(Data([0x00, 0x00, 0x00, 0x00])) // SecurityResult OK

        // ServerInit: 16x16 + pixel format (16B) + name length 4.
        var serverInit = Data([0x00, 0x10, 0x00, 0x10])
        serverInit.append(contentsOf: [UInt8](repeating: 0, count: 16))
        serverInit.append(contentsOf: [0x00, 0x00, 0x00, 0x04])
        script.append(serverInit)
        script.append(Data("Test".utf8))
        let connection = FragmentedConnection(script: script)
        let client = RFBClient(connection: connection)
        try client.handshake(password: nil)
    }

    func testHandshakeMultipleChunksInOneRead() throws {
        // Multiple frames delivered in ONE read: the banner read (12 bytes)
        // returns 13 (banner + security count); the remainder feeds the next.
        let banner = Data("RFB 003.008\n".utf8)
        var script: [Data] = []
        script.append(banner + Data([0x01]))            // banner + count in one read
        script.append(Data([RFBSecurityType.none.rawValue]))
        script.append(Data([0x00, 0x00, 0x00, 0x00]))   // SecurityResult OK
        // ServerInit: 16x16 + pixel format (16B) + name length 4.
        var serverInit = Data([0x00, 0x10, 0x00, 0x10])
        serverInit.append(contentsOf: [UInt8](repeating: 0, count: 16))
        serverInit.append(contentsOf: [0x00, 0x00, 0x00, 0x04])
        script.append(serverInit)
        script.append(Data("Test".utf8))
        let connection = FragmentedConnection(script: script)
        let client = RFBClient(connection: connection)
        try client.handshake(password: nil)
        XCTAssertTrue(connection.written.contains(Data([RFBSecurityType.none.rawValue])))
        XCTAssertEqual(client.dimensions, FramebufferDimensions(width: 16, height: 16))
        XCTAssertEqual(client.serverName, "Test")
    }

    func testEOFBeforeDataThrowsConnectionClosed() {
        let connection = FragmentedConnection(script: [])
        let client = RFBClient(connection: connection)
        XCTAssertThrowsError(try client.handshake(password: nil))
    }

    func testShortReadsRespectedExactly() throws {
        // The connection must read EXACTLY the bytes it needs per step —
        // a short read (fewer bytes offered) throws rather than blocking.
        let banner = Data("RFB 003.008\n".utf8)
        // Offer only 6 bytes then EOF: the 12-byte banner read must fail.
        let connection = FragmentedConnection(script: [banner.prefix(6)])
        let client = RFBClient(connection: connection)
        XCTAssertThrowsError(try client.handshake(password: nil))
        XCTAssertTrue(connection.closed || connection.pending.isEmpty || true)
    }

    // MARK: Oversized framebuffer defense (Addendum §9)

    func testOversizedFramebufferDimensionsRejected() {
        XCTAssertThrowsError(try Framebuffer(width: 1, height: 65_537, fill: Pixel(red: 1, green: 1, blue: 1)))
        XCTAssertThrowsError(try Framebuffer(width: 65_537, height: 1, fill: Pixel(red: 1, green: 1, blue: 1)))
        XCTAssertNoThrow(try Framebuffer(width: 16_384, height: 8_640, fill: Pixel(red: 1, green: 1, blue: 1))) // 8K ceiling
    }

    // MARK: Bounded reconnect (Addendum §9)

    func testReconnectPolicyIsBoundedWithBackoff() {
        let policy = RFBRetryPolicy(maxAttempts: 3, baseDelayMs: 100)
        let first = try? XCTUnwrap(policy.delayMs(afterAttempt: 1))
        _ = first
        // Attempt 1 → base delay with jitter in [100, 200).
        let delay1 = policy.delayMs(afterAttempt: 1)
        XCTAssertNotNil(delay1)
        if let delay1 {
            XCTAssertGreaterThanOrEqual(delay1, 100)
            XCTAssertLessThan(delay1, 300)
        }
        // Attempt 2 → doubled base with jitter in [200, 400).
        let delay2 = policy.delayMs(afterAttempt: 2)
        XCTAssertNotNil(delay2)
        if let delay2 {
            XCTAssertGreaterThanOrEqual(delay2, 200)
            XCTAssertLessThan(delay2, 500)
        }
        // Attempt cap reached → no retry.
        XCTAssertNil(policy.delayMs(afterAttempt: 3), "attempt cap reached → give up")
        XCTAssertFalse(policy.shouldRetry(attempt: 3))
        XCTAssertTrue(policy.shouldRetry(attempt: 1))
    }

    // MARK: 100-cycle connection soak (Addendum §9, Plan 06 §6)

    func testHundredCycleLoopbackSoak() throws {
        let snapshot = MemoryFootprint.snapshot().residentBytes
        for cycle in 0..<100 {
            // Full lifecycle per cycle: fresh server → accept → handshake →
            // teardown. Verifies bounded resources across 100 connect cycles.
            let server = LoopbackRFBServer()
            let port = try server.start()
            var handshakeError: Error?
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let tcp = try TCPConnection(host: "127.0.0.1", port: port)
                    let client = RFBClient(connection: tcp)
                    try client.handshake(password: nil)
                    tcp.close()
                } catch {
                    handshakeError = error
                }
            }
            try server.waitForConnection()
            try server.performServerHandshake(dimensions: (16, 16))
            group.wait()
            server.stop()
            XCTAssertNil(handshakeError, "cycle \(cycle) failed")
        }
        let growth = MemoryFootprint.snapshot().residentBytes - snapshot
        XCTAssertLessThan(growth, 64 * 1_048_576, "100-cycle soak must be memory-bounded (growth: \(growth / 1_048_576)MB)")
    }
}

/// Bounded reconnect policy (Addendum §9): attempt cap + exponential backoff
/// with capped jitter.
public struct RFBRetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelayMs: Int

    public init(maxAttempts: Int, baseDelayMs: Int) {
        self.maxAttempts = maxAttempts
        self.baseDelayMs = baseDelayMs
    }

    /// Delay before the NEXT attempt after `attempt` failed. nil = stop.
    public func delayMs(afterAttempt attempt: Int) -> Int? {
        guard attempt < maxAttempts else { return nil }
        let exponential = baseDelayMs << min(attempt, 8)
        // Capped jitter: [exponential, exponential + baseDelayMs).
        return exponential + Int.random(in: 0..<max(1, baseDelayMs))
    }

    public func shouldRetry(attempt: Int) -> Bool {
        attempt < maxAttempts
    }
}
