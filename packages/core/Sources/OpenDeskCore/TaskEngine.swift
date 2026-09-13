// TaskEngine — universal task object, queue, state machine, per-target results.
// Behavior spec: reverse-engineering/state-machines/task-lifecycle.md
// Invariants:
//   1. Every state transition writes a task_events row.
//   2. Per-target results are independent.
//   3. idempotency_key prevents duplicate execution.
//   4. Terminal states are immutable.
//   5. Admin-initiated tasks write an audit_events row.

import Foundation

public final class TaskEngine: @unchecked Sendable {
    let registry: DeviceRegistry
    let ssh: SSHTransport

    public init(registry: DeviceRegistry, ssh: SSHTransport) {
        self.registry = registry
        self.ssh = ssh
    }

    // MARK: - Task creation

    /// Create and queue a task. Returns the task record.
    @discardableResult
    public func submit(
        type: ODTask.TaskType,
        targets deviceIDs: [UUID],
        parameters: [String: String] = [:],
        executionMode: ODTask.ExecutionMode = .immediate,
        idempotencyKey: String? = nil,
        actor: String = "local-admin"
    ) throws -> TaskRecord {
        let paramsJSON = try JSONEncoder().encode(parameters)
        let execJSON = try JSONEncoder().encode(ODTask.Execution(mode: executionMode))
        let record = TaskRecord(
            type: type.rawValue,
            parametersJSON: String(data: paramsJSON, encoding: .utf8) ?? "{}",
            executionJSON: String(data: execJSON, encoding: .utf8) ?? "{}",
            idempotencyKey: idempotencyKey,
            status: "queued"
        )
        try registry.insertTask(record, targets: deviceIDs)
        try registry.appendAudit(AuditEventRecord(
            action: "task.submit",
            target: record.id.uuidString,
            payloadJSON: "{\"type\":\"\(type.rawValue)\",\"targets\":\(deviceIDs.count)}"
        ))
        return record
    }

    // MARK: - Execution

    /// Execute a task against its targets. Per-target results are independent.
    @discardableResult
    public func execute(taskID: UUID) async throws -> [TaskTargetRecord] {
        let task = try registry.tasks().first { $0.id == taskID }
        guard let task else { throw OpenDeskError.taskInvalid("task \(taskID) not found") }
        guard !Self.isTerminal(task.status) else { return try registry.taskTargets(taskID: taskID) }

        let targets = try registry.taskTargets(taskID: taskID)
        try registry.updateTaskStatus(taskID: taskID, status: "running")

        let params = Self.decodeParameters(task.parametersJSON)
        let command = params["command"] ?? ""

        await withTaskGroup(of: TaskTargetRecord.self) { group in
            for target in targets {
                group.addTask {
                    await self.runOnTarget(task: task, target: target, command: command)
                }
            }
            for await updated in group {
                try? registry.updateTaskTarget(
                    taskID: taskID, deviceID: updated.deviceID,
                    status: updated.status, resultJSON: updated.resultJSON, error: updated.error
                )
            }
        }

        // Aggregate: any failure -> failed; else success.
        let final = try registry.taskTargets(taskID: taskID)
        let allDone = final.allSatisfy { $0.status == "success" || $0.status == "failed" || $0.status == "skipped" }
        if allDone {
            let anyFailed = final.contains { $0.status == "failed" }
            try registry.updateTaskStatus(taskID: taskID, status: anyFailed ? "failed" : "success")
        }
        return final
    }

    private func runOnTarget(task: TaskRecord, target: TaskTargetRecord, command: String) async -> TaskTargetRecord {
        var updated = target
        updated.status = "running"
        try? registry.appendTaskEvent(taskID: task.id, event: "started", deviceID: target.deviceID, payload: nil)

        guard let device = try? registry.device(id: target.deviceID) else {
            updated.status = "failed"
            updated.error = "device not found in registry"
            return updated
        }

        // Resolve host: first IP or hostname.
        let hostString = device.ips.first ?? device.hostname
        guard !hostString.isEmpty else {
            updated.status = "failed"
            updated.error = "no reachable address for device"
            return updated
        }

        let host = SSHHost(hostname: hostString)
        do {
            let result = try await ssh.execute(command, on: host)
            let resultPayload: [String: Any] = [
                "exit_code": result.exitCode,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "duration_seconds": result.durationSeconds,
            ]
            let resultJSON = try JSONSerialization.data(withJSONObject: resultPayload)
            updated.status = result.exitCode == 0 ? "success" : "failed"
            updated.resultJSON = String(data: resultJSON, encoding: .utf8)
            updated.error = result.exitCode == 0 ? nil : result.stderr
            try? registry.appendTaskEvent(
                taskID: task.id, event: updated.status, deviceID: target.deviceID,
                payload: "{\"exit_code\":\(result.exitCode)}"
            )
        } catch SSHError.timeout {
            updated.status = "failed"
            updated.error = "timeout"
            try? registry.appendTaskEvent(taskID: task.id, event: "failed", deviceID: target.deviceID, payload: "{\"error\":\"timeout\"}")
        } catch {
            updated.status = "failed"
            updated.error = String(describing: error)
            try? registry.appendTaskEvent(taskID: task.id, event: "failed", deviceID: target.deviceID, payload: nil)
        }
        return updated
    }

    // MARK: - Helpers

    static func decodeParameters(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func isTerminal(_ status: String) -> Bool {
        ["success", "failed", "cancelled"].contains(status)
    }
}
