import XCTest
@testable import OpenDeskCore

final class VNCAuthTests: XCTestCase {
    func testBitReversal() {
        XCTAssertEqual(UInt8(0b00000001).reversedBits(), 0b10000000)
        XCTAssertEqual(UInt8(0b11111111).reversedBits(), 0b11111111)
        XCTAssertEqual(UInt8(0b10100000).reversedBits(), 0b00000101)
    }

    func testDerivedKeyPadsTo8Bytes() {
        let key = VNCAuth.derivedKey(from: "abc")
        XCTAssertEqual(key.count, 8)
        XCTAssertEqual(key[0], UInt8(ascii: "a").reversedBits())
        XCTAssertEqual(key[3], 0)
    }

    func testDerivedKeyTruncatesLongPasswords() {
        let key = VNCAuth.derivedKey(from: "0123456789")
        XCTAssertEqual(key.count, 8)
        XCTAssertEqual(key[7], UInt8(ascii: "7").reversedBits())
    }

    func testChallengeResponseIs16BytesAndDeterministic() {
        let challenge = Data([UInt8](repeating: 0xA5, count: 16))
        let first = VNCAuth.encryptChallenge(challenge, password: "hunter2")
        let second = VNCAuth.encryptChallenge(challenge, password: "hunter2")
        XCTAssertEqual(first.count, 16)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, challenge) // encrypted output differs from input
    }

    func testDESEncryptBlockOutputLengthAndDeterminism() {
        let block = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        let key = VNCAuth.derivedKey(from: "test")
        let out1 = DESEngine.encryptBlock(block: [UInt8](block), key: key)
        let out2 = DESEngine.encryptBlock(block: [UInt8](block), key: key)
        XCTAssertEqual(out1.count, 8)
        XCTAssertEqual(out1, out2)
        // DES with a known key is deterministic — sanity check the round trip
        // against the well-known test vector: plaintext 0123456789ABCDEF with
        // key 133457799BBCDFF1 encrypts to 85E813540F0AB405.
        let vectorKey: [UInt8] = [0x13, 0x34, 0x57, 0x79, 0x9B, 0xBC, 0xDF, 0xF1]
        let vectorPlaintext: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        let vectorCipher = DESEngine.encryptBlock(block: vectorPlaintext, key: vectorKey)
        XCTAssertEqual(vectorCipher.map { String(format: "%02X", $0) }.joined(), "85E813540F0AB405")
    }
}
