import XCTest
import Foundation
@testable import OpenDeskCore

/// Plan 07 tests: file-transfer contract (Addendum §13), checksum
/// verification, conflict policy, package pipeline outcome, tunnel policy.
final class DistributionContractTests: XCTestCase {

    // MARK: SHA-256 checksum verification (Plan 07 A1.2)

    func testSHA256KnownAnswer() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-dist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: fileURL)
        let checksum = try FileChecksum.sha256(of: fileURL)
        // Verified: echo -n hello | shasum -a 256
        XCTAssertEqual(checksum, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    func testChecksumMismatchDetected() throws {
        let mismatch = FileChecksum.verify(localChecksum: "aaa", remoteChecksum: "bbb")
        XCTAssertEqual(mismatch, .mismatch)
        let match = FileChecksum.verify(localChecksum: "aaa", remoteChecksum: "aaa")
        XCTAssertEqual(match, .verified)
        let unavailable = FileChecksum.verify(localChecksum: "aaa", remoteChecksum: nil)
        XCTAssertEqual(unavailable, .unknown)
    }

    // MARK: Conflict policy (Plan 07 A1.2)

    func testConflictPolicyDecisions() {
        // Overwrite: explicit choice.
        XCTAssertEqual(FileTransferPolicy(overwrite: .always).conflictAction(remoteExists: true, remoteChecksum: nil, localChecksum: nil), .overwrite)
        // Skip: never overwrite.
        XCTAssertEqual(FileTransferPolicy(overwrite: .never).conflictAction(remoteExists: true, remoteChecksum: nil, localChecksum: nil), .skip)
        // Identical checksum → skip regardless of overwrite preference.
        XCTAssertEqual(
            FileTransferPolicy(overwrite: .always).conflictAction(remoteExists: true, remoteChecksum: "aa", localChecksum: "aa"),
            .skipIdentical
        )
        // Rename-on-conflict.
        XCTAssertEqual(FileTransferPolicy(overwrite: .always, renameOnConflict: true).conflictAction(remoteExists: true, remoteChecksum: "aa", localChecksum: "bb"), .rename)
        // Different checksum, overwrite allowed (no rename) → overwrite.
        XCTAssertEqual(FileTransferPolicy(overwrite: .always).conflictAction(remoteExists: true, remoteChecksum: "aa", localChecksum: "bb"), .overwrite)
    }

    // MARK: Package pipeline command shape (checksum → stage → installer → cleanup)

    func testPackagePipelineCommandShape() {
        let pipeline = PackageInstallPipeline(remoteStagingPath: "/tmp/od-stage/tool.pkg", useSudo: true)
        let commands = pipeline.remoteCommandSequence(remoteChecksum: "abc123")
        // Verify checksum → install → cleanup sequence shape.
        XCTAssertEqual(commands.count, 4)
        XCTAssertTrue(commands[0].contains("shasum -a 256"), "remote checksum first")
        XCTAssertTrue(commands[1].contains("installer"), "installer second")
        XCTAssertTrue(commands[2].contains("rm -f"), "staging cleanup third")
        XCTAssertTrue(commands[3].contains("shasum -a 256"), "post-install remote artifact absent")
    }

    // MARK: Tunnel policy (Plan 07 A1.1 — lifecycle/diagnostics surface)

    func testTunnelCommandShapeAndDiagnostics() {
        let policy = TunnelPolicy(
            host: "mac1.local", port: 2222, screenPort: 5900,
            localPort: 15900, identity: "ops_key"
        )
        let args = policy.sshArguments()
        XCTAssertTrue(args.contains("-N") && args.contains("-T"), "no shell, no remote command")
        XCTAssertTrue(args.contains("15900:127.0.0.1:5900"), "local forward spec: local → remote target")
        XCTAssertTrue(args.contains("-p") && args.contains("2222"), "remote port")
        XCTAssertTrue(args.contains("ExitOnForwardFailure=yes"), "forward failure must surface")
        if args.contains("-i") {
            let index = args.firstIndex(of: "-i")!
            XCTAssertEqual(args[index + 1], "ops_key", "identity selection per device")
        }
        let diagnostics = TunnelDiagnostics(state: .connected, lastError: nil, endpoint: "mac1.local:2222")
        XCTAssertEqual(diagnostics.summary, "connected → mac1.local:2222")
        let failed = TunnelDiagnostics(state: .failed(reason: "port in use"), lastError: "EADDRINUSE", endpoint: "mac1.local:2222")
        XCTAssertTrue(failed.summary.contains("failed"))
    }

    // MARK: Overwrite policy applied to copy pipeline — command construction

    func testRsyncOverwriteCommandShape() {
        let policy = FileTransferPolicy(overwrite: .never)
        let args = policy.rsyncExtraArguments()
        XCTAssertTrue(args.contains("--ignore-existing"), "never-overwrite maps to --ignore-existing")
        let always = FileTransferPolicy(overwrite: .always)
        XCTAssertTrue(always.rsyncExtraArguments().contains("--checksum"), "overwrite verifies by checksum")
    }
}
