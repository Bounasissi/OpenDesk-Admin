import Foundation

// MARK: - Quality tiers (Plan 10 §3 + Addendum §10)

/// Resource-aware multi-observe quality classes.
public enum QualityTier: String, Codable, Sendable, CaseIterable {
    case focused
    case visibleThumbnail
    case background
    case suspended

    /// Measured refresh ceiling per tier (Plan 10 §3 guidance; measured rather
    /// than blindly optimized — these are caps, not targets).
    public var maxFPS: Double {
        switch self {
        case .focused: return 30 // up to server/session limit
        case .visibleThumbnail: return 5 // §3 band: ~2–5 FPS
        case .background: return 1 // heavily throttled
        case .suspended: return 0 // suspend or near-zero refresh
        }
    }

    /// Incremental frame-request cadence in milliseconds for this tier.
    public var frameRequestIntervalMs: Int {
        guard maxFPS > 0 else { return Int.max } // never request when suspended
        return Int(1000 / maxFPS)
    }
}

// MARK: - Resource snapshot (Plan 10 A1 verification)

public struct ObserveResourceSnapshot: Equatable, Sendable {
    public var sessions: Int
    public var sockets: Int
    public var threads: Int
    /// Rough bandwidth ceiling in kbit/s across active tiers.
    public var bandwidthKbps: Int
}

// MARK: - Session manager (Plan 10 §2)

public struct ObserveSessionRecord: Sendable {
    public let id: SessionID
    public let deviceID: DeviceID
    public let hostname: String
    public var tier: QualityTier
    /// Opaque connection identity: stable across tier changes (promotion does
    /// NOT reconnect — Plan 10 §5).
    public let connectionIdentity: String
    public var active: Bool
}

/// Central multi-observe session manager. Sessions are owned HERE, never by
/// individual views (Plan 10 §2). Resource-aware: enforces a session cap and
/// exposes a bounded-resource snapshot for Plan 17-style verification.
public final class ObserveSessionManager: @unchecked Sendable {
    public let maxSessions: Int
    private var sessions: [SessionID: ObserveSessionRecord] = [:]
    private let lock = NSLock()

    public init(maxSessions: Int = 16) {
        self.maxSessions = maxSessions
    }

    @discardableResult
    public func open(device: Device) throws -> ObserveSessionRecord {
        lock.lock(); defer { lock.unlock() }
        guard sessions.count < maxSessions else {
            throw ConfigurationError.invalidValue(
                key: "sessionLimit",
                reason: "observe session cap reached (\(maxSessions))"
            )
        }
        let id = SessionID()
        let record = ObserveSessionRecord(
            id: id,
            deviceID: device.id,
            hostname: device.hostname,
            tier: .visibleThumbnail,
            connectionIdentity: "\(device.hostname):5900#\(id.rawValue)",
            active: true
        )
        sessions[id] = record
        return record
    }

    public func setTier(sessionID: SessionID, tier: QualityTier) throws {
        lock.lock(); defer { lock.unlock() }
        guard var record = sessions[sessionID] else {
            throw PersistenceError.queryFailed("session \(sessionID) not found")
        }
        // Promotion/ demotion renegotiates cadence only — connection identity
        // is preserved (no unnecessary reconnect, Plan 10 §5).
        record.tier = tier
        record.active = tier != .suspended
        sessions[sessionID] = record
    }

    public func close(sessionID: SessionID) throws {
        lock.lock(); defer { lock.unlock() }
        sessions.removeValue(forKey: sessionID)
    }

    public var sessionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return sessions.count
    }

    public func isCentralOwner(session: SessionID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sessions[session] != nil
    }

    public func connectionIdentity(sessionID: SessionID) -> String? {
        lock.lock(); defer { lock.unlock() }
        return sessions[sessionID]?.connectionIdentity
    }

    public func tier(sessionID: SessionID) -> QualityTier? {
        lock.lock(); defer { lock.unlock() }
        return sessions[sessionID]?.tier
    }

    public func isRequestingFrames(sessionID: SessionID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let record = sessions[sessionID] else { return false }
        return record.active && record.tier.maxFPS > 0
    }

    /// Bounded resources (Plan 10 A1): one socket + one update thread per
    /// streaming session; bandwidth bounded by tier caps.
    public var resourceSnapshot: ObserveResourceSnapshot {
        lock.lock(); defer { lock.unlock() }
        let streaming = sessions.values.filter { $0.tier != .suspended }
        let bandwidth = streaming.reduce(0) { partial, record in
            partial + Int(record.tier.maxFPS * 900) // ~900 kbit/s per FPS at 1080p hextile-ish
        }
        return ObserveResourceSnapshot(
            sessions: sessions.count,
            sockets: sessions.count,
            threads: streaming.count,
            bandwidthKbps: bandwidth
        )
    }

    // MARK: Grid plan (Plan 10 §4 — 2/4/8/16)

    public struct GridPlan: Equatable, Sendable {
        public let columns: Int
        public let visibleSessions: Int
        public let tierForAll: QualityTier
    }

    public static func gridPlan(columns: Int) throws -> GridPlan {
        guard [2, 4, 8, 16].contains(columns) else {
            throw ConfigurationError.invalidValue(key: "columns", reason: "supported grids are 2, 4, 8, 16")
        }
        return GridPlan(columns: columns, visibleSessions: columns, tierForAll: .visibleThumbnail)
    }
}
