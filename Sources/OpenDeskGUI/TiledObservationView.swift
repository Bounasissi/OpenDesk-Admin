import SwiftUI
import OpenDeskCore

/// Multi-host tiled screen observation — ARD's signature multi-screen view.
/// Each tile owns an independent ScreenStreamer instance.
struct TiledObservationView: View {
    @StateObject private var tileModel = TileViewModel()
    /// Grid sizes per Plan 10 §4: exactly 2/4/8/16 (validated by gridPlan).
    @State private var columns = 2

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Tiled Observation")
                    .font(.headline)
                Menu("Columns: \(columns)") {
                    ForEach([2, 4, 8, 16], id: \.self) { size in
                        Button("\(size)") { columns = size }
                    }
                }
                .frame(width: 160)
                Spacer()
                Text("\(tileModel.tiles.count) streaming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Stop All") { tileModel.stopAll() }
                    .disabled(tileModel.tiles.isEmpty)
            }
            .padding(.horizontal, 10)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                    ForEach(tileModel.tiles) { tile in
                        ObservationTile(tile: tile)
                            .aspectRatio(16 / 10, contentMode: .fit)
                    }
                }
                .padding(10)
            }
        }
        .onAppear { tileModel.reloadHosts() }
        .safeAreaInset(edge: .bottom) {
            TileHostPicker(hosts: tileModel.availableHosts, activeHostnames: Set(tileModel.tiles.map(\.host.hostname))) { host in
                tileModel.addTile(for: host)
            }
            .padding(8)
        }
    }
}

extension Notification.Name {
    static let opendeskCloseTile = Notification.Name("opendeskCloseTile")
}

// MARK: - Tile

struct ObservationTile: View {
    @ObservedObject var tile: ObservationTileModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(tile.streamer.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(tile.host.hostname)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button {
                    // Route through the coordinator (central ownership).
                    NotificationCenter.default.post(name: .opendeskCloseTile, object: tile.id)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(nsColor: .windowBackgroundColor))

            TileFrameView(streamer: tile.streamer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear { tile.start() }
    }
}

/// Renders one streamer's latest frame scaled to fit the tile.
struct TileFrameView: View {
    @ObservedObject var streamer: ScreenStreamer

    var body: some View {
        Group {
            if let frame = streamer.frame {
                GeometryReader { geo in
                    Image(nsImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else {
                ZStack {
                    Color.black
                    Text(streamer.status)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
        }
    }
}

struct TileHostPicker: View {
    let hosts: [OpenDeskCore.Host]
    let activeHostnames: Set<String>
    var onAdd: (OpenDeskCore.Host) -> Void
    @State private var selected = ""

    var body: some View {
        HStack {
            Picker("Add host to grid:", selection: $selected) {
                Text("Select…").tag("")
                ForEach(hosts.filter { !activeHostnames.contains($0.hostname) }) { host in
                    Text(host.hostname).tag(host.hostname)
                }
            }
            .frame(maxWidth: 280)
            Button("Add Tile") {
                guard let host = hosts.first(where: { $0.hostname == selected }) else { return }
                onAdd(host)
                selected = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty)
        }
    }
}

// MARK: - Models

/// One tile: a host + its streamer lifecycle.
@MainActor
final class ObservationTileModel: ObservableObject, Identifiable {
    let id = UUID()
    let host: OpenDeskCore.Host
    let streamer: ScreenStreamer
    /// Central session identity (Plan 10 §2) — the coordinator owns this
    /// session; the tile renders it.
    let sessionID: SessionID

    init(host: OpenDeskCore.Host, password: String? = nil, streamer: ScreenStreamer? = nil, sessionID: SessionID = SessionID()) {
        self.host = host
        self.streamer = streamer ?? ScreenStreamer(host: host, password: password)
        self.sessionID = sessionID
    }

    func start() {
        streamer.startStreaming()
    }

    func stop() {
        streamer.stopStreaming()
    }
}

@MainActor
final class TileViewModel: ObservableObject {
    /// Central ownership (Plan 10 §2): sessions are opened/closed via the
    /// coordinator, not by tiles or views.
    let coordinator = ObserveSessionCoordinator()
    @Published var tiles: [ObservationTileModel] = []
    @Published var availableHosts: [OpenDeskCore.Host] = []

    func reloadHosts() {
        availableHosts = HostRegistry().loadAll()
    }

    func addTile(for host: OpenDeskCore.Host) {
        guard !tiles.contains(where: { $0.host.id == host.id }) else { return }
        guard let tile = try? coordinator.open(host: host, password: nil) else { return }
        tiles.append(tile)
    }

    func removeTile(_ tile: ObservationTileModel) {
        coordinator.close(tile)
        tiles.removeAll { $0.id == tile.id }
    }

    func stopAll() {
        tiles.forEach(coordinator.close)
        tiles.removeAll()
    }
}
