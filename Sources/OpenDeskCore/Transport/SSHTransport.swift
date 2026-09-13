import Foundation

/// Abstraction over a command-execution transport so the task engine can be
/// unit-tested with mock transports and is not hard-wired to SSH.
public protocol CommandTransport {
    func run(command: String, timeoutSeconds: Int?) throws -> (stdout: String, stderr: String, exitCode: Int32)
    func ping() -> Bool
}

/// SSHTransport already satisfies CommandTransport via its existing API.
extension SSHTransport: CommandTransport {}

/// Executes commands and file transfers on a client host over SSH.
/// Uses the system `ssh`/`scp` binaries — no client agent required.
public struct SSHTransport: Sendable {
    public struct Configuration: Sendable {
        public var timeoutSeconds: Int
        public var sshBinaryPath: String
        public var scpBinaryPath: String

        public init(timeoutSeconds: Int = 30, sshBinaryPath: String = "/usr/bin/ssh", scpBinaryPath: String = "/usr/bin/scp") {
            self.timeoutSeconds = timeoutSeconds
            self.sshBinaryPath = sshBinaryPath
            self.scpBinaryPath = scpBinaryPath
        }
    }

    public enum TransportError: Error, Equatable {
        case hostUnreachable(String)
        case authenticationFailed(String)
        case commandFailed(exitCode: Int32, stderr: String)
        case binaryMissing(String)
    }

    public let host: Host
    public let configuration: Configuration

    public init(host: Host, configuration: Configuration = Configuration()) {
        self.host = host
        self.configuration = configuration
    }

    var remoteSpecifier: String {
        "\(host.username)@\(host.hostname)"
    }

    var baseArguments: [String] {
        var args = [
            "-p", String(host.port),
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=\(configuration.timeoutSeconds)",
        ]
        if host.authMethod == .password {
            // Password auth requires an askpass helper; MVP prefers keys.
            args += ["-o", "PreferredAuthentications=password,keyboard-interactive"]
        }
        return args
    }

    /// Run a shell command on the remote host and capture stdout/stderr.
    public func run(command: String, timeoutSeconds: Int? = nil) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.sshBinaryPath)
        process.arguments = baseArguments + [remoteSpecifier, command]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw TransportError.binaryMissing(configuration.sshBinaryPath)
        }

        let deadline = Date().addingTimeInterval(Double(timeoutSeconds ?? configuration.timeoutSeconds))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw TransportError.hostUnreachable("timeout after \(timeoutSeconds ?? configuration.timeoutSeconds)s")
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let exit = process.terminationStatus

        if exit == 255, stderr.contains("Permission denied") {
            throw TransportError.authenticationFailed(remoteSpecifier)
        }
        if exit == 255, stderr.contains("Could not resolve") || stderr.contains("Connection refused") || stderr.contains("timed out") {
            throw TransportError.hostUnreachable(remoteSpecifier)
        }
        return (stdout, stderr, exit)
    }

    /// Copy a local file to the remote host.
    public func pushFile(localPath: String, remotePath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.scpBinaryPath)
        process.arguments = ["-P", String(host.port), "-o", "BatchMode=yes", localPath, "\(remoteSpecifier):\(remotePath)"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TransportError.commandFailed(exitCode: process.terminationStatus, stderr: "scp failed for \(localPath)")
        }
    }

    /// Ping the host to check reachability + auth.
    public func ping() -> Bool {
        do {
            let result = try run(command: "true", timeoutSeconds: 10)
            return result.exitCode == 0
        } catch {
            return false
        }
    }
}
