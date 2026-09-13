// DeviceRegistry — SQLite-backed device, group, and task persistence.
// Implements the schema in packages/device-registry/Assets/schema.sql.

import Foundation
#if canImport(OpenDeskCoreSQLite)
#endif

public struct DeviceRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var hostname: String
    public var bonjourName: String?
    public var ips: [String]
    public var macAddress: String?
    public var osVersion: String?
    public var architecture: String?
    public var ardVersion: String?
    public var rfbAvailable: Bool
    public var sshAvailable: Bool
    public var authState: String?
    public var latencyMs: Double?
    public var online: Bool
    public var lastSeen: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        hostname: String,
        bonjourName: String? = nil,
        ips: [String] = [],
        macAddress: String? = nil,
        osVersion: String? = nil,
        architecture: String? = nil,
        ardVersion: String? = nil,
        rfbAvailable: Bool = false,
        sshAvailable: Bool = false,
        authState: String? = nil,
        latencyMs: Double? = nil,
        online: Bool = false,
        lastSeen: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.hostname = hostname
        self.bonjourName = bonjourName
        self.ips = ips
        self.macAddress = macAddress
        self.osVersion = osVersion
        self.architecture = architecture
        self.ardVersion = ardVersion
        self.rfbAvailable = rfbAvailable
        self.sshAvailable = sshAvailable
        self.authState = authState
        self.latencyMs = latencyMs
        self.online = online
        self.lastSeen = lastSeen
        self.createdAt = createdAt
    }
}

public struct TaskRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var type: String
    public var parametersJSON: String
    public var executionJSON: String
    public var idempotencyKey: String?
    public var status: String
    public var createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        type: String,
        parametersJSON: String = "{}",
        executionJSON: String = "{\"mode\":\"immediate\"}",
        idempotencyKey: String? = nil,
        status: String = "created",
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.parametersJSON = parametersJSON
        self.executionJSON = executionJSON
        self.idempotencyKey = idempotencyKey
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public struct TaskTargetRecord: Codable, Sendable, Equatable {
    public var taskID: UUID
    public var deviceID: UUID
    public var status: String
    public var resultJSON: String?
    public var error: String?

    public init(taskID: UUID, deviceID: UUID, status: String = "pending", resultJSON: String? = nil, error: String? = nil) {
        self.taskID = taskID
        self.deviceID = deviceID
        self.status = status
        self.resultJSON = resultJSON
        self.error = error
    }
}

public struct AuditEventRecord: Codable, Sendable, Equatable {
    public var id: Int64?
    public var userID: String?
    public var action: String
    public var target: String?
    public var payloadJSON: String?
    public var at: Date

    public init(id: Int64? = nil, userID: String? = nil, action: String, target: String? = nil, payloadJSON: String? = nil, at: Date = Date()) {
        self.id = id
        self.userID = userID
        self.action = action
        self.target = target
        self.payloadJSON = payloadJSON
        self.at = at
    }
}

// MARK: - Registry

public final class DeviceRegistry: @unchecked Sendable {
    private let db: SQLiteDatabase

    public init(db: SQLiteDatabase) throws {
        self.db = db
        let schemaURL = Bundle.module.url(forResource: "schema", withExtension: "sql")
        if let schemaURL, let sql = try? String(contentsOf: schemaURL, encoding: .utf8) {
            try db.exec(sql)
        }
    }

    /// Load the bundled schema SQL (public so CLI and tests can bootstrap explicitly).
    public static func bundledSchema() -> String? {
        guard let url = Bundle.module.url(forResource: "schema", withExtension: "sql"),
              let sql = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return sql
    }

    /// Initialize with an explicit schema string (used by tests and CLI bootstrap).
    public init(db: SQLiteDatabase, schema: String) throws {
        self.db = db
        try db.exec(schema)
    }

    // MARK: Devices

    public func upsertDevice(_ d: DeviceRecord) throws {
        let ipsJSON = try JSONEncoder().encode(d.ips)
        let ipsStr = String(data: ipsJSON, encoding: .utf8) ?? "[]"
        try db.run("""
            INSERT INTO devices (id, hostname, bonjour_name, ips, mac_address, os_version,
                                 architecture, ard_version, rfb_available, ssh_available,
                                 auth_state, latency_ms, online, last_seen, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            ON CONFLICT(id) DO UPDATE SET
                hostname=excluded.hostname, bonjour_name=excluded.bonjour_name,
                ips=excluded.ips, mac_address=excluded.mac_address,
                os_version=excluded.os_version, architecture=excluded.architecture,
                ard_version=excluded.ard_version, rfb_available=excluded.rfb_available,
                ssh_available=excluded.ssh_available, auth_state=excluded.auth_state,
                latency_ms=excluded.latency_ms, online=excluded.online,
                last_seen=excluded.last_seen,
                updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now')
            """,
            bindings: [
                .text(d.id.uuidString), .text(d.hostname),
                d.bonjourName.map { .text($0) } ?? .null,
                .text(ipsStr),
                d.macAddress.map { .text($0) } ?? .null,
                d.osVersion.map { .text($0) } ?? .null,
                d.architecture.map { .text($0) } ?? .null,
                d.ardVersion.map { .text($0) } ?? .null,
                .int(d.rfbAvailable ? 1 : 0), .int(d.sshAvailable ? 1 : 0),
                d.authState.map { .text($0) } ?? .null,
                d.latencyMs.map { .real($0) } ?? .null,
                .int(d.online ? 1 : 0),
                d.lastSeen.map { .text(ISO8601DateFormatter.string(from: $0, timeZone: .current)) } ?? .null,
            ])
    }

