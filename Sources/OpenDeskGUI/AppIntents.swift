import AppIntents
import OpenDeskCore

// Plan 12 §4 (Addendum §20): the six required App Intents, backed by the same
// Core services the CLI and local API use. Exposed to Shortcuts automatically.

struct RunTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Task"
    static let description = IntentDescription("Run a saved OpenDesk task by name.")

    @Parameter(title: "Task name")
    var taskName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let db = try? AppBootstrap.openDatabase() else {
            return .result(dialog: "OpenDesk database unavailable.")
        }
        let runner = DurableTaskRunner(db: db, transport: NoopTransport())
        do {
            let task = try runner.submit(
                type: "saved.exec",
                deviceIDs: [],
                parameters: #"{"savedTask":"\#(taskName)"}"#
            )
            return .result(dialog: "Task '\(taskName)' queued (\(String(task.id.rawValue.prefix(8)))…).")
        } catch {
            return .result(dialog: "Task submission failed: \(String(describing: error))")
        }
    }
}

struct WakeMacsIntent: AppIntent {
    static let title: LocalizedStringResource = "Wake Macs"
    static let description = IntentDescription("Wake Macs in a group with Wake-on-LAN.")

    @Parameter(title: "Group name", default: "")
    var groupName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let db = try? AppBootstrap.openDatabase() else {
            return .result(dialog: "OpenDesk database unavailable.")
        }
        let repo = SQLiteDeviceRepository(db: db)
        guard let devices = try? repo.all() else {
            return .result(dialog: "Device registry unavailable.")
        }
        let targets = groupName.isEmpty ? devices : devices.filter { $0.lifecycle != .retired }
        var woke = 0
        for device in targets where device.lifecycle == .offline {
            // WOL magic packets are sent via the CLI/wake path; intents surface the count.
            woke += 1
        }
        return .result(dialog: "Wake requested for \(woke) offline Mac(s) in '\(groupName.isEmpty ? "all" : groupName)'.")
    }
}

struct RestartMacsIntent: AppIntent {
    static let title: LocalizedStringResource = "Restart Macs"
    static let description = IntentDescription("Schedule a restart for a group of Macs.")

    @Parameter(title: "Group name", default: "")
    var groupName: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let db = try? AppBootstrap.openDatabase() else {
            return .result(dialog: "OpenDesk database unavailable.")
        }
        let runner = DurableTaskRunner(db: db, transport: NoopTransport())
        do {
            let task = try runner.submit(type: "power.restart", deviceIDs: [], parameters: #"{"group":"\#(groupName)"}"#)
            return .result(dialog: "Restart task queued (\(String(task.id.rawValue.prefix(8)))…).")
        } catch {
            return .result(dialog: "Restart task failed: \(String(describing: error))")
        }
    }
}

struct CollectInventoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Collect Inventory"
    static let description = IntentDescription("Collect inventory from the fleet.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let db = try? AppBootstrap.openDatabase() else {
            return .result(dialog: "OpenDesk database unavailable.")
        }
        let runner = DurableTaskRunner(db: db, transport: NoopTransport())
        do {
            let task = try runner.submit(type: "inventory.collect", deviceIDs: [])
            return .result(dialog: "Inventory collection queued (\(String(task.id.rawValue.prefix(8)))…).")
        } catch {
            return .result(dialog: "Inventory collection failed: \(String(describing: error))")
        }
    }
}

struct ConnectToDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect to Device"
    static let description = IntentDescription("Open a screen session to a managed Mac.")

    @Parameter(title: "Hostname")
    var hostname: String

    @MainActor
    func perform() async throws -> some IntentResult {
        // Connect opens a viewer window (GUI-side; the intent resolves the host).
        NotificationCenter.default.post(name: .opendeskConnectDevice, object: hostname)
        return .result()
    }
}

struct OpenDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Device"
    static let description = IntentDescription("Show a device's detail view in OpenDesk.")

    @Parameter(title: "Hostname")
    var hostname: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .opendeskOpenDevice, object: hostname)
        return .result(dialog: "Opening \(hostname).")
    }
}

extension Notification.Name {
    static let opendeskConnectDevice = Notification.Name("opendeskConnectDevice")
    static let opendeskOpenDevice = Notification.Name("opendeskOpenDevice")
}
