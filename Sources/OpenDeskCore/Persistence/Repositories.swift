import Foundation

// MARK: - Repository protocols (ports per Plan 03 §5)

public protocol DeviceRepository {
    func upsert(_ device: Device) throws
    func load(_ id: DeviceID) throws -> Device?
    func all() throws -> [Device]
    func delete(_ id: DeviceID) throws
}

public protocol TaskRepository {
    func insert(_ task: TaskRecord) throws
    func load(_ id: TaskID) throws -> TaskRecord?
    func recordTransition(taskID: TaskID, from: TaskState, to: TaskState, detail: String?) throws
    func events(for taskID: TaskID) throws -> [TaskEvent]
}

public protocol AuditRepository {
    func record(_ event: AuditEvent) throws
    func recent(limit: Int) throws -> [AuditEvent]
}

public protocol SmartGroupRepository {
    func upsert(_ group: SmartGroup) throws
    func load(_ id: GroupID) throws -> SmartGroup?
    func all() throws -> [SmartGroup]
}

// MARK: - SQLite implementations

public final class SQLiteDeviceRepository: DeviceRepository, @unchecked Sendable {
    let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func upsert(_ device: Device) throws {
        try db.execute("""
        INSERT INTO devices (id, hostname, lifecycle, stable_signals, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            hostname = excluded.hostname,
            lifecycle = excluded.lifecycle,
            stable_signals = excluded.stable_signals,
            notes = excluded.notes,
            updated_at = excluded.updated_at
        """, bindings: [
            device.id.rawValue,
            device.hostname,
            device.lifecycle.rawValue,
            signalsJSON(device.stableSignals),
            device.notes,
            iso(device.createdAt),
            iso(device.updatedAt),
        ])
        try db.execute("DELETE FROM device_endpoints WHERE device_id = ?", bindings: [device.id.rawValue])
        for endpoint in device.endpoints {
            try db.execute(
                "INSERT OR REPLACE INTO device_endpoints (device_id, host, port, transport, last_seen) VALUES (?, ?, ?, ?, ?)",
                bindings: [device.id.rawValue, endpoint.host, String(endpoint.port), endpoint.transport.rawValue, endpoint.lastSeen.map(iso)]
            )
        }
    }

    public func load(_ id: DeviceID) throws -> Device? {
        let rows = try db.query("SELECT * FROM devices WHERE id = ?", bindings: [id.rawValue])
        guard let row = rows.first else { return nil }
        var device = Device(
            id: id,
            hostname: row.str("hostname"),
            lifecycle: DeviceLifecycle(rawValue: row.str("lifecycle")) ?? .unknown,
            notes: row.opt("notes"),
            createdAt: row.date("created_at") ?? Date(),
            updatedAt: row.date("updated_at") ?? Date()
        )
        device.stableSignals = decodeSignals(row.opt("stable_signals"))
        let endpointRows = try db.query("SELECT * FROM device_endpoints WHERE device_id = ?", bindings: [id.rawValue])
        device.endpoints = endpointRows.compactMap { r in
            guard let host = r.opt("host"),
                  let port = r.int("port"),
                  let transport = r.opt("transport").flatMap(EndpointTransport.init(rawValue:)) else { return nil }
            return Endpoint(host: host, port: port, transport: transport, lastSeen: r.date("last_seen"))
        }
        return device
    }

    public func all() throws -> [Device] {
        try db.stringColumn("SELECT id FROM devices").compactMap { try load(DeviceID(rawValue: $0)) }
    }

    public func delete(_ id: DeviceID) throws {
        try db.execute("DELETE FROM devices WHERE id = ?", bindings: [id.rawValue])
    }
}

