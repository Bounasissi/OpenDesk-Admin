import ArgumentParser
import OpenDeskCore
import Foundation

@main
struct OpenDesk: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "opendesk",
        abstract: "OpenDesk Admin — open-source, API-first macOS fleet administration.",
        version: "0.1.0",
        subcommands: [
            DiscoverCommand.self,
            DevicesCommand.self,
            ExecCommand.self,
            CopyCommand.self,
            InstallCommand.self,
            InventoryCommand.self,
            GroupsCommand.self,
            PowerCommand.self,
            ScheduleCommand.self,
            TasksCommand.self,
            AuditCommand.self,
        ]
    )
}

// MARK: - Shared bootstrap

enum Bootstrap {
    /// Default database location: ~/Library/Application Support/OpenDeskAdmin/opendesk.db
    static func defaultDBPath() -> String {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenDeskAdmin", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("opendesk.db").path
    }

    static func registry(path: String?) throws -> DeviceRegistry {
        let db = try SQLiteDatabase(path: path ?? defaultDBPath())
        guard let schema = DeviceRegistry.bundledSchema() else {
            throw ValidationError("Bundled schema.sql missing from OpenDeskCore resources.")
        }
        return try DeviceRegistry(db: db, schema: schema)
    }
}

// MARK: - discover

struct DiscoverCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Discover Macs via Bonjour and/or CIDR scan; persist to registry."
    )

    @Option(name: .shortAndLong, help: "CIDR range to scan, e.g. 192.168.1.0/24")
    var cidr: String?

    @Flag(help: "Skip Bonjour browse")
    var noBonjour = false

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    func run() throws {
        let registry = try Bootstrap.registry(path: db)
        var sources: [DiscoverySource] = []
        if !noBonjour { sources.append(BonjourDiscovery()) }
        if let cidr { sources.append(CIDRScanner(cidr: cidr)) }
        if sources.isEmpty {
            throw ValidationError("Provide --cidr or omit --no-bonjour to use Bonjour.")
        }

        let service = DiscoveryService(registry: registry, sources: sources)
        let results = try runAsync { try await service.discover() }

        if results.isEmpty {
            print("No devices discovered.")
        } else {
            print("Discovered \(results.count) device(s):")
            for r in results {
                let flags = [r.rfbAvailable ? "rfb" : nil, r.sshAvailable ? "ssh" : nil].compactMap { $0 }.joined(separator: "+")
                print("  \(r.hostname)  [\(flags.isEmpty ? "no services" : flags)]  ips: \(r.ips.joined(separator: ","))")
            }
        }
        try registry.appendAudit(AuditEventRecord(action: "discovery.run", payloadJSON: "{\"count\":\(results.count)}"))
    }
}

// MARK: - devices

struct DevicesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List registered devices."
    )

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    @Option(name: .shortAndLong, help: "Output format: table or json")
    var format: String = "table"

    func run() throws {
        let registry = try Bootstrap.registry(path: db)
        let devices = try registry.devices()
        if format == "json" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(devices)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else {
            if devices.isEmpty {
                print("No devices registered. Run `opendesk discover` first.")
            } else {
                print("\(devices.count) device(s):")
                for d in devices {
                    let flags = [d.rfbAvailable ? "rfb" : nil, d.sshAvailable ? "ssh" : nil, d.online ? "online" : "offline"].compactMap { $0 }.joined(separator: "+")
                    print("  \(d.id.uuidString.prefix(8))  \(d.hostname)  [\(flags)]")
                }
            }
        }
    }
}

// MARK: - exec

