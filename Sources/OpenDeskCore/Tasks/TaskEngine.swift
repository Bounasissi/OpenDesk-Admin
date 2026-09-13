import Foundation

/// A saved, versioned task definition (ARD "Saved Tasks" equivalent).
public struct TaskDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var timeoutSeconds: Int
    public var targetGroups: [String]
    public var version: Int

    public init(
        id: UUID = UUID(),
        name: String,
        command: String,
        timeoutSeconds: Int = 30,
        targetGroups: [String] = [],
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.timeoutSeconds = timeoutSeconds
        self.targetGroups = targetGroups
        self.version = version
    }
}

/// Result of running a task on a single host.
public struct TaskResult: Codable, Sendable {
    public var taskId: UUID
    public var host: String
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var errorDescription: String?
    public var durationMs: Int
    public var startedAt: Date

    public init(
        taskId: UUID,
        host: String,
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        errorDescription: String? = nil,
        durationMs: Int,
        startedAt: Date = Date()
    ) {
        self.taskId = taskId
        self.host = host
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.errorDescription = errorDescription
        self.durationMs = durationMs
        self.startedAt = startedAt
    }

    public var succeeded: Bool { exitCode == 0 && errorDescription == nil }
}

/// Built-in power management tasks (ARD Sleep/Restart/Shutdown equivalents).
public enum PowerTask {
    public static let sleep = "pmset sleepnow"
    public static let restart = "osascript -e 'tell application \"System Events\" to restart'"
    public static let shutdown = "osascript -e 'tell application \"System Events\" to shut down'"
}

/// Runs task definitions across the host roster and aggregates results.
public final class TaskEngine: @unchecked Sendable {
    public typealias TransportFactory = (Host) -> CommandTransport

    private let transportFactory: TransportFactory

    public init(transportFactory: TransportFactory? = nil) {
        self.transportFactory = transportFactory ?? { SSHTransport(host: $0) }
    }

    /// Run a command on one host.
    public func runOnHost(_ command: String, host: Host, taskId: UUID = UUID(), timeoutSeconds: Int = 30) -> TaskResult {
        let transport = transportFactory(host)
        let start = Date()
        do {
            let output = try transport.run(command: command, timeoutSeconds: timeoutSeconds)
            return TaskResult(
                taskId: taskId,
                host: host.hostname,
                exitCode: output.exitCode,
                stdout: output.stdout,
                stderr: output.stderr,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                startedAt: start
            )
        } catch let error as SSHTransport.TransportError {
            return TaskResult(
                taskId: taskId,
                host: host.hostname,
                exitCode: -1,
                errorDescription: describe(error),
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                startedAt: start
            )
        } catch {
            return TaskResult(
                taskId: taskId,
                host: host.hostname,
                exitCode: -1,
                errorDescription: error.localizedDescription,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                startedAt: start
            )
        }
    }

    /// Run a command across many hosts with bounded parallelism.
    /// Results are returned in the same order as the input hosts.
    public func runAcrossHosts(_ command: String, hosts: [Host], taskId: UUID = UUID(), timeoutSeconds: Int = 30, maxConcurrency: Int = 8) -> [TaskResult] {
        guard !hosts.isEmpty else { return [] }
        let boundedConcurrency = Swift.max(1, maxConcurrency)
        var results = [TaskResult?](repeating: nil, count: hosts.count)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: boundedConcurrency)
        let lock = NSLock()

        for (index, host) in hosts.enumerated() {
            group.enter()
            semaphore.wait()
            DispatchQueue.global().async {
                defer {
                    semaphore.signal()
                    group.leave()
                }
                let result = self.runOnHost(command, host: host, taskId: taskId, timeoutSeconds: timeoutSeconds)
                lock.lock()
                results[index] = result
                lock.unlock()
            }
        }
        group.wait()
        return results.compactMap { $0 }
    }

    private func describe(_ error: SSHTransport.TransportError) -> String {
        switch error {
        case .hostUnreachable(let host): return "host unreachable: \(host)"
        case .authenticationFailed(let host): return "authentication failed: \(host)"
        case .commandFailed(_, let stderr): return "command failed: \(stderr)"
        case .binaryMissing(let path): return "ssh binary missing at \(path)"
        }
    }
}
