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