    public func devices() throws -> [DeviceRecord] {
        try db.query("SELECT * FROM devices ORDER BY hostname") { r in
            DeviceRecord(
                id: UUID(uuidString: r.text(0) ?? "") ?? UUID(),
                hostname: r.text(1) ?? "",
                bonjourName: r.text(2),
                ips: Self.decodeIPs(r.text(3)),
                macAddress: r.text(4),
                osVersion: r.text(5),
                architecture: r.text(6),
                ardVersion: r.text(7),
                rfbAvailable: r.bool(8),
                sshAvailable: r.bool(9),
                authState: r.text(10),
                latencyMs: r.isNull(11) ? nil : r.real(11),
                online: r.bool(12),
                lastSeen: r.text(13).flatMap { Self.parseDate($0) },
                createdAt: r.text(14).flatMap { Self.parseDate($0) } ?? Date()
            )
        }
    }

    public func device(id: UUID) throws -> DeviceRecord? {
        try db.query("SELECT * FROM devices WHERE id = ?", bindings: [.text(id.uuidString)]) { r in
            DeviceRecord(
                id: UUID(uuidString: r.text(0) ?? "") ?? UUID(),
                hostname: r.text(1) ?? "",
                bonjourName: r.text(2),
                ips: Self.decodeIPs(r.text(3)),
                macAddress: r.text(4),
                osVersion: r.text(5),
                architecture: r.text(6),
                ardVersion: r.text(7),
                rfbAvailable: r.bool(8),
                sshAvailable: r.bool(9),
                authState: r.text(10),
                latencyMs: r.isNull(11) ? nil : r.real(11),
                online: r.bool(12),
                lastSeen: r.text(13).flatMap { Self.parseDate($0) },
                createdAt: r.text(14).flatMap { Self.parseDate($0) } ?? Date()
            )
        }.first
    }

    /// Find a device by MAC address or hostname (discovery dedupe).
    public func findDevice(mac: String?, hostname: String) throws -> DeviceRecord? {
        if let mac {
            let byMac = try db.query("SELECT id FROM devices WHERE mac_address = ?", bindings: [.text(mac)]) { r in
                UUID(uuidString: r.text(0) ?? "")
            }.compactMap { $0 }
            if let first = byMac.first, let rec = try device(id: first) { return rec }
        }
        let byHost = try db.query("SELECT id FROM devices WHERE hostname = ? LIMIT 1", bindings: [.text(hostname)]) { r in
            UUID(uuidString: r.text(0) ?? "")
        }.compactMap { $0 }
        if let first = byHost.first, let rec = try device(id: first) { return rec }
        return nil
    }

    // MARK: Groups

    public func createGroup(name: String, parent: UUID? = nil) throws -> UUID {
        let id = UUID()
        try db.run("INSERT INTO groups (id, name, parent_id) VALUES (?, ?, ?)",
                   bindings: [.text(id.uuidString), .text(name), parent.map { .text($0.uuidString) } ?? .null])
        return id
    }

    public func addDevice(_ device: UUID, toGroup group: UUID) throws {
        try db.run("INSERT OR IGNORE INTO group_memberships (group_id, device_id) VALUES (?, ?)",
                   bindings: [.text(group.uuidString), .text(device.uuidString)])
    }

    public func groupMembers(group: UUID) throws -> [DeviceRecord] {
        try db.query("""
            SELECT d.* FROM devices d
            JOIN group_memberships gm ON gm.device_id = d.id
            WHERE gm.group_id = ? ORDER BY d.hostname
            """, bindings: [.text(group.uuidString)]) { r in
            DeviceRecord(
                id: UUID(uuidString: r.text(0) ?? "") ?? UUID(),
                hostname: r.text(1) ?? "",
                ips: DeviceRegistry.decodeIPs(r.text(3)),
                online: r.bool(12)
            )
        }
    }

