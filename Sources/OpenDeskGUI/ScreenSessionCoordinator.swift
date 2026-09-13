import SwiftUI
import OpenDeskCore

/// Shared app state holding the active screen streaming target so the
/// dashboard can hand a host to the Screen Viewer window.
@MainActor
final class ScreenSessionCoordinator: ObservableObject {
    static let shared = ScreenSessionCoordinator()

    @Published var activeHost: OpenDeskCore.Host?
    @Published var password: String = ""

    /// Replace the active stream with a new host session.
    func open(host: OpenDeskCore.Host, password: String?) {
        activeHost = host
        self.password = password ?? ""
    }
}
