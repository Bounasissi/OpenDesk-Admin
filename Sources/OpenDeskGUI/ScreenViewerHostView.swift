import SwiftUI
import OpenDeskCore

/// The Screen Viewer window scene: connects to the coordinator's active host
/// and renders the live framebuffer. Shows a picker when no session is active.
struct ScreenViewerHostView: View {
    @ObservedObject var coordinator = ScreenSessionCoordinator.shared
    @State private var registryHosts: [OpenDeskCore.Host] = []
    @State private var selectedHostname = ""

    var body: some View {
        Group {
            if let streamer = coordinator.activeStreamer {
                ScreenViewerView(
                    streamer: streamer,
                    onConnectWithPassword: { coordinator.connectWithPassword($0) },
                    onDisconnect: { coordinator.disconnect() }
                )
            } else if coordinator.activeHost != nil {
                VStack(spacing: 12) {
                    Text(coordinator.errorMessage ?? "Unable to open the screen session.")
                        .foregroundStyle(.secondary)
                    Button("Dismiss") { coordinator.disconnect() }
                }
            } else {
                picker
            }
        }
        .onAppear { registryHosts = HostRegistry().loadAll() }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var picker: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Screen Viewer")
                .font(.headline)
            HStack {
                Picker("Host", selection: $selectedHostname) {
                    Text("Select…").tag("")
                    ForEach(registryHosts) { host in
                        Text(host.hostname).tag(host.hostname)
                    }
                }
                .frame(maxWidth: 260)
                Button("Observe") {
                    guard let host = registryHosts.first(where: { $0.hostname == selectedHostname }) else { return }
                    coordinator.open(host: host, password: nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedHostname.isEmpty)
            }
            Text("Screen observation uses the host's Screen Sharing (VNC) service. Add hosts in the dashboard first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
