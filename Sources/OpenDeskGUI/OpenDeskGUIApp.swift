import SwiftUI

@main
struct OpenDeskGUIApp: App {
    init() {
        // SPM executables launched from a terminal need the regular
        // activation policy or AppKit tears down immediately.
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.regular)
        #endif
    }

    var body: some Scene {
        WindowGroup("OpenDesk Admin") {
            DashboardView()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
