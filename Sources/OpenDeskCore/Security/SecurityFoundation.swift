import Foundation

// MARK: - Credential kinds (Plan 05 §3 + A1.1)

public enum CredentialKind: String, Codable, Sendable, CaseIterable {
    case vncPassword
    case sshPassword
    case sshKey
    case agentToken
    case certificate

    /// Storage token used by the credentials schema CHECK constraint
    /// (migration 001): 'password','ssh_key','certificate','agent_token','vnc'.
    public var storageValue: String {
        switch self {
        case .vncPassword: return "vnc"
        case .sshPassword: return "password"
        case .sshKey: return "ssh_key"
        case .agentToken: return "agent_token"
        case .certificate: return "certificate"
        }
    }

    public init?(storageValue: String) {
        switch storageValue {
        case "vnc": self = .vncPassword
        case "password": self = .sshPassword
        case "ssh_key": self = .sshKey
        case "agent_token": self = .agentToken
        case "certificate": self = .certificate
        default: return nil
        }
    }
}

// MARK: - Authorization result (Plan 05 §5)

public enum AuthorizationDecision: Equatable, Sendable {
    case granted
    case denied
}

// MARK: - Credential service (Plan 05 §7.2)

/// Credential CRUD over the Keychain seam + SQLite reference rows.
/// Secrets NEVER touch SQLite; the reference (CredentialID) does.
public struct CredentialService {
    let db: SQLiteDatabase
    let secretStore: SecretStore

    public init(db: SQLiteDatabase, secretStore: SecretStore) {
        self.db = db
        self.secretStore = secretStore
    }

    @discardableResult
    public func store(kind: CredentialKind, username: String?, secret: String, deviceID: DeviceID?) throws -> CredentialReference {
        let id = CredentialID()
        try secretStore.store(secret: secret, for: id, kind: kind.storageValue)
        try db.execute("""
        INSERT INTO credentials (id, device_id, kind, username, credential_reference) VALUES (?, ?, ?, ?, ?)
        """, bindings: [
            id.rawValue,
            deviceID?.rawValue,
            kind.storageValue,
            username,
            id.rawValue,
        ])
        return CredentialReference(id: id, kind: kind, username: username, deviceID: deviceID)
    }

    /// Rotation: replace the secret under the same reference (Plan 05 A1.1).
    public func rotate(reference: CredentialID, newSecret: String) throws {
        let kind = try db.scalar("SELECT kind FROM credentials WHERE id = ?", bindings: [reference.rawValue])
        try secretStore.store(secret: newSecret, for: reference, kind: kind ?? "unknown")
    }

    /// Removal: Keychain secret + reference row (Plan 05 A1.1).
    public func remove(reference: CredentialID) throws {
        try secretStore.delete(reference: reference)
        try db.execute("DELETE FROM credentials WHERE id = ?", bindings: [reference.rawValue])
    }

    public func load(reference: CredentialID) throws -> CredentialReference? {
        let rows = try db.query("SELECT id, device_id, kind, username FROM credentials WHERE id = ?", bindings: [reference.rawValue])
        guard let row = rows.first,
              let kind = row.opt("kind").flatMap(CredentialKind.init(storageValue:)) else { return nil }
        return CredentialReference(
            id: reference,
            kind: kind,
            username: row.opt("username"),
            deviceID: row.opt("device_id").map(DeviceID.init(rawValue:))
        )
    }
}

/// The persisted reference (no secret material).
public struct CredentialReference: Hashable, Codable, Sendable {
    public let id: CredentialID
    public let kind: CredentialKind
    public let username: String?
    public let deviceID: DeviceID?

    public init(id: CredentialID, kind: CredentialKind, username: String?, deviceID: DeviceID?) {
        self.id = id
        self.kind = kind
        self.username = username
        self.deviceID = deviceID
    }
}

// MARK: - Authorization service (Plan 05 §5 / A1.2)

/// RBAC authorization seam. v1 uses a single administrator identity, but the
/// model (privilege enum + service + audit) is the enforcement point contract.
public struct AuthorizationService {
    let auditRepository: AuditRepository
    let administrator: String

    public init(auditRepository: AuditRepository, administrator: String) {
        self.auditRepository = auditRepository
        self.administrator = administrator
    }