public final class SQLiteTaskRepository: TaskRepository, @unchecked Sendable {
    let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func insert(_ task: TaskRecord) throws {
        do {
            try db.execute("""
            INSERT INTO tasks (id, type, state, target_selector, parameters, idempotency_key, correlation_id, deadline, retry_policy, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, bindings: [
                task.id.rawValue, task.type, task.state.rawValue,
                task.targetSelectorJSON, task.parametersJSON,
                task.idempotencyKey, task.correlationID,
                task.deadline.map(iso), task.retryPolicyJSON,
                iso(task.createdAt),
            ])
        } catch let failure as PersistenceError {
            // Duplicate idempotency key → UNIQUE constraint surfaced by the
            // wrapped query error (message check; execution must not repeat).
            if case .queryFailed(let message) = failure,
               message.contains("UNIQUE constraint failed"), message.contains("idempotency_key") {
                throw PersistenceError.duplicateIdempotencyKey
            }
            throw failure
        } catch {
            // UNIQUE constraint on idempotency_key → duplicate execution prevention.
            throw PersistenceError.duplicateIdempotencyKey
        }
    }

    public func load(_ id: TaskID) throws -> TaskRecord? {
        let rows = try db.query("SELECT * FROM tasks WHERE id = ?", bindings: [id.rawValue])
        guard let row = rows.first else { return nil }
        return TaskRecord(
            id: id,
            type: row.str("type"),
            state: TaskState(rawValue: row.str("state")) ?? .created,
            targetSelectorJSON: row.opt("target_selector"),
            parametersJSON: row.opt("parameters"),
            idempotencyKey: row.opt("idempotency_key"),
            correlationID: row.opt("correlation_id"),
            deadline: row.date("deadline"),
            retryPolicyJSON: row.opt("retry_policy"),
            createdAt: row.date("created_at") ?? Date()
        )
    }

    public func recordTransition(taskID: TaskID, from: TaskState, to: TaskState, detail: String?) throws {
        try db.transaction {
            let rows = try db.queryInTransaction("SELECT state FROM tasks WHERE id = ?", bindings: [taskID.rawValue])
            guard let current = rows.first?.str("state") else {
                throw PersistenceError.queryFailed("task \(taskID) not found")
            }
            guard let currentState = TaskState(rawValue: current) else {
                throw PersistenceError.queryFailed("unknown state \(current)")
            }
            guard !currentState.isTerminal else {
                throw PersistenceError.terminalStateImmutable
            }
            try db.executeInTransaction("UPDATE tasks SET state = ? WHERE id = ?", bindings: [to.rawValue, taskID.rawValue])
            try db.executeInTransaction(
                "INSERT INTO task_events (task_id, from_state, to_state, detail) VALUES (?, ?, ?, ?)",
                bindings: [taskID.rawValue, from.rawValue, to.rawValue, detail]
            )
        }
    }

    public func events(for taskID: TaskID) throws -> [TaskEvent] {
        let rows = try db.query("SELECT from_state, to_state, detail, recorded_at FROM task_events WHERE task_id = ? ORDER BY id", bindings: [taskID.rawValue])
        return rows.compactMap { row in
            guard let from = row.opt("from_state").flatMap(TaskState.init(rawValue:)),
                  let to = row.opt("to_state").flatMap(TaskState.init(rawValue:)) else { return nil }
            return TaskEvent(taskID: taskID, fromState: from, toState: to, detail: row.opt("detail"), recordedAt: row.date("recorded_at") ?? Date())
        }
    }
}

public final class SQLiteAuditRepository: AuditRepository, @unchecked Sendable {
    let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func record(_ event: AuditEvent) throws {
        try db.execute("""
        INSERT INTO audit_events (actor, action, targets, parameters, result, correlation_id)
        VALUES (?, ?, ?, ?, ?, ?)
        """, bindings: [
            event.actor, event.action, event.targets.joined(separator: ","),
            event.parametersJSON, event.result.rawValue, event.correlationID,
        ])
    }

    public func recent(limit: Int) throws -> [AuditEvent] {
        let rows = try db.query("SELECT actor, action, targets, parameters, result, correlation_id, recorded_at FROM audit_events ORDER BY id DESC LIMIT \(max(1, limit))")
        return rows.compactMap { row in
            guard let action = row.opt("action"),
                  let result = row.opt("result").flatMap(AuditEvent.AuditResult.init(rawValue:)) else { return nil }
            let targets = row.str("targets").isEmpty ? [] : row.str("targets").components(separatedBy: ",")
            var params: [String: String] = [:]
            if let json = row.opt("parameters"), let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                params = decoded
            }
            return AuditEvent(
                actor: row.str("actor"),
                action: action,
                targets: targets,
                parameters: params,
                result: result,
                correlationID: row.opt("correlation_id"),
                recordedAt: row.date("recorded_at") ?? Date()
            )
        }
    }
}

public final class SQLiteSmartGroupRepository: SmartGroupRepository, @unchecked Sendable {
    let db: SQLiteDatabase
    public init(db: SQLiteDatabase) { self.db = db }

    public func upsert(_ group: SmartGroup) throws {
        let data = try JSONEncoder().encode(group.predicate)
        try db.execute("""
        INSERT INTO smart_groups (id, name, predicate) VALUES (?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET name = excluded.name, predicate = excluded.predicate
        """, bindings: [group.id.rawValue, group.name, String(data: data, encoding: .utf8)])
    }

    public func load(_ id: GroupID) throws -> SmartGroup? {
        let rows = try db.query("SELECT id, name, predicate FROM smart_groups WHERE id = ?", bindings: [id.rawValue])
        guard let row = rows.first,
              let name = row.opt("name"),
              let predicateJSON = row.opt("predicate"),
              let data = predicateJSON.data(using: .utf8),
              let predicate = try? JSONDecoder().decode(SmartGroupPredicate.self, from: data) else { return nil }
        return SmartGroup(id: id, name: name, predicate: predicate)
    }

    public func all() throws -> [SmartGroup] {
        try db.stringColumn("SELECT id FROM smart_groups").compactMap { try load(GroupID(rawValue: $0)) }
    }
}

// MARK: - Helpers

func iso(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func isoDate(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
}

func signalsJSON(_ signals: [StableSignal]) -> String {
    signals.map {
        switch $0 {
        case .hardwareMAC(let v): return "mac:\(v)"
        case .machineUUID(let v): return "uuid:\(v)"
        case .sshHostKey(let v): return "ssh:\(v)"
        case .hostname(let v): return "host:\(v)"
        case .subnetCorrelation(let v): return "subnet:\(v)"
        }
    }
    .joined(separator: "|")
}

func decodeSignals(_ json: String?) -> [StableSignal] {
    guard let json, !json.isEmpty else { return [] }
    return json.components(separatedBy: "|").compactMap { token in
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "mac": return .hardwareMAC(parts[1])
        case "uuid": return .machineUUID(parts[1])
        case "ssh": return .sshHostKey(parts[1])
        case "host": return .hostname(parts[1])
        case "subnet": return .subnetCorrelation(parts[1])
        default: return nil
        }
    }
}