struct ExecCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a command on target devices via SSH."
    )

    @Argument(help: "Command to execute")
    var command: String

    @Option(name: .customLong("devices"), help: "Target device IDs or hostnames (comma-separated)")
    var devices: String?

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    @Flag(help: "Run as root via sudo")
    var root = false

    func run() throws {
        let registry = try Bootstrap.registry(path: db)
        let all = try registry.devices()

        let targets: [DeviceRecord]
        if let devices, !devices.isEmpty {
            let wanted = Set(devices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            targets = all.filter { wanted.contains(String($0.id.uuidString.prefix(8))) || wanted.contains($0.hostname) }
            guard !targets.isEmpty else {
                throw ValidationError("No matching devices for '\(devices)'. Run `opendesk devices` to list.")
            }
        } else {
            targets = all.filter { $0.sshAvailable }
            guard !targets.isEmpty else {
                throw ValidationError("No SSH-capable devices registered. Run `opendesk discover` first.")
            }
        }

        let engine = TaskEngine(registry: registry, ssh: SSHTransport())
        let task = try engine.submit(
            type: .executeCommand,
            targets: targets.map { $0.id },
            parameters: ["command": command]
        )
        print("Task \(task.id.uuidString.prefix(8)) queued on \(targets.count) device(s)...")
        let results = try runAsync { try await engine.execute(taskID: task.id) }

        for r in results {
            let device = targets.first { $0.id == r.deviceID }
            let name = device?.hostname ?? String(r.deviceID.uuidString.prefix(8))
            let status = r.status
            if status == "success" {
                let resultJSON = r.resultJSON ?? "{}"
                let stdout = Self.extract(resultJSON, key: "stdout")
                print("  \(name): success")
                if !stdout.isEmpty { print("    \(stdout.replacingOccurrences(of: "\n", with: "\n    "))") }
            } else {
                print("  \(name): \(status) — \(r.error ?? "unknown error")")
            }
        }
    }

    static func extract(_ json: String, key: String) -> String {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = dict[key] as? String else { return "" }
        return value
    }
}

// MARK: - copy

struct CopyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Push a file to a remote device via SFTP (checksum-verified)."
    )

    @Argument(help: "Local file path")
    var source: String

    @Argument(help: "Remote destination path")
    var destination: String

    @Option(name: .customLong("devices"), help: "Target device IDs or hostnames (comma-separated)")
    var devices: String?

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    func run() throws {
        let registry = try Bootstrap.registry(path: db)
        let targets = try resolveTargets(registry, devices)
        let engine = TaskEngine(registry: registry, ssh: SSHTransport())
        let task = try engine.submit(type: .copyFiles, targets: targets.map { $0.id },
                                     parameters: ["source": source, "destination": destination])
        print("Task \(task.id.uuidString.prefix(8)) queued (copy) on \(targets.count) device(s)...")

        let transfers = TransferEngine(ssh: SSHTransport())
        let results = try runAsync { () -> [String] in
            var out: [String] = []
            for device in targets {
                let host = SSHHost(hostname: device.ips.first ?? device.hostname)
                do {
                    let r = try await transfers.push(localPath: source, toRemote: destination, on: host)
                    out.append("  \(device.hostname): \(r.exitCode == 0 ? "success" : "failed") (checksum \(r.checksumRemote ?? "n/a"))")
                } catch TransferError.checksumMismatch(let local, let remote) {
                    out.append("  \(device.hostname): CHECKSUM MISMATCH local=\(local.prefix(12)) remote=\(remote.prefix(12))")
                } catch {
                    out.append("  \(device.hostname): failed — \(error)")
                }
            }
            return out
        }
        results.forEach { print($0) }
        try registry.updateTaskStatus(taskID: task.id, status: "success")
    }
}

// MARK: - install

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deploy a .pkg to devices: checksum -> SFTP stage -> installer -> cleanup."
    )

    @Argument(help: "Local .pkg path")
    var package: String

    @Option(name: .customLong("devices"), help: "Target device IDs or hostnames (comma-separated)")
    var devices: String?

    @Option(help: "none | restart")
    var restartPolicy: String = "none"

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    func run() throws {
        guard restartPolicy == "none" || restartPolicy == "restart" else {
            throw ValidationError("restartPolicy must be 'none' or 'restart'")
        }
        let registry = try Bootstrap.registry(path: db)
        let targets = try resolveTargets(registry, devices)
        let engine = TaskEngine(registry: registry, ssh: SSHTransport())
        let task = try engine.submit(type: .installPackage, targets: targets.map { $0.id },
                                     parameters: ["package": package, "restart_policy": restartPolicy])
        print("Task \(task.id.uuidString.prefix(8)) queued (install) on \(targets.count) device(s)...")

        let transfers = TransferEngine(ssh: SSHTransport())
        let results = try runAsync { () -> [String] in
            var out: [String] = []
            for device in targets {
                let host = SSHHost(hostname: device.ips.first ?? device.hostname)
                do {
                    let r = try await transfers.installPackage(packagePath: package, on: host, restartPolicy: restartPolicy)
                    out.append("  \(device.hostname): installer exit \(r.exitCode) \(r.exitCode == 0 ? "(success)" : "(FAILED)")")
                } catch {
                    out.append("  \(device.hostname): failed — \(error)")
                }
            }
            return out
        }
        results.forEach { print($0) }
        try registry.updateTaskStatus(taskID: task.id, status: "success")
    }
}

