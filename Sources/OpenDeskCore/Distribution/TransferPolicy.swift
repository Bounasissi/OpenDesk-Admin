import Foundation
import CryptoKit

// MARK: - File checksums (Plan 07 A1.2)

public enum FileChecksum {
    public enum Verification: Equatable, Sendable {
        case verified
        case mismatch
        case unknown
    }

    /// SHA-256 of a local file (hex, lowercase).
    public static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(localChecksum: String?, remoteChecksum: String?) -> Verification {
        switch (localChecksum, remoteChecksum) {
        case (let a?, let b?):
            return a.lowercased() == b.lowercased() ? .verified : .mismatch
        default:
            return .unknown
        }
    }
}

// MARK: - Transfer policy (Plan 07 A1.2)

public enum OverwritePolicy: String, Codable, Sendable, CaseIterable {
    case always
    case never
    case ask // resolved by the caller; v1 defaults to never
}

public enum ConflictAction: Equatable, Sendable {
    case overwrite
    case skip
    case skipIdentical
    case rename
}

/// File-transfer conflict policy (Plan 07 A1.2): overwrite policy,
/// rename-on-conflict, checksum verification — explicit choices.
public struct FileTransferPolicy: Sendable {
    public let overwrite: OverwritePolicy
    public let renameOnConflict: Bool
    public let verifyChecksum: Bool

    public init(overwrite: OverwritePolicy, renameOnConflict: Bool = false, verifyChecksum: Bool = true) {
        self.overwrite = overwrite
        self.renameOnConflict = renameOnConflict
        self.verifyChecksum = verifyChecksum
    }

    public func conflictAction(remoteExists: Bool, remoteChecksum: String?, localChecksum: String?) -> ConflictAction {
        guard remoteExists else { return .overwrite }
        if verifyChecksum, let local = localChecksum, let remote = remoteChecksum, local.lowercased() == remote.lowercased() {
            return .skipIdentical
        }
        if renameOnConflict {
            return .rename
        }
        switch overwrite {
        case .always: return .overwrite
        case .never, .ask: return .skip
        }
    }

    /// rsync flag mapping (used when the transfer uses rsync transport).
    public func rsyncExtraArguments() -> [String] {
        var args: [String] = []
        switch overwrite {
        case .never: args.append("--ignore-existing")
        case .always, .ask: args.append("--checksum")
        }
        if renameOnConflict {
            args.append(contentsOf: ["--backup", "--suffix=.opendesk-conflict"])
        }
        return args
    }
}

// MARK: - Package install pipeline (Plan 07 A1.2 / §5)

/// Command sequence for the remote package pipeline:
/// verify remote checksum → installer → staging cleanup → artifact absence check.
public struct PackageInstallPipeline: Sendable {
    public let remoteStagingPath: String
    public let useSudo: Bool

    public init(remoteStagingPath: String, useSudo: Bool = true) {
        self.remoteStagingPath = remoteStagingPath
        self.useSudo = useSudo
    }

    public func remoteCommandSequence(remoteChecksum: String) -> [String] {
        let installerBin = useSudo ? "sudo installer" : "installer"
        return [
            // 1. Verify the staged artifact matches the local checksum.
            "shasum -a 256 \(remoteStagingPath) | awk '{print $1}' | grep -x '\(remoteChecksum)'",
            // 2. Install and capture the result.
            "\(installerBin) -pkg \(remoteStagingPath) -target /",
            // 3. Safe staging cleanup (no orphan temp files).
            "rm -f \(remoteStagingPath)",
            // 4. Confirm the artifact is gone (post-condition).
            "test ! -f \(remoteStagingPath) && echo cleanup-ok || shasum -a 256 \(remoteStagingPath)",
        ]
    }
}

// MARK: - Tunnel policy + diagnostics (Plan 07 A1.1)

public struct TunnelPolicy: Sendable {
    public let host: String
    public let port: Int
    public let screenPort: Int
    public let localPort: Int
    public let identity: String?

    public init(host: String, port: Int, screenPort: Int, localPort: Int, identity: String? = nil) {
        self.host = host
        self.port = port
        self.screenPort = screenPort
        self.localPort = localPort
        self.identity = identity
    }

    public func sshArguments() -> [String] {
        var args = ["-N", "-T", "-o", "ExitOnForwardFailure=yes"]
        args.append(contentsOf: ["-p", String(port)])
        if let identity {
            args.append(contentsOf: ["-i", identity])
        }
        args.append(contentsOf: ["-L", "\(localPort):127.0.0.1:\(screenPort)"])
        args.append(host)
        return args
    }
}

public enum TunnelState: Equatable, Sendable {
    case starting
    case connected
    case reconnecting(attempt: Int)
    case failed(reason: String)
}

public struct TunnelDiagnostics: Equatable, Sendable {
    public let state: TunnelState
    public let lastError: String?
    public let endpoint: String

    public init(state: TunnelState, lastError: String?, endpoint: String) {
        self.state = state
        self.lastError = lastError
        self.endpoint = endpoint
    }

    public var summary: String {
        let stateText: String
        switch state {
        case .starting: stateText = "starting"
        case .connected: stateText = "connected"
        case .reconnecting(let attempt): stateText = "reconnecting(\(attempt))"
        case .failed(let reason): stateText = "failed(\(reason))"
        }
        return "\(stateText) → \(endpoint)\(lastError.map { " [\(String(describing: $0))]" } ?? "")"
    }
}
