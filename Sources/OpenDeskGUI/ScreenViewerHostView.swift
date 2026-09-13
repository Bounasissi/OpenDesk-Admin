import SwiftUI
import OpenDeskCore

/// Placeholder host for the Screen Viewer window; a future pass will bind an
/// RFB streaming session to this window. Kept separate from the dashboard so
/// the window scene compiles and opens without a selected host.
struct ScreenViewerHostView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Screen Viewer")
                .font(.headline)
            Text("Open a screen session from the dashboard's Screen tab. Frame streaming lands here in the next iteration.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
        }
        .padding()
    }
}