// MARK: - inventory

struct InventoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Collect hardware/software/network inventory from devices."
    )

    @Option(name: .customLong("devices"), help: "Target device IDs or hostnames (comma-separated)")
    var devices: String?

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    @Flag(help: "Print JSON snapshots to stdout")
    var json = false

    func run() throws {
        let registry = try Bootstrap.registry(path: db)
        let targets = try resolveTargets(registry, devices)
        let engine = TaskEngine(registry: registry, ssh: SSHTransport())
        let task = try engine.submit(type: .inventoryCollect, targets: targets.map { $0.id })
        print("Task \(task.id.uuidString.prefix(8)) queued (inventory) on \(targets.count) device(s)...")

        let collector = InventoryCollector(ssh: SSHTransport())
        let snapshots = try runAsync { () -> [InventorySnapshot] in
            var out: [InventorySnapshot] = []
            for device in targets {
                let host = SSHHost(hostname: device.ips.first ?? device.hostname)
                let snap = await collector.collect(host: host, deviceID: device.id.uuidString)
                out.append(snap)
                if let errs = snap.errors, !errs.isEmpty {
                    print("  \(device.hostname): partial — errors: \(errs.keys.joined(separator: ","))")
                } else {
                    print("  \(device.hostname): collected")
                }
            }
            return out
        }
        try registry.updateTaskStatus(taskID: task.id, status: "success")

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshots)
            print(String(data: data, encoding: .utf8) ?? "[]")
        }
    }
}

// MARK: - target resolution helper

func resolveTargets(_ registry: DeviceRegistry, _ devices: String?) throws -> [DeviceRecord] {
    let all = try registry.devices()
    if let devices, !devices.isEmpty {
        let wanted = Set(devices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let matched = all.filter { wanted.contains(String($0.id.uuidString.prefix(8))) || wanted.contains($0.hostname) }
        guard !matched.isEmpty else {
            throw ValidationError("No matching devices for '\(devices)'. Run `opendesk devices-command` to list.")
        }
        return matched
    }
    let sshCapable = all.filter { $0.sshAvailable }
    guard !sshCapable.isEmpty else {
        throw ValidationError("No SSH-capable devices registered. Run `opendesk discover-command` first.")
    }
    return sshCapable
}

// MARK: - groups

struct GroupsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage device groups and smart groups.",
        subcommands: [GroupsCreate.self, GroupsList.self, GroupsAdd.self, GroupsSmart.self, GroupsShow.self]
    )

    struct GroupsCreate: ParsableCommand {
        @Argument(help: "Group name")
        var name: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let id = try registry.createGroup(name: name)
            try registry.appendAudit(AuditEventRecord(action: "group.create", target: name))
            print("Created group '\(name)' (\(id.uuidString.prefix(8)))")
        }
    }

    struct GroupsList: ParsableCommand {
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let groups = try registry.db.query("SELECT id, name FROM groups ORDER BY name") { r in
                (id: r.text(0) ?? "", name: r.text(1) ?? "")
            }
            let smart = try registry.db.query("SELECT id, name, predicate_json FROM smart_groups ORDER BY name") { r in
                (id: r.text(0) ?? "", name: r.text(1) ?? "", predicate: r.text(2) ?? "")
            }
            if groups.isEmpty && smart.isEmpty { print("No groups."); return }
            for g in groups { print("  \(String(g.id.prefix(8)))  [static]  \(g.name)") }
            for g in smart { print("  \(String(g.id.prefix(8)))  [smart]   \(g.name)  \(g.predicate)") }
        }
    }

    struct GroupsAdd: ParsableCommand {
        @Argument(help: "Group name")
        var group: String
        @Argument(help: "Device hostname or ID prefix")
        var device: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let groups = try registry.db.query("SELECT id FROM groups WHERE name = ? LIMIT 1", bindings: [.text(group)]) { r in
                UUID(uuidString: r.text(0) ?? "")
            }.compactMap { $0 }
            guard let groupID = groups.first else {
                throw ValidationError("Group '\(group)' not found. Create it first.")
            }
            let all = try registry.devices()
            guard let device = all.first(where: { $0.hostname == device || String($0.id.uuidString.prefix(8)) == device }) else {
                throw ValidationError("Device '\(device)' not found.")
            }
            try registry.addDevice(device.id, toGroup: groupID)
            print("Added \(device.hostname) to \(group)")
        }
    }

    struct GroupsSmart: ParsableCommand {
        @Argument(help: "Smart group name")
        var name: String
        @Argument(help: "Predicate JSON, e.g. '{\"op\":\"AND\",\"clauses\":[{\"field\":\"architecture\",\"op\":\"=\",\"value\":\"arm64\"}]}'")
        var predicate: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            _ = try SmartGroupPredicate.decode(predicate) // validate
            let registry = try Bootstrap.registry(path: db)
            let id = UUID()
            try registry.db.run("INSERT INTO smart_groups (id, name, predicate_json) VALUES (?, ?, ?)",
                                bindings: [.text(id.uuidString), .text(name), .text(predicate)])
            try registry.appendAudit(AuditEventRecord(action: "smart_group.create", target: name))
            print("Created smart group '\(name)' (\(id.uuidString.prefix(8)))")
        }
    }

    struct GroupsShow: ParsableCommand {
        @Argument(help: "Group name (static or smart)")
        var group: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            // Smart group: evaluate predicate.
            let smart = try registry.db.query("SELECT id, predicate_json FROM smart_groups WHERE name = ? LIMIT 1", bindings: [.text(group)]) { r in
                (id: r.text(0) ?? "", predicate: r.text(1) ?? "")
            }
            if let s = smart.first {
                let predicate = try SmartGroupPredicate.decode(s.predicate)
                let members = try registry.devices().filter { predicate.matches($0) }
                print("Smart group '\(group)' matches \(members.count) device(s):")
                members.forEach { print("  \($0.hostname) [\($0.architecture ?? "?") os \($0.osVersion ?? "?")]") }
                return
            }
            // Static group.
            let groups = try registry.db.query("SELECT id FROM groups WHERE name = ? LIMIT 1", bindings: [.text(group)]) { r in
                UUID(uuidString: r.text(0) ?? "")
            }.compactMap { $0 }
            guard let groupID = groups.first else {
                throw ValidationError("Group '\(group)' not found.")
            }
            let members = try registry.groupMembers(group: groupID)
            print("Group '\(group)' contains \(members.count) device(s):")
            members.forEach { print("  \($0.hostname)") }
        }
    }
}

