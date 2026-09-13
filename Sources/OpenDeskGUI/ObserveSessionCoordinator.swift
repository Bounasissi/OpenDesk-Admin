import SwiftUI
import OpenDeskCore

/// GUI observe-session coordinator (Plan 10 §2 + Plan 15 §2).
///
/// Connections are owned CENTRALLY here, never by individual views. The
/// coordinator wraps the Core `ObserveSessionManager` (session cap, quality
/// tiers, resource bounds) and owns the per-session `ScreenStreamer` handles.
/// Tiles/bundles render; they do not own connections.
@MainActor
final class ObserveSessionCoordinator: ObservableObject {
    static let shared = ObserveSessionCoordinator()

    private let manager = ObserveSessionManager(maxSessions: 16)
    private var streamers: [SessionID: ScreenStreamer] = [:]
    /// SessionID lookup by host id so tiles can resolve their stream.
    private var sessionByHost: [UUID: SessionID] = [:]

    @Published private(set) var liveSessions: Int = 0

    /// Open a session for a host. Throws when the session cap is reached.
    func open(host: OpenDeskCore.Host, password: String?) throws -> ObservationTileModel {
        let device = Device(hostname: host.hostname, lifecycle: .online)
        let record = try manager.open(device: device)
        let streamer = ScreenStreamer(host: host, password: password)
        streamers[record.id] = streamer
        sessionByHost[host.id] = record.id
        liveSessions = manager.sessionCount
        return ObservationTileModel(host: host, streamer: streamer, sessionID: record.id)
    }

    /// Close a session: streamer teardown + central ownership release.
    func close(_ tile: ObservationTileModel) {
        streamers[tile.sessionID]?.stopStreaming()
        streamers.removeValue(forKey: tile.sessionID)
        try? manager.close(sessionID: tile.sessionID)
        liveSessions = manager.sessionCount
    }

    func closeAll() {
        for tile in tilesSnapshot() { close(tile) }
    }

    /// Quality-tier change WITHOUT reconnect (Plan 10 §5): the manager updates
    /// the tier (identity preserved) and the streamer adjusts its pacing.
    func setTier(_ tile: ObservationTileModel, tier: QualityTier) {
        try? manager.setTier(sessionID: tile.sessionID, tier: tier)
        streamers[tile.sessionID]?.applyQualityTier(tier)
    }

    func isStreaming(hostID: UUID) -> Bool {
        sessionByHost[hostID] != nil
    }

    private func tilesSnapshot() -> [ObservationTileModel] {
        streamers.keys.compactMap { sessionID in
            streamers[sessionID].map { streamer in
                ObservationTileModel(
                    host: OpenDeskCore.Host(hostname: "", username: ""),
                    streamer: streamer,
                    sessionID: sessionID
                )
            }
        }
    }
}
