import XCTest
@testable import OpenDeskCore

/// Plan 10 tests: central session manager, quality tiers, 2/4/8/16 grid,
/// promotion without reconnect, bounded resource verification.
final class MultiObserveTests: XCTestCase {

    // MARK: Quality tiers (Plan 10 §3 + A1)

    func testQualityTierRefreshCadences() {
        XCTAssertGreaterThan(QualityTier.focused.maxFPS, QualityTier.visibleThumbnail.maxFPS)
        XCTAssertGreaterThan(QualityTier.visibleThumbnail.maxFPS, QualityTier.background.maxFPS)
        XCTAssertEqual(QualityTier.suspended.maxFPS, 0, "suspended = near-zero refresh")
        // Thumbnail band per §3: approximately 2–5 FPS.
        XCTAssertGreaterThanOrEqual(QualityTier.visibleThumbnail.maxFPS, 2)
        XCTAssertLessThanOrEqual(QualityTier.visibleThumbnail.maxFPS, 5)
    }

    // MARK: Central session manager (Plan 10 §2 + A1)

    func testSessionManagerOwnsConnectionsCentrally() throws {
        let manager = ObserveSessionManager(maxSessions: 16)
        let devices = (0..<16).map { Device(hostname: "mac-\($0)", lifecycle: .online) }
        var sessions: [SessionID] = []
        for device in devices {
            let session = try manager.open(device: device)
            sessions.append(session.id)
        }
        XCTAssertEqual(manager.sessionCount, 16, "resource-aware manager supports 16 simultaneous sessions")
        // Connections are owned centrally, not by views.
        XCTAssertTrue(manager.isCentralOwner(session: sessions[0]))
    }

    func testSessionCapEnforced() throws {
        let manager = ObserveSessionManager(maxSessions: 4)
        for index in 0..<4 {
            _ = try manager.open(device: Device(hostname: "m-\(index)", lifecycle: .online))
        }
        XCTAssertThrowsError(try manager.open(device: Device(hostname: "overflow", lifecycle: .online)))
        // Resource bound: sockets ≤ sessions.
        XCTAssertEqual(manager.resourceSnapshot.sockets, 4)
        XCTAssertEqual(manager.resourceSnapshot.threads, 4, "one update thread per streaming session")
    }

    // MARK: Promotion without reconnect (Plan 10 §5 + A1)

    func testPromotionKeepsConnection() throws {
        let manager = ObserveSessionManager(maxSessions: 8)
        let session = try manager.open(device: Device(hostname: "focus-target", lifecycle: .online))
        try manager.setTier(sessionID: session.id, tier: .visibleThumbnail)
        let before = manager.connectionIdentity(sessionID: session.id)
        try manager.setTier(sessionID: session.id, tier: .focused)
        let after = manager.connectionIdentity(sessionID: session.id)
        XCTAssertEqual(before, after, "promotion must not reconnect — same connection identity")
        XCTAssertEqual(manager.tier(sessionID: session.id), .focused)
    }

    // MARK: Grid plans (Plan 10 §4 — 2/4/8/16)

    func testGridPlansForSupportedSizes() throws {
        for size in [2, 4, 8, 16] {
            let plan = try ObserveSessionManager.gridPlan(columns: size)
            XCTAssertEqual(plan.visibleSessions, size)
            XCTAssertEqual(plan.tierForAll, .visibleThumbnail, "grid starts thumbnails; focused is per-tile")
        }
        XCTAssertThrowsError(try ObserveSessionManager.gridPlan(columns: 3), "only 2/4/8/16 are supported layouts")
        XCTAssertThrowsError(try ObserveSessionManager.gridPlan(columns: 32))
    }

    // MARK: Suspension stops frame requests (bounded bandwidth)

    func testSuspensionStopsFrameRequests() throws {
        let manager = ObserveSessionManager(maxSessions: 4)
        let session = try manager.open(device: Device(hostname: "s", lifecycle: .online))
        try manager.setTier(sessionID: session.id, tier: .suspended)
        XCTAssertFalse(manager.isRequestingFrames(sessionID: session.id), "suspended session requests no frames")
        XCTAssertTrue(manager.isRequestingFrames(sessionID: try manager.open(device: Device(hostname: "t", lifecycle: .online)).id))
    }
}
