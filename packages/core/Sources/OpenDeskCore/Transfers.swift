// Transfers — file push/pull via SFTP (system /usr/bin/sftp in batch mode)
// and package deployment via SFTP staging + `installer`.
// Behavior specs: copy-files.yaml, install-package.yaml
//
// Pipeline (install):
//   .pkg -> local checksum -> SFTP stage to remote temp
//   -> sudo installer -pkg PKG -target / -> capture exit/output
//   -> delete staging artifact -> optional reboot

import Foundation
import CryptoKit

public struct TransferResult: Codable, Sendable, Equatable {
    public var exitCode: Int
    public var output: String
    public var checksumSource: String?
    public var checksumRemote: String?
    public var durationSeconds: Double

    public init(exitCode: Int, output: String, checksumSource: String? = nil, checksumRemote: String? = nil, durationSeconds: Double) {
        self.exitCode = exitCode
        self.output = output
        self.checksumSource = checksumSource
        self.checksumRemote = checksumRemote
        self.durationSeconds = durationSeconds
    }
}

public enum TransferError: Error, Sendable, Equatable {
    case sourceNotFound(String)
    case checksumMismatch(local: String, remote: String)
    case stagingFailed(String)
}

public final class TransferEngine: @unchecked Sendable {
    let ssh: SSHTransport
    let sftpPath: String

    public init(ssh: SSHTransport, sftpPath: String = "/usr/bin/sftp") {
        self.ssh = ssh
        self.sftpPath = sftpPath
    }

    // MARK: - Push (local -> remote)

    /// Push a file or directory to a remote path via SFTP batch mode.
    @discardableResult
    public func push(
        localPath: String,
        toRemote remotePath: String,
        on host: SSHHost,
        verifyChecksum: Bool = true
    ) async throws -> TransferResult {
        guard FileManager.default.fileExists(atPath: localPath) else {
            throw TransferError.sourceNotFound(localPath)
        }
        let start = Date()
        let localChecksum = verifyChecksum ? try Self.sha256(path: localPath) : nil

        // Ensure remote destination directory exists.
        let dir = (remotePath as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            _ = try? await ssh.execute("mkdir -p \(ssh.shellQuote(dir))", on: host)
        }

        // SFTP batch: put -r preserves recursion.
        let batch = "put \"\(localPath)\" \"\(remotePath)\"\n"
        let args = [
            "-P", String(host.port),
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            host.hostname,
        ]
        let result = try await ssh.runProcess(sftpPath, args: args, timeout: 3600, stdinData: Data(batch.utf8))
        let duration = Date().timeIntervalSince(start)

        var remoteChecksum: String? = nil
        if verifyChecksum, result.exitCode == 0, let localChecksum {
            let probe = try await ssh.execute("shasum -a 256 \(ssh.shellQuote(remotePath)) 2>/dev/null | cut -d' ' -f1", on: host)
            remoteChecksum = probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if remoteChecksum?.lowercased() != localChecksum.lowercased() {
                throw TransferError.checksumMismatch(local: localChecksum, remote: remoteChecksum ?? "unreadable")
            }
        }

        return TransferResult(
            exitCode: result.exitCode,
            output: result.stdout + result.stderr,
            checksumSource: localChecksum,
            checksumRemote: remoteChecksum,
            durationSeconds: duration
        )
    }

    // MARK: - Pull (remote -> local)

    @discardableResult
    public func pull(
        remotePath: String,
        toLocal localPath: String,
        on host: SSHHost
    ) async throws -> TransferResult {
        let start = Date()
        let dir = (localPath as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let batch = "get \"\(remotePath)\" \"\(localPath)\"\n"
        let args = [
            "-P", String(host.port),
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            host.hostname,
        ]
        let result = try await ssh.runProcess(sftpPath, args: args, timeout: 3600, stdinData: Data(batch.utf8))
        return TransferResult(
            exitCode: result.exitCode,
            output: result.stdout + result.stderr,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }

    // MARK: - Package install

    /// Full package deployment pipeline per install-package.yaml.
    @discardableResult
    public func installPackage(
        packagePath: String,
        on host: SSHHost,
        restartPolicy: String = "none",
        stagingPath: String = "/tmp/opendesk-staging"
    ) async throws -> TransferResult {
        let start = Date()
        let fileName = (packagePath as NSString).lastPathComponent
        let remotePkg = "\(stagingPath)/\(fileName)"

        // 1. Local checksum before upload.
        let localChecksum = try Self.sha256(path: packagePath)

        // 2. Stage via SFTP.
        let staged = try await push(localPath: packagePath, toRemote: remotePkg, on: host, verifyChecksum: true)

        // 3. Install non-interactively.
        let install = try await ssh.execute(
            "sudo installer -pkg \(ssh.shellQuote(remotePkg)) -target /",
            on: host, timeout: 1800, runAsRoot: false
        )

        // 4. Remove staging artifact regardless of install outcome.
        _ = try? await ssh.execute("rm -f \(ssh.shellQuote(remotePkg))", on: host)

        // 5. Optional reboot per restart policy.
        var rebootOutput = ""
        if restartPolicy == "restart", install.exitCode == 0 {
            let reboot = try? await ssh.execute("echo 'Reboot requested by OpenDesk' | sudo shutdown -r now", on: host, timeout: 15)
            rebootOutput = reboot.map { $0.stdout + $0.stderr } ?? ""
        }

        let duration = Date().timeIntervalSince(start)
        let payload: [String: Any] = [
            "installer_exit_code": install.exitCode,
            "installer_output": install.stdout + install.stderr,
            "reboot": rebootOutput,
            "checksum": localChecksum,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        return TransferResult(
            exitCode: install.exitCode,
            output: String(data: json, encoding: .utf8) ?? "{}",
            checksumSource: localChecksum,
            checksumRemote: staged.checksumRemote,
            durationSeconds: duration
        )
    }

    // MARK: - Checksums

    static func sha256(path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) // 1 MiB
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
