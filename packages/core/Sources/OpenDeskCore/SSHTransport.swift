// SSHTransport — remote command/script execution over SSH.
// Behavior spec: reverse-engineering/behavior-specs/execute-command.yaml
// v1 uses the system /usr/bin/ssh binary (no external dependency), which is
// present on every macOS install. Captures exit code, stdout, stderr, duration.

import Foundation

public struct SSHCommandResult: Codable, Sendable, Equatable {
    public var exitCode: Int
    public var stdout: String
    public var stderr: String
    public var durationSeconds: Double

    public init(exitCode: Int, stdout: String, stderr: String, durationSeconds: Double) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationSeconds = durationSeconds
    }
}

public enum SSHError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timeout
    case invalidHost(String)
}

public struct SSHHost: Sendable, Equatable {
    public var hostname: String   // user@host or host
    public var port: UInt16

    public init(hostname: String, port: UInt16 = 22) {
        self.hostname = hostname
        self.port = port
    }
}

public final class SSHTransport: @unchecked Sendable {
    /// Path to ssh binary; injectable for testing.
    let sshPath: String

    public init(sshPath: String = "/usr/bin/ssh") {
        self.sshPath = sshPath
    }

    /// Execute a command on one host. Batch mode (no interactive prompts).
    /// - Parameters:
    ///   - command: shell command string
    ///   - timeout: seconds before SIGKILL (default 120)
    ///   - runAsRoot: prefix with sudo (requires NOPASSWD sudo or root key)
    @discardableResult
    public func execute(
        _ command: String,
        on host: SSHHost,
        timeout: TimeInterval = 120,
        runAsRoot: Bool = false
    ) async throws -> SSHCommandResult {
        let remote = runAsRoot ? "sudo sh -c \(shellQuote(command))" : command
        let args = sshArgs(host: host, remote: remote)
        let start = Date()
        let result = try await runProcess(sshPath, args: args, timeout: timeout)
        let duration = Date().timeIntervalSince(start)
        return SSHCommandResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            durationSeconds: duration
        )
    }

    /// Execute a multi-line script: pipe the script body via stdin to `sh -s`.
    @discardableResult
    public func executeScript(
        _ script: String,
        on host: SSHHost,
        timeout: TimeInterval = 300,
        runAsRoot: Bool = false
    ) async throws -> SSHCommandResult {
        let remote = runAsRoot ? "sudo sh -s" : "sh -s"
        let args = sshArgs(host: host, remote: remote)
        let start = Date()
        let result = try await runProcess(sshPath, args: args, timeout: timeout, stdinData: Data(script.utf8))
        let duration = Date().timeIntervalSince(start)
        return SSHCommandResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            durationSeconds: duration
        )
    }

    private func sshArgs(host: SSHHost, remote: String) -> [String] {
        [
            "-p", String(host.port),
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            host.hostname,
            remote,
        ]
    }

    // MARK: - Process runner

    struct ProcessOutput {
        var exitCode: Int
        var stdout: String
        var stderr: String
    }

    func runProcess(_ path: String, args: [String], timeout: TimeInterval, stdinData: Data? = nil) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdinData {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
            try stdinPipe.fileHandleForWriting.close()
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        final class BufferState: @unchecked Sendable {
            private var stdoutData = Data()
            private var stderrData = Data()
            private let lock = NSLock()

            func appendStdout(_ data: Data) {
                lock.lock(); stdoutData.append(data); lock.unlock()
            }

            func appendStderr(_ data: Data) {
                lock.lock(); stderrData.append(data); lock.unlock()
            }

            /// Merge drain data and return both buffers. Call from a sync context.
            func drainAndRead(stdout extra: Data, stderr extraErr: Data) -> (String, String) {
                lock.lock()
                stdoutData.append(extra)
                stderrData.append(extraErr)
                let o = String(data: stdoutData, encoding: .utf8) ?? ""
                let e = String(data: stderrData, encoding: .utf8) ?? ""
                lock.unlock()
                return (o, e)
            }
        }
        let buffers = BufferState()

        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            buffers.appendStdout(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            buffers.appendStderr(data)
        }

        do {
            try process.run()
        } catch {
            throw SSHError.launchFailed(String(describing: error))
        }

        let terminated = await waitForExit(process, timeout: timeout)

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        // Drain remaining buffered output. All lock work happens inside a
        // detached synchronous task so no NSLock call occurs in async context.
        let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let drainTask = Task.detached(priority: .userInitiated) { () -> (String, String) in
            buffers.drainAndRead(stdout: remainingOut, stderr: remainingErr)
        }
        let (outStr, errStr) = await drainTask.value

        guard terminated else {
            process.terminate()
            throw SSHError.timeout
        }

        return ProcessOutput(
            exitCode: Int(process.terminationStatus),
            stdout: outStr,
            stderr: errStr
        )
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if process.isRunning == false { return true }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms poll
        }
        return !process.isRunning
    }

    func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
