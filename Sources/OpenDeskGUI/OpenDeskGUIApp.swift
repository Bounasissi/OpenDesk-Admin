import SwiftUI
import OpenDeskCore

@main
struct OpenDeskGUIApp: App {
    init() {
        // SPM executables launched from a terminal need the regular
        // activation policy or AppKit tears down immediately.
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        #endif
        // Plan 03 §7.6: launch → open DB → migrate → audit event.
        // A blocked database degrades the app rather than preventing launch;
        // the audit event records either outcome.
        if let db = try? AppBootstrap.openDatabase() {
            AppBootstrap.recordLaunch(db: db)
        }
    }

    var body: some Scene {
        WindowGroup("OpenDesk Admin") {
            DashboardView()
                .frame(minWidth: 900, minHeight: 600)
        }
        Window("Tiled Observation", id: "tiled-observation") {
            TiledObservationView()
                .frame(minWidth: 800, minHeight: 560)
        }
        WindowGroup("Screen Viewer", id: "screen-viewer") {
            ScreenViewerHostView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Screen Viewer Window") {
                    if let url = NSWorkspace.shared.frontmostApplication?.bundleURL {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Show Tiled Observation") {
                    NotificationCenter.default.post(name: .openTiledObservation, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
    }
}

extension Notification.Name {
    static let openTiledObservation = Notification.Name("openTiledObservation")
}