// MARK: - power

struct PowerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Power management: wake (WoL), sleep, restart, shutdown, logout.",
        subcommands: [PowerWake.self, PowerSleep.self, PowerRestart.self, PowerShutdown.self, PowerLogout.self]
    )

    struct PowerWake: ParsableCommand {
        @Argument(help: "Target MAC address (AA:BB:CC:DD:EE:FF)")
        var mac: String
        @Option(help: "Broadcast address")
        var broadcast: String = "255.255.255.255"

        func run() throws {
            let controller = PowerController(ssh: SSHTransport())
            try controller.wake(mac: mac, broadcast: broadcast)
            try Bootstrap.registry(path: nil).appendAudit(AuditEventRecord(action: "power.wake", target: mac))
            print("Wake-on-LAN packet sent to \(mac) via \(broadcast)")
        }
    }

    struct PowerSleep: ParsableCommand {
        @Argument(help: "Device hostname or ID prefix")
        var device: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let targets = try resolveTargets(registry, device)
            let controller = PowerController(ssh: SSHTransport())
            for d in targets {
                let host = SSHHost(hostname: d.ips.first ?? d.hostname)
                let r = try runAsync { try await controller.sleep(on: host) }
                print("\(d.hostname): exit \(r.exitCode)")
            }
            try registry.appendAudit(AuditEventRecord(action: "power.sleep", target: device))
        }
    }

    struct PowerRestart: ParsableCommand {
        @Argument(help: "Device hostname or ID prefix")
        var device: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let targets = try resolveTargets(registry, device)
            let controller = PowerController(ssh: SSHTransport())
            for d in targets {
                let host = SSHHost(hostname: d.ips.first ?? d.hostname)
                let r = try runAsync { try await controller.restart(on: host) }
                print("\(d.hostname): exit \(r.exitCode)")
            }
            try registry.appendAudit(AuditEventRecord(action: "power.restart", target: device))
        }
    }

    struct PowerShutdown: ParsableCommand {
        @Argument(help: "Device hostname or ID prefix")
        var device: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let targets = try resolveTargets(registry, device)
            let controller = PowerController(ssh: SSHTransport())
            for d in targets {
                let host = SSHHost(hostname: d.ips.first ?? d.hostname)
                let r = try runAsync { try await controller.shutdown(on: host) }
                print("\(d.hostname): exit \(r.exitCode)")
            }
            try registry.appendAudit(AuditEventRecord(action: "power.shutdown", target: device))
        }
    }

    struct PowerLogout: ParsableCommand {
        @Argument(help: "Device hostname or ID prefix")
        var device: String
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let targets = try resolveTargets(registry, device)
            let controller = PowerController(ssh: SSHTransport())
            for d in targets {
                let host = SSHHost(hostname: d.ips.first ?? d.hostname)
                let r = try runAsync { try await controller.logoutUser(on: host) }
                print("\(d.hostname): exit \(r.exitCode)")
            }
            try registry.appendAudit(AuditEventRecord(action: "power.logout", target: device))
        }
    }
}

