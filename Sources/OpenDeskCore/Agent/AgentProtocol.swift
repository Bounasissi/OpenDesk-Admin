import Foundation

// MARK: - Agent protocol (Plan 11 §6 — versioned from day one)

public enum AgentCapability: String, Codable, Sendable, CaseIterable {
    case inventory
    case files
    case packages
    case power
    case clipboard
    case screenCapture
    case notifications
    case heartbeat
}

/// Agent → admin hello: protocol version, agent version, declared capabilities.
public struct AgentHello: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var agentVersion: String
    public var capabilities: [AgentCapability]

    public init(protocolVersion: Int, agentVersion: String, capabilities: [AgentCapability]) {
        self.protocolVersion = protocolVersion
        self.agentVersion = agentVersion
        self.capabilities = capabilities
    }
}

/// Admin → agent response: accepted protocol version + granted capabilities.
public struct AgentWelcome: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var adminVersion: String
    public var grantedCapabilities: [AgentCapability]

    public init(protocolVersion: Int, adminVersion: String, grantedCapabilities: [AgentCapability]) {
        self.protocolVersion = protocolVersion
        self.adminVersion = adminVersion
        self.grantedCapabilities = grantedCapabilities
    }
}

/// Version + capability negotiation (Plan 11 A1: at least one-version
/// admin/agent compatibility skew; graceful capability degradation).
public enum AgentNegotiation {
    /// Admin accepts an agent exactly ONE protocol version behind.
    public static func compatible(adminProtocol: Int, agent: AgentHello) -> Bool {
        let skew = adminProtocol - agent.protocolVersion
        return skew >= 0 && skew <= 1
    }

    /// Granted capabilities = intersection; unavailable ones drop silently.
    public static func capabilities(admin: [AgentCapability], agent: AgentHello) -> [AgentCapability] {
        admin.filter { agent.capabilities.contains($0) }
    }
}

/// Heartbeat record (agent → admin, periodic).
public struct AgentHeartbeat: Codable, Equatable, Sendable {
    public var agentVersion: String
    public var capabilities: [AgentCapability]
    public var uptimeSeconds: Int
    public var sentAt: Date

    public init(agentVersion: String, capabilities: [AgentCapability], uptimeSeconds: Int, sentAt: Date = Date()) {
        self.agentVersion = agentVersion
        self.capabilities = capabilities
        self.uptimeSeconds = uptimeSeconds
        self.sentAt = sentAt
    }
}

// MARK: - Enrollment (Plan 11 §5)

public struct AgentIdentity: Codable, Equatable, Sendable {
    public var deviceLabel: String
    public var credentialID: CredentialID
    public var secretPrefix: String
}

/// Enrollment service: admin issues a ONE-TIME token; the agent redeems it
/// once for a per-device identity. Identity secrets live in the Keychain only;
/// the database records the reference.
public struct EnrollmentService {
    let db: SQLiteDatabase
    let secretStore: SecretStore

    public init(db: SQLiteDatabase, secretStore: SecretStore) {
        self.db = db
        self.secretStore = secretStore
    }

    /// Issue a single-use enrollment token.
    public func issueToken(deviceLabel: String) throws -> String {
        let token = UUID().uuidString + "." + UUID().uuidString
        try db.execute(
            "INSERT INTO enrollment_tokens (token, device_label, created_at) VALUES (?, ?, ?)",
            bindings: [token, deviceLabel, iso(Date())]
        )
        return token
    }

