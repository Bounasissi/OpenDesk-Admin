import SwiftUI
import OpenDeskCore

/// Root dashboard: sidebar roster + detail pane (Tasks / Inventory / Screen).
struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationSplitView {
            List { Text("sidebar test") }
        } detail: {
            Text("detail test")
        }
        .onAppear {
            viewModel.reloadHosts()
        }
    }
}

// MARK: - Sidebar

struct RosterSidebar: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        List(selection: $viewModel.selectedHostname) {
            Section("Roster") {
                ForEach(viewModel.hosts) { host in
                    Label(host.hostname, systemImage: "desktopcomputer")
                        .tag(host.hostname)
                }
            }
            if !viewModel.discoveredServices.isEmpty {
                Section("Discovered (Bonjour)") {
                    ForEach(viewModel.discoveredServices) { service in
                        Label(service.name, systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AddHostBar { hostname, username, groups in
                viewModel.addHost(hostname: hostname, username: username, groups: groups)
            }
            .padding(8)
        }
    }
}

struct AddHostBar: View {
    @State private var hostname = ""
    @State private var username = ""
    @State private var groups = ""
    var onAdd: (String, String, [String]) -> Void

    var body: some View {
        VStack(spacing: 6) {
            TextField("Hostname", text: $hostname)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            TextField("Groups (comma-separated)", text: $groups)
                .textFieldStyle(.roundedBorder)
            Button("Add Host") {
                onAdd(hostname, username, groups.split(separator: ",").map(String.init).map { $0.trimmingCharacters(in: .whitespaces) })
                hostname = ""
                username = ""
                groups = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(hostname.isEmpty || username.isEmpty)
        }
    }
}

// MARK: - Detail

struct HostDetailView: View {
    let host: OpenDeskCore.Host
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        TabView {
            TaskRunnerView(host: host, viewModel: viewModel)
                .tabItem { Label("Tasks", systemImage: "terminal") }
            InventoryView(host: host, viewModel: viewModel)
                .tabItem { Label("Inventory", systemImage: "doc.text.magnifyingglass") }
            ScreenConnectView(host: host)
                .tabItem { Label("Screen", systemImage: "rectangle.on.rectangle") }
        }
        .padding()
    }
}

// MARK: - Task runner

struct TaskRunnerView: View {
    let host: OpenDeskCore.Host
    @ObservedObject var viewModel: DashboardViewModel
    @State private var command = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Shell command, e.g. sw_vers", text: $command)
                    .textFieldStyle(.roundedBorder)
                Button("Run") {
                    viewModel.runCommand(command, on: host)
                }
                .buttonStyle(.borderedProminent)
                .disabled(command.isEmpty || viewModel.isRunning)
                if viewModel.isRunning { ProgressView().controlSize(.small) }
            }
            ScrollView {
                Text(viewModel.lastOutput.isEmpty ? "No output yet." : viewModel.lastOutput)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding()
    }
}

// MARK: - Inventory

struct InventoryView: View {
    let host: OpenDeskCore.Host
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Collect Report") { viewModel.collectInventory(for: host) }
                    .disabled(viewModel.isLoadingInventory)
                if viewModel.isLoadingInventory { ProgressView().controlSize(.small) }
            }
            if let report = viewModel.inventoryReport {
                List {
                    LabeledRow("Hostname", report.hostname)
                    LabeledRow("Model", report.modelName)
                    LabeledRow("Architecture", report.chipArchitecture)
                    LabeledRow("macOS", report.osVersion)
                    LabeledRow("Serial", report.serialNumber)
                    LabeledRow("Memory (MB)", String(report.totalMemoryMB))
                    Section("Installed Apps (\(report.installedApps.count))") {
                        ForEach(report.installedApps, id: \.path) { app in
                            HStack {
                                Text(app.name)
                                Spacer()
                                Text(app.version).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("No report collected yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Screen

struct ScreenConnectView: View {
    let host: OpenDeskCore.Host
    @State private var status: String = "Idle."
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Observe \(host.hostname) (VNC port \(host.screenPort))")
                .font(.headline)
            Button("Connect & Test Handshake") {
                isConnecting = true
                let target = host
                Task.detached {
                    let result = await ScreenConnectHelper.handshakeResult(target)
                    await MainActor.run {
                        status = result
                        isConnecting = false
                    }
                }
            }
            .disabled(isConnecting)
            Text(status)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Full pixel streaming opens in the Screen Viewer window once auth is configured for the target host.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

enum ScreenConnectHelper {
    static func handshakeResult(_ host: OpenDeskCore.Host) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let session = ScreenSession(host: host, mode: .observe)
                do {
                    try session.connect(password: nil)
                    let name = session.client?.serverName ?? ""
                    let dims = session.client?.dimensions
                    session.disconnect()
                    continuation.resume(returning: "Connected: \(name) \(dims.map { "\($0.width)x\($0.height)" } ?? "")")
                } catch {
                    session.disconnect()
                    continuation.resume(returning: "Connection failed: \(error)")
                }
            }
        }
    }
}

// MARK: - View model

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var hosts: [OpenDeskCore.Host] = []
    @Published var selectedHostname: String?
    @Published var discoveredServices: [FleetDiscovery.DiscoveredService] = []
    @Published var isRunning = false
    @Published var lastOutput = ""
    @Published var isLoadingInventory = false
    @Published var inventoryReport: OpenDeskCore.MachineReport?

    private let registry = HostRegistry()
    private let engine = TaskEngine()
    private let discovery = FleetDiscovery()

    func reloadHosts() {
        hosts = registry.loadAll()
        if selectedHostname == nil, let first = hosts.first {
            selectedHostname = first.hostname
        }
        discovery.start { [weak self] services in
            self?.discoveredServices = services
        }
    }

    var selectedHost: OpenDeskCore.Host? {
        hosts.first { $0.hostname == selectedHostname }
    }

    func addHost(hostname: String, username: String, groups: [String]) {
        registry.add(OpenDeskCore.Host(hostname: hostname, username: username, groups: groups))
        reloadHosts()
    }

    func runCommand(_ command: String, on host: OpenDeskCore.Host) {
        isRunning = true
        lastOutput = ""
        Task.detached {
            let result = self.engine.runOnHost(command, host: host)
            await MainActor.run {
                self.isRunning = false
                self.lastOutput = result.succeeded
                    ? "[OK] \(result.host)\n\(result.stdout)"
                    : "[FAIL] \(result.host)\n\(result.errorDescription ?? result.stderr)"
            }
        }
    }

    func collectInventory(for host: OpenDeskCore.Host) {
        isLoadingInventory = true
        Task.detached {
            let collector = InventoryCollector()
            let report: OpenDeskCore.MachineReport?
            do {
                report = try collector.collectRemote(host: host)
            } catch {
                report = nil
            }
            await MainActor.run {
                self.isLoadingInventory = false
                self.inventoryReport = report
            }
        }
    }
}
