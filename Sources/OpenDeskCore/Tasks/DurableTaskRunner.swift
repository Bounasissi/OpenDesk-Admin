import Foundation

// MARK: - Remote transport seam (Plan 08; SSH adapter in Plan 07 layer)

public struct ExecOutcome: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }
}

public protocol RemoteTransport {
    func execute(device: Device, command: String) -> ExecOutcome
}

// MARK: - Durable task runner (Plan 08 §2/§3 + A1.1)

/// Durable task execution over the canonical database.
/// Behaviors (Plan 08 A1.1): offline target waits (WAITING_FOR_TARGET),
/// reconnect executes, restart survives, per-target independence,
/// duplicate execution prevented (idempotency key), cancellation persisted.
public final class DurableTaskRunner: @unchecked Sendable {
    let db: SQLiteDatabase
    let tasks: SQLiteTaskRepository
    let devices: SQLiteDeviceRepository
    let transport: RemoteTransport

    public init(db: SQLiteDatabase, transport: RemoteTransport) {
        self.db = db
        self.tasks = SQLiteTaskRepository(db: db)
        self.devices = SQLiteDeviceRepository(db: db)
        self.transport = transport
    }

    @discardableResult
    public func submit(
        type: String,
        deviceIDs: [DeviceID],
        idempotencyKey: String? = nil,
        parameters: String? = nil,
        correlationID: String? = nil
    ) throws -> TaskRecord {
        let task = TaskRecord(
            type: type,
            state: .queued,
            targetSelectorJSON: nil,
            parametersJSON: parameters,
            idempotencyKey: idempotencyKey,
            correlationID: correlationID
        )
        try tasks.insert(task)
        for deviceID in deviceIDs {
            try db.execute(
                "INSERT OR REPLACE INTO task_targets (task_id, device_id, state) VALUES (?, ?, 'pending')",
                bindings: [task.id.rawValue, deviceID.rawValue]
            )
        }
        try tasks.recordTransition(taskID: task.id, from: .queued, to: .queued, detail: "queued with \(deviceIDs.count) target(s)")
        return task
    }

    /// One dispatch cycle: move QUEUED/WAITING_FOR_TARGET tasks whose targets
    /// are online to RUNNING and execute per-target. Returns executed tasks.
    @discardableResult
    public func dispatchPending() throws -> [TaskRecord] {
        let pendingIDs = try db.stringColumn(
            "SELECT id FROM tasks WHERE state IN ('queued','waitingForTarget') ORDER BY created_at"
        )
        var executed: [TaskRecord] = []
        for rawID in pendingIDs {
            let taskID = TaskID(rawValue: rawID)
            let targets = try db.query("SELECT device_id, state FROM task_targets WHERE task_id = ?", bindings: [rawID])
            guard !targets.isEmpty else { continue }
            let pendingTargets = targets.filter { $0.opt("state") == "pending" }
            guard !pendingTargets.isEmpty else {
                // All targets resolved → finalize if still running/waiting.
                try finalizeIfComplete(taskID: taskID)
                continue
            }
            var anyOnline = false
            for target in pendingTargets {
                guard let deviceIDRaw = target.opt("device_id") else { continue }
                let device = try devices.load(DeviceID(rawValue: deviceIDRaw))
                guard let device, device.lifecycle != .retired else {
                    try markTarget(taskID: taskID, deviceIDRaw: deviceIDRaw, state: "failed", detail: "target retired/unknown")
                    continue
                }
                if device.lifecycle != .online {
                    // Offline → WAITING_FOR_TARGET (Addendum §14: not failed).
                    try tasks.recordTransition(taskID: taskID, from: try currentState(taskID: taskID), to: .waitingForTarget, detail: "target offline")
                    continue
                }
                anyOnline = true
                let command = commandFor(task: try tasks.load(taskID), device: device)
                try tasks.recordTransition(taskID: taskID, from: .waitingForTarget, to: .running, detail: "dispatching")
                let outcome = transport.execute(device: device, command: command)
                try markTarget(
                    taskID: taskID, deviceIDRaw: deviceIDRaw,
                    state: outcome.succeeded ? "success" : "failed",
                    detail: "exit \(outcome.exitCode)"
                )
            }
            try finalizeIfComplete(taskID: taskID)
            if anyOnline, let task = try tasks.load(taskID) {
                executed.append(task)
            }
        }
        return executed
    }

    /// Restart survival: non-terminal tasks resume from persisted state.
    public func resumeAfterRestart() throws -> [TaskRecord] {
        let states = ["created", "queued", "waitingForTarget", "dispatched", "running", "retryWait"]
        let ids = try db.stringColumn("SELECT id FROM tasks WHERE state IN (\(states.map { "'\($0)'" }.joined(separator: ",")))")
        return try ids.compactMap { try tasks.load(TaskID(rawValue: $0)) }
    }

    /// Cancellation is persisted (Plan 08 A1.1).
    public func cancel(taskID: TaskID) throws {
        guard let task = try tasks.load(taskID) else {
            throw PersistenceError.queryFailed("task \(taskID) not found")
        }
        guard !task.state.isTerminal else { return }
        let pendingTargets = try db.query("SELECT device_id FROM task_targets WHERE task_id = ? AND state = 'pending'", bindings: [taskID.rawValue])
        for row in pendingTargets {
            if let deviceID = row.opt("device_id") {
                try markTarget(taskID: taskID, deviceIDRaw: deviceID, state: "cancelled", detail: "cancelled before dispatch")
            }
        }
        try tasks.recordTransition(taskID: taskID, from: task.state, to: .cancelled, detail: "cancelled by user")
    }

    // MARK: Internals

    /// Test/exposure helper: load a task record (thin wrapper over the repo).
    public func tasksLoad(_ taskID: TaskID) throws -> TaskRecord? {
        try tasks.load(taskID)
    }

