import Foundation

// MARK: - Stable opaque identifiers (Plan 03 §3, DATA_MODEL §3)

public struct DeviceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init() { self.rawValue = UUID().uuidString }
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct GroupID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init() { self.rawValue = UUID().uuidString }
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct TaskID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init() { self.rawValue = UUID().uuidString }
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct SessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init() { self.rawValue = UUID().uuidString }
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct CredentialID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init() { self.rawValue = UUID().uuidString }
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

public struct InventorySnapshotID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init() { self.rawValue = UUID().uuidString }
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

// MARK: - Device (Plan 04 §2.5 lifecycle states)

public enum DeviceLifecycle: String, Codable, Sendable, CaseIterable {
    case unknown
    case online
    case degraded
    case offline
    case retired
}

public enum EndpointTransport: String, Codable, Sendable, CaseIterable {
    case rfb
    case ssh
    case ardReporting
    case agent
}

/// A routable address for a device. Devices own many endpoints; identity
/// reconciliation (Plan 04) merges endpoints into one stable device.
public struct Endpoint: Hashable, Codable, Sendable {
    public var host: String
    public var port: Int
    public var transport: EndpointTransport
    public var lastSeen: Date?

    public init(host: String, port: Int, transport: EndpointTransport, lastSeen: Date? = nil) {
        self.host = host
        self.port = port
        self.transport = transport
        self.lastSeen = lastSeen
    }
}

public enum StableSignal: Hashable, Codable, Sendable {
    case hardwareMAC(String)
    case machineUUID(String)
    case sshHostKey(String)
    case hostname(String)
    case subnetCorrelation(String)
}

/// The domain device. Transport-specific objects (Host, RFBClient, …) must not
/// leak into UI state; UI renders this model (Plan 03 §2/§5).
public struct Device: Hashable, Codable, Sendable, Identifiable {
    public var id: DeviceID
    public var hostname: String
    public var lifecycle: DeviceLifecycle
    public var stableSignals: [StableSignal]
    public var endpoints: [Endpoint]
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: DeviceID = DeviceID(),
        hostname: String,
        lifecycle: DeviceLifecycle = .unknown,
        stableSignals: [StableSignal] = [],
        endpoints: [Endpoint] = [],
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.hostname = hostname
        self.lifecycle = lifecycle
        self.stableSignals = stableSignals
        self.endpoints = endpoints
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Task (TASK_MODEL.md state machine)

public enum TaskState: String, Codable, Sendable, CaseIterable {
    case created
    case queued
    case waitingForTarget
    case dispatched
    case running
    case retryWait
    case success
    case failed
    case cancelled

    public var isTerminal: Bool { self == .success || self == .failed || self == .cancelled }
}

/// A durable task record (Plan 08 A1.1 metadata checklist encoded in schema).
public struct TaskRecord: Hashable, Codable, Sendable, Identifiable {
    public var id: TaskID
    public var type: String
    public var state: TaskState
    public var targetSelectorJSON: String?
    public var parametersJSON: String?
    public var idempotencyKey: String?
    public var correlationID: String?
    public var deadline: Date?
    public var retryPolicyJSON: String?
    public var createdAt: Date

    public init(
        id: TaskID = TaskID(),
        type: String,
        state: TaskState = .created,
        targetSelectorJSON: String? = nil,
        parametersJSON: String? = nil,
        idempotencyKey: String? = nil,
        correlationID: String? = nil,
        deadline: Date? = nil,
        retryPolicyJSON: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.state = state
        self.targetSelectorJSON = targetSelectorJSON
        self.parametersJSON = parametersJSON
        self.idempotencyKey = idempotencyKey
        self.correlationID = correlationID
        self.deadline = deadline
        self.retryPolicyJSON = retryPolicyJSON
        self.createdAt = createdAt
    }
}

public struct TaskEvent: Hashable, Codable, Sendable {
    public var taskID: TaskID
    public var fromState: TaskState
    public var toState: TaskState
    public var detail: String?
    public var recordedAt: Date

    public init(taskID: TaskID, fromState: TaskState, toState: TaskState, detail: String? = nil, recordedAt: Date = Date()) {
        self.taskID = taskID
        self.fromState = fromState
        self.toState = toState
        self.detail = detail
        self.recordedAt = recordedAt
    }
}

// MARK: - Smart groups (Plan 04 A1.3: definitions are source of truth)

public struct SmartGroupClause: Hashable, Codable, Sendable {
    public enum FieldOperation: String, Codable, Sendable { case eq, neq, lt, gt, contains }
    public var field: String
    public var op: FieldOperation
    public var value: String

    public init(field: String, op: FieldOperation, value: String) {
        self.field = field
        self.op = op
        self.value = value
    }
}

public struct SmartGroupPredicate: Hashable, Codable, Sendable {
    public enum BooleanOperator: String, Codable, Sendable { case and, or }
    public var op: BooleanOperator
    public var clauses: [SmartGroupClause]

    public init(op: BooleanOperator, clauses: [SmartGroupClause]) {
        self.op = op
        self.clauses = clauses
    }
}

public struct SmartGroup: Hashable, Codable, Sendable, Identifiable {
    public var id: GroupID
    public var name: String
    public var predicate: SmartGroupPredicate
    public var createdAt: Date

    public init(id: GroupID = GroupID(), name: String, predicate: SmartGroupPredicate, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.predicate = predicate
        self.createdAt = createdAt
    }
}

// MARK: - Audit events (Plan 05 A1.3 field contract)

public struct AuditEvent: Hashable, Codable, Sendable {
    public enum AuditResult: String, Codable, Sendable { case success, failure, denied }

    public var actor: String
    public var action: String
    public var targets: [String]
    public var parameters: [String: String]
    public var result: AuditResult
    public var correlationID: String?
    public var recordedAt: Date

    public init(
        actor: String,
        action: String,
        targets: [String],
        parameters: [String: String] = [:],
        result: AuditResult,
        correlationID: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.actor = actor
        self.action = action
        self.targets = targets
        self.parameters = parameters
        self.result = result
        self.correlationID = correlationID
        self.recordedAt = recordedAt
    }

    var parametersJSON: String {
        guard let data = try? JSONEncoder().encode(parameters) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