    public func authorize(actor: String, privilege: RBACPrivilege) throws -> AuthorizationDecision {
        let decision: AuthorizationDecision = actor == administrator ? .granted : .denied
        if decision == .denied {
            try auditRepository.record(AuditEvent(
                actor: actor,
                action: "authorization.denied",
                targets: [privilege.rawValue],
                result: .denied
            ))
        }
        return decision
    }
}

// MARK: - Host-key policy (Plan 05 §4)

public enum HostKeyDecision: Equatable, Sendable {
    case firstUseTrusted
    case verified
}

/// SSH host-key verification policy: TOFU on first explicit use, recorded;
/// subsequent mismatch is a hard security event (typed error + audit).
public struct HostKeyPolicy {
    let db: SQLiteDatabase
    let auditRepository: AuditRepository

    public init(db: SQLiteDatabase, auditRepository: AuditRepository? = nil) {
        self.db = db
        self.auditRepository = auditRepository ?? SQLiteAuditRepository(db: db)
    }

    public func evaluate(host: String, fingerprint: String) throws -> HostKeyDecision {
        let stored = try db.scalar("SELECT fingerprint FROM host_key_records WHERE host = ?", bindings: [host])
        guard let stored else {
            try db.execute(
                "INSERT INTO host_key_records (host, fingerprint, recorded_at) VALUES (?, ?, ?)",
                bindings: [host, fingerprint, iso(Date())]
            )
            try auditRepository.record(AuditEvent(
                actor: "system",
                action: "security.host_key_first_use",
                targets: [host],
                parameters: ["fingerprint": fingerprint],
                result: .success
            ))
            return .firstUseTrusted
        }
        if stored == fingerprint {
            return .verified
        }
        try auditRepository.record(AuditEvent(
            actor: "system",
            action: "security.host_key_mismatch",
            targets: [host],
            parameters: ["expected": stored, "observed": fingerprint],
            result: .failure
        ))
        throw AuthenticationError.hostKeyMismatch(fingerprint: fingerprint)
    }
}

// MARK: - Redaction (Plan 05 §7.6; Plan 18 §3 consumer)

/// Replace every known secret occurrence with a fixed placeholder.
public func redactSecrets(in text: String, secrets: [String]) -> String {
    var result = text
    for secret in secrets where !secret.isEmpty {
        result = result.replacingOccurrences(of: secret, with: "[REDACTED]")
    }
    return result
}

/// Key-based parameter redaction (Plan 18 §3 / Plan 05 §7.6): any parameter
/// whose key indicates secret material is replaced wholesale. Applied before
/// persistence (audit) and before diagnostic export (defense in depth).
public func redactParameterKeys(in text: String) -> String {
    let sensitiveKeys = ["password", "secret", "token", "vncpassword", "credential", "privatekey", "key"]
    var result = text
    for key in sensitiveKeys {
        // Scan JSON-style "key": "value" pairs. The key's OPENING quote is the
        // second quote before the colon (the last one is its closing quote).
        var searchStart = result.startIndex
        while let colonRange = result.range(of: ":", range: searchStart..<result.endIndex) {
            let keyEndQuote = result[..<colonRange.lowerBound].lastIndex(of: "\"")
            guard let keyStartQuote = keyEndQuote.flatMap({ result[..<$0].lastIndex(of: "\"") }) else {
                searchStart = colonRange.upperBound
                continue
            }
            let keyText = result[result.index(after: keyStartQuote)..<keyEndQuote!].lowercased()
            let afterColon = colonRange.upperBound
            guard let valueStart = result.range(of: "\"", range: afterColon..<result.endIndex)?.lowerBound,
                  let valueEndQuote = result.range(of: "\"", range: result.index(after: valueStart)..<result.endIndex)?.lowerBound else {
                searchStart = colonRange.upperBound
                continue
            }
            if sensitiveKeys.contains(where: { keyText.contains($0) }) {
                result = result.replacingCharacters(in: keyStartQuote...valueEndQuote, with: "\"[REDACTED]\"")
                searchStart = result.startIndex
                continue
            }
            searchStart = afterColon
        }
    }
    return result
}