// MARK: - schedule

struct ScheduleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage task schedules (RRULE / one-shot / on-reconnect).",
        subcommands: [ScheduleCreate.self, ScheduleList.self]
    )

    struct ScheduleCreate: ParsableCommand {
        @Option(help: "RRULE, e.g. 'FREQ=WEEKLY;BYDAY=FR;BYHOUR=22'")
        var rrule: String?
        @Option(help: "One-shot ISO8601 run time, e.g. 2026-09-14T09:00:00Z")
        var at: String?
        @Flag(help: "Run when host reconnects")
        var onReconnect = false
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            guard rrule != nil || at != nil || onReconnect else {
                throw ValidationError("Provide --rrule, --at, or --on-reconnect.")
            }
            if let rrule { _ = try Scheduler.parseRRULE(rrule) }
            let runAt: Date? = at.map { dateStr -> Date in
                let formats = [DeviceRegistry.isoFormatter, DeviceRegistry.isoFormatterNoFraction]
                for f in formats {
                    if let d = try? f.date(from: dateStr) { return d }
                }
                fatalError("Invalid --at date format: \(dateStr)")
            }
            let registry = try Bootstrap.registry(path: db)
            let scheduler = Scheduler(registry: registry)
            let s = try scheduler.createSchedule(ScheduleRecord(rrule: rrule, runAt: runAt, onReconnect: onReconnect))
            try registry.appendAudit(AuditEventRecord(action: "schedule.create", target: s.id.uuidString))
            print("Created schedule \(s.id.uuidString.prefix(8))")
        }
    }

    struct ScheduleList: ParsableCommand {
        @Option(name: .shortAndLong, help: "Database path")
        var db: String?

        func run() throws {
            let registry = try Bootstrap.registry(path: db)
            let scheduler = Scheduler(registry: registry)
            let all = try scheduler.schedules()
            if all.isEmpty { print("No schedules."); return }
            for s in all {
                var desc = s.id.uuidString.prefix(8).description
                if let rrule = s.rrule { desc += "  rrule: \(rrule)" }
                if let runAt = s.runAt { desc += "  at: \(runAt)" }
                if s.onReconnect { desc += "  on-reconnect" }
                print("  \(desc)")
            }
        }
    }
}

// MARK: - tasks

struct TasksCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List tasks and per-target results."
    )

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    func run() throws {
        let registry = try Bootstrap.registry(path: db)
        let tasks = try registry.tasks()
        if tasks.isEmpty {
            print("No tasks recorded.")
            return
        }
        for t in tasks {
            print("\(t.id.uuidString.prefix(8))  \(t.type)  \(t.status)  \(t.createdAt)")
            for target in try registry.taskTargets(taskID: t.id) {
                print("    \(target.deviceID.uuidString.prefix(8))  \(target.status)\(target.error.map { " — \($0)" } ?? "")")
            }
        }
    }
}

// MARK: - audit

struct AuditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the audit log."
    )

    @Option(name: .shortAndLong, help: "Database path")
    var db: String?

    @Option(name: .shortAndLong, help: "Max entries")
    var limit: Int = 20

    func run() throws {
        let registry = try Bootstrap.registry(path: db)
        let events = try registry.auditEvents(limit: limit)
        if events.isEmpty {
            print("No audit events.")
            return
        }
        for e in events {
            print("\(e.at)  \(e.action)  \(e.target ?? "-")")
        }
    }
}

// MARK: - async bridge

func runAsync<T>(_ body: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?
    Task.detached {
        do { result = .success(try await body()) }
        catch { result = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    switch result! {
    case .success(let value): return value
    case .failure(let error): throw error
    }
}