    /// Redeem a token exactly once → per-device identity (Keychain-backed).
    public func redeem(token: String) throws -> AgentIdentity? {
        let rows = try db.query("SELECT device_label, redeemed_at FROM enrollment_tokens WHERE token = ?", bindings: [token])
        guard let row = rows.first else {
            throw AuthenticationError.badCredentials(user: "unknown token")
        }
        guard (row.opt("redeemed_at") ?? nil) == nil else {
            throw AuthenticationError.badCredentials(user: "token already used")
        }
        let deviceLabel = row.str("device_label")
        // Generate a per-device identity secret.
        let secret = "odid." + UUID().uuidString + "." + UUID().uuidString
        let credentialID = CredentialID()
        try secretStore.store(secret: secret, for: credentialID, kind: CredentialKind.agentToken.storageValue)
        try db.execute(
            "INSERT INTO credentials (id, kind, credential_reference) VALUES (?, ?, ?)",
            bindings: [credentialID.rawValue, CredentialKind.agentToken.storageValue, credentialID.rawValue]
        )
        try db.execute(
            "UPDATE enrollment_tokens SET redeemed_at = ? WHERE token = ?",
            bindings: [iso(Date()), token]
        )
        try db.execute(
            "INSERT INTO audit_events (actor, action, targets, parameters, result) VALUES ('agent', 'agent.enrolled', ?, '{}', 'success')",
            bindings: [deviceLabel]
        )
        return AgentIdentity(
            deviceLabel: deviceLabel,
            credentialID: credentialID,
            secretPrefix: String(secret.prefix(16))
        )
    }
}

// MARK: - Agent job queue (Plan 11 §3 — daemon durable jobs)

public struct AgentJob: Codable, Equatable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable { case pending, running, done, failed }

    public var id: UUID
    public var type: String
    public var payloadJSON: String
    public var state: State
    public var resultJSON: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), type: String, payloadJSON: String, state: State = .pending, resultJSON: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.payloadJSON = payloadJSON
        self.state = state
        self.resultJSON = resultJSON
        self.createdAt = createdAt
    }
}

/// Durable job queue for the agent daemon (Plan 11 §3: durable jobs).
/// Jobs survive daemon restart; terminal states are final.
public struct AgentJobQueue {
    let db: SQLiteDatabase

    public init(db: SQLiteDatabase) {
        self.db = db
    }

    @discardableResult
    public func enqueue(type: String, payloadJSON: String) throws -> AgentJob {
        let job = AgentJob(type: type, payloadJSON: payloadJSON)
        try db.execute(
            "INSERT INTO agent_jobs (id, type, payload, state, created_at) VALUES (?, ?, ?, ?, ?)",
            bindings: [job.id.uuidString, job.type, job.payloadJSON, job.state.rawValue, iso(job.createdAt)]
        )
        return job
    }

    public func pending() throws -> [AgentJob] {
        let rows = try db.query("SELECT id, type, payload, state, created_at FROM agent_jobs WHERE state IN ('pending','running') ORDER BY created_at")
        return rows.compactMap(Self.map)
    }

    public func load(_ id: UUID) throws -> AgentJob? {
        let rows = try db.query("SELECT id, type, payload, state, result, created_at FROM agent_jobs WHERE id = ?", bindings: [id.uuidString])
        return rows.first.flatMap(Self.map)
    }

    public func markDone(jobID: UUID, resultJSON: String) throws {
        try db.execute(
            "UPDATE agent_jobs SET state = 'done', result = ? WHERE id = ?",
            bindings: [resultJSON, jobID.uuidString]
        )
    }

    public func markFailed(jobID: UUID, errorText: String) throws {
        try db.execute(
            "UPDATE agent_jobs SET state = 'failed', result = ? WHERE id = ?",
            bindings: [#"{"error":"\#(errorText)"}"#, jobID.uuidString]
        )
    }

    static func map(_ row: Row) -> AgentJob? {
        guard let id = row.opt("id").flatMap(UUID.init(uuidString:)),
              let type = row.opt("type") else { return nil }
        return AgentJob(
            id: id,
            type: type,
            payloadJSON: row.opt("payload") ?? "{}",
            state: AgentJob.State(rawValue: row.str("state")) ?? .pending,
            resultJSON: row.opt("result"),
            createdAt: row.date("created_at") ?? Date()
        )
    }
}

// MARK: - Packaging (Plan 11 §2)

public enum AgentPackaging {
    /// LaunchDaemon plist (privileged/system operations only, §3).
    public static func launchDaemonPlabel(agentPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>com.opendesk.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(agentPath)</string>
                <string>daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Background</string>
        </dict>
        </plist>
        """
    }

    /// Per-user LaunchAgent plist (user-session operations, §3).
    public static func launchAgentPlist(agentPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.opendesk.agent.user</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(agentPath)</string>
                <string>user-agent</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }
}
