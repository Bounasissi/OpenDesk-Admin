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
    private var tiles: [SessionID: ObservationTileModel] = [:]

    @Published private(set) var liveSessions: Int = 0

    /// Open a session for a host. Throws when the session cap is reached.
    func open(
        host: OpenDeskCore.Host,
        password: String?,
        tier: QualityTier = .visibleThumbnail
    ) throws -> ObservationTileModel {
        let device = Device(hostname: host.hostname, lifecycle: .online)
        var record = try manager.open(device: device)
        if record.tier != tier {
            try manager.setTier(sessionID: record.id, tier: tier)
            record.tier = tier
            record.active = tier != .suspended
        }
        let streamer = ScreenStreamer(host: host, password: password, qualityTier: record.tier)
        let tile = ObservationTileModel(host: host, streamer: streamer, sessionID: record.id)
        streamers[record.id] = streamer
        tiles[record.id] = tile
        liveSessions = manager.sessionCount
        // The coordinator, not the view, starts and owns the connection lifecycle.
        streamer.startStreaming()
        return tile
    }

    /// Close a session: streamer teardown + central ownership release.
    func close(_ tile: ObservationTileModel) {
        streamers[tile.sessionID]?.stopStreaming()
        streamers.removeValue(forKey: tile.sessionID)
        tiles.removeValue(forKey: tile.sessionID)
        try? manager.close(sessionID: tile.sessionID)
        liveSessions = manager.sessionCount
    }

    func closeAll() {
        for tile in Array(tiles.values) { close(tile) }
    }

    /// Quality-tier change WITHOUT reconnect (Plan 10 §5): the manager updates
    /// the tier (identity preserved) and the streamer adjusts its pacing.
    func setTier(_ tile: ObservationTileModel, tier: QualityTier) {
        try? manager.setTier(sessionID: tile.sessionID, tier: tier)
        streamers[tile.sessionID]?.applyQualityTier(tier)
    }

    /// Keep one selected session responsive while other active tiles use the
    /// bounded thumbnail cadence. A nil selection clears the promotion.
    func focus(_ selected: ObservationTileModel?) {
        for tile in tiles.values {
            setTier(tile, tier: tile.sessionID == selected?.sessionID ? .focused : .visibleThumbnail)
        }
    }

}
