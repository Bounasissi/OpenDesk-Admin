import Foundation

/// Pushes files and installs packages on client Macs (ARD "Copy Items" /
/// "Install Packages" equivalents), backed by scp + installer over SSH.
public struct DistributionEngine: Sendable {
    public enum DistributionError: Error, Equatable {
        case localFileMissing(String)
        case unsupportedPackageType(String)
    }

    public init() {}

    /// Copy a local file or folder to a remote host path (ARD "Copy Items").
    /// Directories are transferred with rsync; single files with scp.
    public func copyItem(localPath: String, toHost host: Host, remotePath: String) throws -> TaskResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localPath, isDirectory: &isDirectory) else {
            throw DistributionError.localFileMissing(localPath)
        }

        let transport = SSHTransport(host: host)
        let start = Date()
        do {
            if isDirectory.boolValue {
                try runProcess("/usr/bin/rsync", args: [
                    "-az", "-e",
                    "ssh -p \(host.port) -o BatchMode=yes -o StrictHostKeyChecking=accept-new",
                    localPath,
                    "\(transport.remoteSpecifier):\(remotePath)",
                ])
            } else {
                try transport.pushFile(localPath: localPath, remotePath: remotePath)
            }
            return TaskResult(
                taskId: UUID(),
                host: host.hostname,
                exitCode: 0,
                stdout: "copied \(localPath) to \(remotePath)",
                durationMs: Int(Date().timeIntervalSince(start) * 1000)
            )
        } catch {
            return TaskResult(
                taskId: UUID(),
                host: host.hostname,
                exitCode: -1,
                errorDescription: String(describing: error),
                durationMs: Int(Date().timeIntervalSince(start) * 1000)
            )
        }
    }

    /// Copy a .pkg to the client and install it via `installer` (ARD "Install Packages").
    /// Requires the SSH user to have admin rights (installer runs with sudo).
    public func installPackage(localPath: String, toHost host: Host, useSudo: Bool = true) throws -> TaskResult {
        let ext = (localPath as NSString).pathExtension.lowercased()
        guard ext == "pkg" else {
            throw DistributionError.unsupportedPackageType(ext)
        }

        let transport = SSHTransport(host: host)
        let remoteStaging = "/tmp/\((localPath as NSString).lastPathComponent)"

        let copyResult = try copyItem(localPath: localPath, toHost: host, remotePath: remoteStaging)
        guard copyResult.succeeded else { return copyResult }

        let installerCommand = useSudo
            ? "sudo installer -pkg \(remoteStaging) -target /"
            : "installer -pkg \(remoteStaging) -target /"
        let installStart = Date()
        let output = try transport.run(command: installerCommand, timeoutSeconds: 600)
        // Clean staging copy regardless of install outcome.
        _ = try? transport.run(command: "rm -f \(remoteStaging)")

        return TaskResult(
            taskId: UUID(),
            host: host.hostname,
            exitCode: output.exitCode,
            stdout: output.stdout,
            stderr: output.stderr,
            durationMs: Int(Date().timeIntervalSince(installStart) * 1000)
        )
    }

    private func runProcess(_ path: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SSHTransport.TransportError.commandFailed(exitCode: process.terminationStatus, stderr: "process \(path) failed")
        }
    }
}