    // MARK: Tasks

    public func insertTask(_ t: TaskRecord, targets: [UUID]) throws {
        try db.run("""
            INSERT INTO tasks (id, type, parameters_json, execution_json, idempotency_key, status, created_at)
            VALUES (?, ?, ?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            """,
            bindings: [
                .text(t.id.uuidString), .text(t.type), .text(t.parametersJSON),
                .text(t.executionJSON), t.idempotencyKey.map { .text($0) } ?? .null, .text(t.status),
            ])
        for deviceID in targets {
            try db.run("INSERT INTO task_targets (task_id, device_id, status) VALUES (?, ?, 'pending')",
                       bindings: [.text(t.id.uuidString), .text(deviceID.uuidString)])
        }
        try appendTaskEvent(taskID: t.id, event: "queued", deviceID: nil, payload: nil)
    }

    public func updateTaskStatus(taskID: UUID, status: String) throws {
        try db.run("UPDATE tasks SET status = ? WHERE id = ?", bindings: [.text(status), .text(taskID.uuidString)])
        try appendTaskEvent(taskID: taskID, event: status, deviceID: nil, payload: nil)
    }

    public func updateTaskTarget(taskID: UUID, deviceID: UUID, status: String, resultJSON: String?, error: String?) throws {
        try db.run("""
            UPDATE task_targets SET status = ?, result_json = ?, error = ?
            WHERE task_id = ? AND device_id = ?
            """,
            bindings: [
                .text(status), resultJSON.map { .text($0) } ?? .null, error.map { .text($0) } ?? .null,
                .text(taskID.uuidString), .text(deviceID.uuidString),
            ])
    }

    public func tasks() throws -> [TaskRecord] {
        try db.query("SELECT id, type, parameters_json, execution_json, idempotency_key, status, created_at, started_at, completed_at FROM tasks ORDER BY created_at DESC") { r in
            TaskRecord(
                id: UUID(uuidString: r.text(0) ?? "") ?? UUID(),
                type: r.text(1) ?? "",
                parametersJSON: r.text(2) ?? "{}",
                executionJSON: r.text(3) ?? "{}",
                idempotencyKey: r.text(4),
                status: r.text(5) ?? "created",
                createdAt: Self.parseDate(r.text(6) ?? "") ?? Date(),
                startedAt: r.text(7).flatMap(Self.parseDate),
                completedAt: r.text(8).flatMap(Self.parseDate)
            )
        }
    }

    public func taskTargets(taskID: UUID) throws -> [TaskTargetRecord] {
        try db.query("SELECT task_id, device_id, status, result_json, error FROM task_targets WHERE task_id = ?",
                     bindings: [.text(taskID.uuidString)]) { r in
            TaskTargetRecord(
                taskID: UUID(uuidString: r.text(0) ?? "") ?? UUID(),
                deviceID: UUID(uuidString: r.text(1) ?? "") ?? UUID(),
                status: r.text(2) ?? "pending",
                resultJSON: r.text(3),
                error: r.text(4)
            )
        }
    }

    public func appendTaskEvent(taskID: UUID, event: String, deviceID: UUID?, payload: String?) throws {
        try db.run("""
            INSERT INTO task_events (task_id, device_id, event, payload_json)
            VALUES (?, ?, ?, ?)
            """,
            bindings: [
                .text(taskID.uuidString),
                deviceID.map { .text($0.uuidString) } ?? .null,
                .text(event), payload.map { .text($0) } ?? .null,
            ])
    }

    // MARK: Audit

    public func appendAudit(_ e: AuditEventRecord) throws {
        try db.run("""
            INSERT INTO audit_events (user_id, action, target, payload_json, at)
            VALUES (?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'))
            """,
            bindings: [
                e.userID.map { .text($0) } ?? .null, .text(e.action),
                e.target.map { .text($0) } ?? .null, e.payloadJSON.map { .text($0) } ?? .null,
            ])
    }

    public func auditEvents(limit: Int = 100) throws -> [AuditEventRecord] {
        try db.query("SELECT id, user_id, action, target, payload_json, at FROM audit_events ORDER BY at DESC LIMIT ?",
                     bindings: [.int(Int64(limit))]) { r in
            AuditEventRecord(
                id: r.int(0), userID: r.text(1), action: r.text(2) ?? "",
                target: r.text(3), payloadJSON: r.text(4),
                at: Self.parseDate(r.text(5) ?? "") ?? Date()
            )
        }
    }

    // MARK: Helpers

    static func decodeIPs(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterNoFraction = ISO8601DateFormatter()

    static func parseDate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        return isoFormatterNoFraction.date(from: s)
    }

    static func formatDate(_ d: Date) -> String {
        isoFormatter.string(from: d)
    }
}