    func currentState(taskID: TaskID) throws -> TaskState {
        let loaded = try tasks.load(taskID)
        return loaded?.state ?? .created
    }

    public func commandFor(task: TaskRecord?, device: Device) -> String {
        // v1: exec.command carries {"command": "..."}; the agent path lands in Plan 11.
        if let task, let data = task.parametersJSON?.data(using: .utf8),
           let object = try? JSONDecoder().decode([String: String].self, from: data),
           let command = object["command"] {
            return command
        }
        return "true"
    }

    func markTarget(taskID: TaskID, deviceIDRaw: String, state: String, detail: String) throws {
        try db.execute(
            "UPDATE task_targets SET state = ?, result = ?, finished_at = ? WHERE task_id = ? AND device_id = ?",
            bindings: [state, detail, iso(Date()), taskID.rawValue, deviceIDRaw]
        )
    }

    func finalizeIfComplete(taskID: TaskID) throws {
        let remaining = try db.query("SELECT state FROM task_targets WHERE task_id = ?", bindings: [taskID.rawValue])
        let targetStates = remaining.compactMap { $0.opt("state") }
        guard !targetStates.isEmpty else { return }
        let current = try currentState(taskID: taskID)
        guard !current.isTerminal else { return }
        if targetStates.allSatisfy({ $0 == "success" }) {
            try tasks.recordTransition(taskID: taskID, from: current, to: .success, detail: "all targets succeeded")
        } else if targetStates.allSatisfy({ ["failed", "cancelled"].contains($0) }) {
            try tasks.recordTransition(taskID: taskID, from: current, to: .failed, detail: "all targets failed/cancelled")
        } else if targetStates.contains("failed") || targetStates.contains("cancelled") {
            // Mixed outcome: no targets remain pending and at least one failed
            // → the task record finalizes as failed (partial fleet failure
            // survives in per-target results; retries create new work —
            // Plan 08 §6 retry classifications).
            try tasks.recordTransition(taskID: taskID, from: current, to: .failed, detail: "completed with per-target failures")
        }
    }
}

// MARK: - Schedules in the canonical DB (Plan 08 A1.2)

public enum ScheduleKindDB: String, Codable, Sendable, CaseIterable {
    case now
    case once
    case rrule
    case onReconnect
    case onPredicate
}

public struct ScheduleDefinitionDB: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var taskTemplateID: UUID?
    public var kind: ScheduleKindDB
    public var rrule: String?
    public var runAt: Date?
    public var predicate: String?
    public var enabled: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        taskTemplateID: UUID? = nil,
        kind: ScheduleKindDB,
        rrule: String? = nil,
        runAt: Date? = nil,
        predicate: String? = nil,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskTemplateID = taskTemplateID
        self.kind = kind
        self.rrule = rrule
        self.runAt = runAt
        self.predicate = predicate
        self.enabled = enabled
        self.createdAt = createdAt
    }

    /// Legacy JSON schedules (TaskStore-era payload) import for one release
    /// cycle (Plan 08 A1.2 migration path).
    public static func fromLegacyJSON(_ json: String) throws -> ScheduleDefinitionDB {
        struct Legacy: Decodable {
            struct Trigger: Decodable {
                struct Daily: Decodable { let hour: Int; let minute: Int }
                let daily: Daily?
                let interval: [String: Int]?
            }
            let name: String?
            let taskName: String?
            let trigger: Trigger?
        }
        guard let data = json.data(using: .utf8),
              let legacy = try? JSONDecoder().decode(Legacy.self, from: data) else {
            throw ConfigurationError.invalidValue(key: "legacySchedule", reason: "unparseable")
        }
        var schedule = ScheduleDefinitionDB(kind: .once)
        if let daily = legacy.trigger?.daily {
            schedule.predicate = "legacy.daily.\(daily.hour):\(daily.minute)"
        }
        return schedule
    }
}

public final class SQLiteScheduleRepository: @unchecked Sendable {
    let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func upsert(_ schedule: ScheduleDefinitionDB) throws {
        try db.execute("""
        INSERT INTO schedules (id, task_id, task_template_id, kind, rrule, run_at, predicate, enabled, created_at)
        VALUES (?, NULL, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            task_template_id = excluded.task_template_id,
            kind = excluded.kind,
            rrule = excluded.rrule,
            run_at = excluded.run_at,
            predicate = excluded.predicate,
            enabled = excluded.enabled
        """, bindings: [
            schedule.id.uuidString,
            schedule.taskTemplateID?.uuidString,
            schedule.kind.rawValue,
            schedule.rrule,
            schedule.runAt.map(iso),
            schedule.predicate,
            schedule.enabled ? "1" : "0",
            iso(schedule.createdAt),
        ])
    }

    public func load(_ id: UUID) throws -> ScheduleDefinitionDB? {
        let rows = try db.query("SELECT * FROM schedules WHERE id = ?", bindings: [id.uuidString])
        guard let row = rows.first,
              let kind = row.opt("kind").flatMap(ScheduleKindDB.init(rawValue:)) else { return nil }
        return ScheduleDefinitionDB(
            id: id,
            taskTemplateID: row.opt("task_template_id").flatMap(UUID.init(uuidString:)),
            kind: kind,
            rrule: row.opt("rrule"),
            runAt: row.date("run_at"),
            predicate: row.opt("predicate"),
            enabled: row.opt("enabled") == "0" ? false : true,
            createdAt: row.date("created_at") ?? Date()
        )
    }

    public func all() throws -> [ScheduleDefinitionDB] {
        try db.stringColumn("SELECT id FROM schedules").compactMap { UUID(uuidString: $0) }.compactMap { try load($0) }
    }
}
