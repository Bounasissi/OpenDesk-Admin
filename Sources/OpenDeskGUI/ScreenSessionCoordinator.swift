import SwiftUI
import OpenDeskCore

/// Shared app state holding the active screen streaming target so the
/// dashboard can hand a host to the Screen Viewer window.
@MainActor
final class ScreenSessionCoordinator: ObservableObject {
    static let shared = ScreenSessionCoordinator()

    @Published var activeHost: OpenDeskCore.Host?
    @Published var password: String = ""
    @Published private(set) var activeStreamer: ScreenStreamer?
    @Published private(set) var errorMessage: String?
    private var activeTile: ObservationTileModel?

    /// Replace the active stream with a new host session.
    func open(host: OpenDeskCore.Host, password: String?) {
        closeActiveTile()
        activeHost = host
        self.password = password ?? ""
        do {
            let tile = try ObserveSessionCoordinator.shared.open(host: host, password: password, tier: .focused)
            activeTile = tile
            activeStreamer = tile.streamer
            ObserveSessionCoordinator.shared.focus(tile)
            errorMessage = nil
        } catch {
            activeStreamer = nil
            errorMessage = "Could not open screen session: \(error)"
        }
    }

    func connectWithPassword(_ password: String) {
        guard let host = activeHost else { return }
        self.password = password
        closeActiveTile()
        do {
            let tile = try ObserveSessionCoordinator.shared.open(host: host, password: password.isEmpty ? nil : password, tier: .focused)
            activeTile = tile
            activeStreamer = tile.streamer
            ObserveSessionCoordinator.shared.focus(tile)
            errorMessage = nil
        } catch {
            activeStreamer = nil
            errorMessage = "Could not retry screen session: \(error)"
        }
    }

    func disconnect() {
        closeActiveTile()
        activeStreamer = nil
        activeHost = nil
        password = ""
        errorMessage = nil
        ObserveSessionCoordinator.shared.focus(nil)
    }

    private func closeActiveTile() {
        guard let activeTile else { return }
        ObserveSessionCoordinator.shared.close(activeTile)
        self.activeTile = nil
    }
}
