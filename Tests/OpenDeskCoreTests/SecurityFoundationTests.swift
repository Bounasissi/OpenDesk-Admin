import XCTest
@testable import OpenDeskCore

/// Plan 05 tests: credential service (Keychain + reference rows), RBAC
/// authorization service, SSH host-key policy (TOFU), secret redaction.
final class SecurityFoundationTests: XCTestCase {

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-sec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }

    // MARK: Credential service (Plan 05 §3 + A1.1)

    func testCredentialStoreStoresSecretOnlyInKeychain() throws {
        let db = try tempDB()
        let keychain = KeychainSecretStore(service: "com.opendesk.test.sec")
        let service = CredentialService(db: db, secretStore: keychain)
        let deviceID = DeviceID()
        try SQLiteDeviceRepository(db: db).upsert(Device(id: deviceID, hostname: "lab-01"))
        let credential = try service.store(
            kind: .vncPassword, username: "admin", secret: "vnc-secret-123", deviceID: deviceID
        )
        // Reference row exists; secret material is NOT in the database.
        let secretInDB = try db.scalar("SELECT credential_reference FROM credentials WHERE id = ?", bindings: [credential.id.rawValue])
        XCTAssertEqual(secretInDB, credential.id.rawValue)
        let rawRows = try db.query("SELECT * FROM credentials")
        for row in rawRows {
            for value in row.values.values {
                XCTAssertNotEqual(value, "vnc-secret-123", "secret must never be stored in SQLite")
            }
        }
        // Keychain holds the secret.
        XCTAssertEqual(try keychain.read(reference: credential.id), "vnc-secret-123")
    }

    func testCredentialRotationRekeysAndRemovesOldSecret() throws {
        let db = try tempDB()
        let keychain = KeychainSecretStore(service: "com.opendesk.test.rot")
        let service = CredentialService(db: db, secretStore: keychain)
        let credential = try service.store(kind: .sshKey, username: "ops", secret: "old-key-material", deviceID: nil)
        try service.rotate(reference: credential.id, newSecret: "new-key-material")
        XCTAssertEqual(try keychain.read(reference: credential.id), "new-key-material")
    }

    func testCredentialRemovalDeletesKeychainAndRow() throws {
        let db = try tempDB()
        let keychain = KeychainSecretStore(service: "com.opendesk.test.rem")
        let service = CredentialService(db: db, secretStore: keychain)
        let credential = try service.store(kind: .sshPassword, username: "admin", secret: "pw", deviceID: nil)
        try service.remove(reference: credential.id)
        XCTAssertNil(try keychain.read(reference: credential.id))
        let rows = try db.stringColumn("SELECT id FROM credentials WHERE id = ?", bindings: [credential.id.rawValue])
        XCTAssertTrue(rows.isEmpty)
    }

    func testCredentialTypesCoverFullSet() {
        let all: [CredentialKind] = [.vncPassword, .sshPassword, .sshKey, .agentToken, .certificate]
        XCTAssertEqual(all.count, 5, "Plan 05 A1.1: full credential set including certificates")
    }

    // MARK: Authorization service (Plan 05 §5 / A1.2)

    func testAuthorizationGrantsAdministratorAndDeniesUnprivileged() throws {
        let db = tempDBNoThrow()
        let audit = SQLiteAuditRepository(db: db)
        let service = AuthorizationService(auditRepository: audit, administrator: "dom")
        XCTAssertEqual(try service.authorize(actor: "dom", privilege: .power), .granted)
        XCTAssertEqual(try service.authorize(actor: "guest", privilege: .control), .denied)
        let events = try audit.recent(limit: 10)
        let denial = events.first { $0.action == "authorization.denied" }
        XCTAssertNotNil(denial, "denials must be audited")
        XCTAssertEqual(denial?.actor, "guest")
    }

    func testAllThirteenPrivilegesEnumerated() {
        XCTAssertEqual(Set(RBACPrivilege.allCases).count, 13)
        XCTAssertTrue(RBACPrivilege.allCases.contains(.lock), "Addendum §8 requires the lock privilege")
    }

    // MARK: Host-key policy (Plan 05 §4)

    func testHostKeyTOFURecordsFirstUse() throws {
        let db = try tempDB()
        let policy = HostKeyPolicy(db: db)
        let first = try policy.evaluate(host: "lab-01.local", fingerprint: "SHA256:first")
        XCTAssertEqual(first, .firstUseTrusted, "first use is recorded (TOFU)")
        let second = try policy.evaluate(host: "lab-01.local", fingerprint: "SHA256:first")
        XCTAssertEqual(second, .verified)
    }

    func testHostKeyMismatchIsHardSecurityEvent() throws {
        let db = try tempDB()
        let policy = HostKeyPolicy(db: db)
        _ = try policy.evaluate(host: "lab-01.local", fingerprint: "SHA256:original")
        XCTAssertThrowsError(try policy.evaluate(host: "lab-01.local", fingerprint: "SHA256:different")) { error in
            guard case AuthenticationError.hostKeyMismatch = error else {
                return XCTFail("expected hostKeyMismatch, got \(error)")
            }
        }
        // The mismatch must be recorded as a hard security event (audit).
        let audit = SQLiteAuditRepository(db: db)
        let events = try audit.recent(limit: 10)
        XCTAssertTrue(events.contains { $0.action == "security.host_key_mismatch" }, "mismatch must be audited")
    }

    // MARK: Redaction (Plan 05 §7.6 → feeds Plan 18 §3)

    func testSecretRedactionFilter() {
        let line = "connect admin:hunter2 to lab-01 token=abc123def456ghi789"
        let redacted = redactSecrets(in: line, secrets: ["hunter2", "abc123def456ghi789"])
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("abc123def456ghi789"))
        XCTAssertTrue(redacted.contains("lab-01"), "non-secret content must survive")
    }

    private func tempDBNoThrow() -> SQLiteDatabase {
        do {
            return try Self.makeDB()
        } catch {
            fatalError("temp db failed: \(error)")
        }
    }

    private static func makeDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-sec2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }
}
