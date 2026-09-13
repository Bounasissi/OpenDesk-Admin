import XCTest
@testable import OpenDeskCore

/// Plan 11 tests: versioned agent protocol with capability negotiation and
/// one-version skew, enrollment token flow, durable agent job queue,
/// LaunchDaemon/LaunchAgent packaging artifacts.
final class EndpointAgentTests: XCTestCase {

    // MARK: Protocol (Plan 11 §6 — versioned from day one)

    func testAgentHandshakeEncodesVersionAndCapabilities() throws {
        let hello = AgentHello(
            protocolVersion: 1,
            agentVersion: "0.4.0",
            capabilities: [.inventory, .packages, .power, .files, .heartbeat]
        )
        let data = try JSONEncoder().encode(hello)
        let decoded = try JSONDecoder().decode(AgentHello.self, from: data)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.agentVersion, "0.4.0")
        XCTAssertTrue(decoded.capabilities.contains(.inventory))
    }

    func testVersionSkewAgentNWorksWithAdminNAndNPlusOne() {
        // Admin N and N+1 both accept agent N (one-version skew, Plan 11 A1).
        let agent = AgentHello(protocolVersion: 1, agentVersion: "0.4.0", capabilities: [.inventory])
        XCTAssertTrue(AgentNegotiation.compatible(adminProtocol: 1, agent: agent))
        XCTAssertTrue(AgentNegotiation.compatible(adminProtocol: 2, agent: agent), "one-version skew: admin N+1 accepts agent N")
        XCTAssertFalse(AgentNegotiation.compatible(adminProtocol: 3, agent: agent), "two-version skew must degrade")
    }

    func testCapabilityNegotiationDegradesGracefully() throws {
        let agent = AgentHello(protocolVersion: 1, agentVersion: "0.4.0", capabilities: [.inventory, .files])
        let requested: [AgentCapability] = [.inventory, .files, .packages]
        let granted = AgentNegotiation.capabilities(admin: requested, agent: agent)
        XCTAssertEqual(granted, [.inventory, .files], "unavailable capabilities are dropped, not failed")
        XCTAssertTrue(granted.allSatisfy { agent.capabilities.contains($0) })
    }

    // MARK: Enrollment (Plan 11 §5 — one-time token → per-device identity)

    func testEnrollmentTokenRedeemedOnceOnly() throws {
        let db = try tempDB()
        let enrollment = EnrollmentService(db: db, secretStore: KeychainSecretStore(service: "com.opendesk.test.agent"))
        let token = try enrollment.issueToken(deviceLabel: "lab-05")
        // First redemption succeeds and creates a per-device identity.
        let identity = try enrollment.redeem(token: token)
        XCTAssertNotNil(identity)
        // Second redemption of the same one-time token must fail.
        XCTAssertThrowsError(try enrollment.redeem(token: token)) { error in
            guard case AuthenticationError.badCredentials = error else {
                return XCTFail("expected badCredentials on token reuse, got \(error)")
            }
        }
    }

    func testEnrolledIdentityStoredInKeychainNotSQLite() throws {
        let db = try tempDB()
        let keychain = KeychainSecretStore(service: "com.opendesk.test.agent2")
        let enrollment = EnrollmentService(db: db, secretStore: keychain)
        let token = try enrollment.issueToken(deviceLabel: "lab-06")
        let identity = try enrollment.redeem(token: token)
        // The secret material is in the Keychain; the DB has the reference.
        let stored = try keychain.read(reference: identity!.credentialID)
        XCTAssertNotNil(stored)
        XCTAssertNotEqual(stored, "")
        let rows = try db.query("SELECT * FROM credentials")
        for row in rows {
            for value in row.values.values {
                let s = value ?? ""
                XCTAssertFalse(s.contains(identity!.secretPrefix), "identity secret must never appear in SQLite")
            }
        }
    }

    // MARK: Durable agent jobs (Plan 11 §3 — daemon durable jobs)

    func testAgentJobQueueSurvivesRestart() throws {
        let db = try tempDB()
        let queue = AgentJobQueue(db: db)
        let job = try queue.enqueue(type: "inventory.collect", payloadJSON: "{}")
        XCTAssertEqual(try queue.pending().count, 1)
        // "Restart": a fresh queue over the same DB sees the pending job.
        let fresh = AgentJobQueue(db: db)
        let pending = try fresh.pending()
        XCTAssertEqual(pending.first?.id, job.id)
        XCTAssertEqual(pending.first?.state, .pending)
        // Execution marks the job done; terminal states are durable.
        try queue.markDone(jobID: job.id, resultJSON: #"{"ok":true}"#)
        XCTAssertTrue(try queue.pending().isEmpty)
        let done = try queue.load(job.id)
        XCTAssertEqual(done?.state, .done)
        XCTAssertEqual(done?.resultJSON, #"{"ok":true}"#)
    }

    func testAgentJobFailureRetained() throws {
        let db = try tempDB()
        let queue = AgentJobQueue(db: db)
        let job = try queue.enqueue(type: "pkg.install", payloadJSON: "{}")
        try queue.markFailed(jobID: job.id, errorText: "installer exit 3")
        let loaded = try queue.load(job.id)
        XCTAssertEqual(loaded?.state, .failed)
        XCTAssertEqual(loaded?.resultJSON, #"{"error":"installer exit 3"}"#)
    }

    // MARK: Packaging artifacts (Plan 11 §2 — LaunchDaemon + LaunchAgent + SMAppService)

    func testLaunchDaemonPlistTemplate() throws {
        let plist = AgentPackaging.launchDaemonPlabel(agentPath: "/usr/local/bin/opendesk-agent")
        XCTAssertTrue(plist.contains("com.opendesk.agent"), "labeled service")
        XCTAssertTrue(plist.contains("KeepAlive"), "daemon stays alive")
        XCTAssertTrue(plist.contains("/usr/local/bin/opendesk-agent"), "program path")
        XCTAssertTrue(plist.contains("RunAtLoad"))
    }

    func testLaunchAgentPlistTemplate() throws {
        let plist = AgentPackaging.launchAgentPlist(agentPath: "/usr/local/bin/opendesk-agent")
        XCTAssertTrue(plist.contains("com.opendesk.agent.user"), "per-user agent labeled")
        XCTAssertTrue(plist.contains("RunAtLoad"))
    }

    private func tempDB() throws -> SQLiteDatabase {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("od-agent-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: dir.appendingPathComponent("t.db").path)
        _ = try SQLiteMigrator(db: db).run()
        return db
    }
}
