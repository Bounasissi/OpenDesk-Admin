import Foundation
import OpenDeskCore

extension String {
    /// Left-justify to the given width for aligned table output.
    func padding(toWidth width: Int) -> String {
        if count >= width { return self + " " }
        return padding(toLength: width, withPad: " ", startingAt: 0)
    }
}

@main
struct OpenDeskCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let exitCode = run(args: args)
        exit(exitCode)
    }

    static func run(args: [String]) -> Int32 {
        guard let command = args.first else {
            printUsage()
            return 1
        }
        let rest = Array(args.dropFirst())

        switch command {
        case "--help", "-h", "help":
            printUsage()
            return 0
        case "hosts": return handleHosts(rest)
        case "task": return handleTask(rest)
        case "tasks": return handleSavedTasks(rest)
        case "schedule": return handleSchedule(rest)
        case "wake": return handleWake(rest)
        case "inventory": return handleInventory(rest)
        case "observe": return handleObserve(rest)
        case "copy": return handleCopy(rest)
        case "install": return handleInstall(rest)
        default:
            fputs("Unknown command: \(command)\n", stderr)
            printUsage()
            return 1
        }
    }

    static func printUsage() {
        print("""
        opendesk — open-source Mac fleet administration

        USAGE:
            opendesk hosts add <hostname> <username> [--groups lab-1,staff]
            opendesk hosts list
            opendesk hosts remove <hostname>
            opendesk task run --host <hostname> --command "<shell command>"
            opendesk task run --groups <g1,g2> --command "<shell command>"
            opendesk task sleep --host <hostname>
            opendesk tasks add <name> --command "<cmd>" [--timeout 30] [--groups g1]
            opendesk tasks list
            opendesk tasks remove <name>
            opendesk schedule add <name> --task <saved-task> [--groups g1] [--every <sec> | --daily HH:mm]
            opendesk schedule list
            opendesk schedule daemon                 (runs schedules in foreground)
            opendesk schedule run-now <name>
            opendesk schedule remove <name>
            opendesk wake --host <hostname>          (requires --mac registered on host)
            opendesk inventory --local [--export-csv <path>]
            opendesk inventory --host <hostname>
            opendesk observe --host <hostname> [--port 5900] [--password <pw>]
            opendesk copy --host <hostname> --local <path> --remote <path>
            opendesk install --host <hostname> --pkg <path>

        Screen observation requires the client's Screen Sharing (VNC) service.
        Tasks/inventory/distribution require SSH access with admin credentials.
        """)
    }

    // MARK: - hosts

    static func handleHosts(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            fputs("hosts: missing subcommand (add|list|remove)\n", stderr)
            return 1
        }
        let registry = HostRegistry()
        switch sub {
        case "add":
            let rest = Array(args.dropFirst())
            guard rest.count >= 2 else {
                fputs("hosts add: usage: opendesk hosts add <hostname> <username> [--groups g1,g2]\n", stderr)
                return 1
            }
            var groups: [String] = []
            if let gi = rest.firstIndex(of: "--groups"), gi + 1 < rest.count {
                groups = rest[gi + 1].split(separator: ",").map(String.init)
            }
            let host = Host(hostname: rest[0], username: rest[1], groups: groups)
            registry.add(host)
            let groupLabel = groups.isEmpty ? "none" : groups.joined(separator: ", ")
            print("Added host \(host.hostname) (user \(host.username), groups: \(groupLabel))")
            return 0
        case "list":
            let hosts = registry.loadAll()
            if hosts.isEmpty {
                print("No hosts registered. Add one: opendesk hosts add <hostname> <username>")
                return 0
            }
            print("HOSTNAME".padding(toWidth: 28) + "USER".padding(toWidth: 14) + "AUTH".padding(toWidth: 12) + "GROUPS")
            for host in hosts {
                print(host.hostname.padding(toWidth: 28) + host.username.padding(toWidth: 14)
                      + host.authMethod.rawValue.padding(toWidth: 12)
                      + host.groups.joined(separator: ","))
            }
            return 0
        case "remove":
            guard let hostname = args.dropFirst().first else {
                fputs("hosts remove: missing <hostname>\n", stderr)
                return 1
            }
            let matches = registry.loadAll().filter { $0.hostname == hostname }
            for host in matches { registry.remove(id: host.id) }
            print(matches.isEmpty ? "No host named \(hostname)" : "Removed \(matches.count) host(s)")
            return matches.isEmpty ? 1 : 0
        default:
            fputs("hosts: unknown subcommand \(sub)\n", stderr)
            return 1
        }
    }

    // MARK: - task

    static func handleTask(_ args: [String]) -> Int32 {
        guard let sub = args.first, sub == "run" || sub == "sleep" || sub == "restart" || sub == "shutdown" else {
            fputs("task: usage: opendesk task run --host <h> --command \"<cmd>\" | task sleep --host <h>\n", stderr)
            return 1
        }
        let registry = HostRegistry()
        let engine = TaskEngine()

        var command: String
        switch sub {
        case "run":
            guard let cmd = optionValue("--command", in: args) else {
                fputs("task run: missing --command\n", stderr)
                return 1
            }
            command = cmd
        case "sleep": command = PowerTask.sleep
        case "restart": command = PowerTask.restart
        case "shutdown": command = PowerTask.shutdown
        default: return 1
        }

        let hosts = resolveTargets(args: Array(args.dropFirst()), registry: registry)
        guard !hosts.isEmpty else {
            fputs("task: no matching hosts\n", stderr)
            return 1
        }

        let results = engine.runAcrossHosts(command, hosts: hosts)
        printResults(results)
        return results.allSatisfy { $0.succeeded } ? 0 : 2
    }

    // MARK: - saved tasks

    static func handleSavedTasks(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            fputs("tasks: missing subcommand (add|list|remove)\n", stderr)
            return 1
        }
        let store = TaskStore()
        switch sub {
        case "add":
            guard let name = args.dropFirst().first,
                  let command = optionValue("--command", in: args) else {
                fputs("tasks add: usage: opendesk tasks add <name> --command \"<cmd>\" [--timeout 30] [--groups g1,g2]\n", stderr)
                return 1
            }
            let timeout = Int(optionValue("--timeout", in: args) ?? "") ?? 30
            let groups = (optionValue("--groups", in: args) ?? "").split(separator: ",").map(String.init)
            guard store.add(name: name, command: command, timeoutSeconds: timeout, targetGroups: groups) != nil else {
                fputs("tasks add: task named \(name) already exists\n", stderr)
                return 1
            }
            print("Saved task \(name) (v1)")
            return 0
        case "list":
            let tasks = store.loadAll()
            if tasks.isEmpty {
                print("No saved tasks. Add one: opendesk tasks add <name> --command \"<cmd>\"")
                return 0
            }
            for task in tasks {
                print("\(task.name)  v\(task.version)  timeout=\(task.timeoutSeconds)s  groups=\(task.targetGroups.joined(separator: ","))")
                print("  cmd: \(task.command)")
            }
            return 0
        case "remove":
            guard let name = args.dropFirst().first else {
                fputs("tasks remove: missing <name>\n", stderr)
                return 1
            }
            guard let task = store.task(named: name) else {
                fputs("tasks remove: no task named \(name)\n", stderr)
                return 1
            }
            store.remove(id: task.id)
            print("Removed task \(name)")
            return 0
        default:
            fputs("tasks: unknown subcommand \(sub)\n", stderr)
            return 1
        }
    }

    // MARK: - wake

    static func handleWake(_ args: [String]) -> Int32 {
        guard let hostname = optionValue("--host", in: args) else {
            fputs("wake: missing --host\n", stderr)
            return 1
        }
        let registry = HostRegistry()
        guard let host = registry.loadAll().first(where: { $0.hostname == hostname }) else {
            fputs("wake: host \(hostname) not registered\n", stderr)
            return 1
        }
        do {
            try WakeOnLAN.wake(host: host)
            print("Wake-on-LAN magic packet sent to \(host.macAddress ?? "") (\(hostname))")
            return 0
        } catch {
            fputs("wake failed: \(error)\n", stderr)
            return 1
        }
    }

    // MARK: - schedule

    static func handleSchedule(_ args: [String]) -> Int32 {
        guard let sub = args.first else {
            fputs("schedule: missing subcommand (add|list|daemon|run-now|remove)\n", stderr)
            return 1
        }
        let store = ScheduleStore()
        let taskStore = TaskStore()
        switch sub {
        case "add":
            guard let name = args.dropFirst().first,
                  let taskName = optionValue("--task", in: args) else {
                fputs("schedule add: usage: opendesk schedule add <name> --task <saved-task> [--every <sec> | --daily HH:mm]\n", stderr)
                return 1
            }
            let trigger: ScheduleDefinition.Trigger
            if let every = optionValue("--every", in: args), let seconds = Int(every) {
                trigger = .interval(seconds: seconds)
            } else if let daily = optionValue("--daily", in: args),
                      let parts = parseDaily(daily) {
                trigger = parts
            } else {
                fputs("schedule add: specify --every <seconds> or --daily HH:mm\n", stderr)
                return 1
            }
            let groups = (optionValue("--groups", in: args) ?? "").split(separator: ",").map(String.init)
            guard taskStore.task(named: taskName) != nil else {
                fputs("schedule add: no saved task named \(taskName)\n", stderr)
                return 1
            }
            guard store.add(ScheduleDefinition(name: name, taskName: taskName, targetGroups: groups, trigger: trigger)) else {
                fputs("schedule add: schedule named \(name) already exists\n", stderr)
                return 1
            }
            print("Schedule \(name) saved (\(ScheduleMath.describe(trigger)))")
            return 0
        case "list":
            let schedules = store.loadAll()
            if schedules.isEmpty {
                print("No schedules. Add one: opendesk schedule add <name> --task <task> --every <sec>")
                return 0
            }
            for schedule in schedules {
                print("\(schedule.name)  task=\(schedule.taskName)  \(ScheduleMath.describe(schedule.trigger))  groups=\(schedule.targetGroups.joined(separator: ","))  \(schedule.enabled ? "enabled" : "disabled")")
            }
            return 0
        case "daemon":
            let scheduler = TaskScheduler(scheduleStore: store, taskStore: taskStore, hostRegistry: HostRegistry())
            scheduler.onRun = { scheduleName, results in
                let okCount = results.filter(\.succeeded).count
                print("[\(scheduleName)] ran on \(results.count) hosts, \(okCount) succeeded")
            }
            signal(SIGINT) { _ in exit(0) }
            print("Scheduler running — checks every 5s. Ctrl-C to stop.")
            scheduler.start()
            dispatchMain()
            return 0
        case "run-now":
            guard let name = args.dropFirst().first else {
                fputs("schedule run-now: missing <name>\n", stderr)
                return 1
            }
            let scheduler = TaskScheduler(scheduleStore: store, taskStore: taskStore, hostRegistry: HostRegistry())
            guard let results = scheduler.runNow(named: name) else {
                fputs("schedule run-now: no schedule named \(name)\n", stderr)
                return 1
            }
            if results.isEmpty {
                print("No hosts matched the schedule's target groups.")
                return 0
            }
            printResults(results)
            return results.allSatisfy { $0.succeeded } ? 0 : 2
        case "remove":
            guard let name = args.dropFirst().first else {
                fputs("schedule remove: missing <name>\n", stderr)
                return 1
            }
            print(store.remove(named: name) ? "Removed schedule \(name)" : "No schedule named \(name)")
            return 0
        default:
            fputs("schedule: unknown subcommand \(sub)\n", stderr)
            return 1
        }
    }

    static func parseDaily(_ value: String) -> ScheduleDefinition.Trigger? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return .daily(hour: hour, minute: minute)
    }

    // MARK: - inventory

    static func handleInventory(_ args: [String]) -> Int32 {
        let collector = InventoryCollector()
        if args.contains("--local") {
            do {
                let report = try collector.collectLocal()
                printReport(report)
                if let exportPath = optionValue("--export-csv", in: args) {
                    let csv = ReportExporter.reportsCSV([report]) + "\n" + ReportExporter.appsCSV([report])
                    try csv.write(toFile: exportPath, atomically: true, encoding: .utf8)
                    print("Exported report to \(exportPath)")
                }
                return 0
            } catch {
                fputs("inventory failed: \(error)\n", stderr)
                return 1
            }
        }
        if let hostname = optionValue("--host", in: args) {
            let registry = HostRegistry()
            guard let host = registry.loadAll().first(where: { $0.hostname == hostname }) else {
                fputs("inventory: host \(hostname) not registered\n", stderr)
                return 1
            }
            do {
                let report = try collector.collectRemote(host: host)
                printReport(report)
                return 0
            } catch {
                fputs("inventory failed: \(error)\n", stderr)
                return 1
            }
        }
        fputs("inventory: specify --local or --host <hostname>\n", stderr)
        return 1
    }

    // MARK: - observe

    static func handleObserve(_ args: [String]) -> Int32 {
        guard let hostname = optionValue("--host", in: args) else {
            fputs("observe: missing --host\n", stderr)
            return 1
        }
        var host = Host(hostname: hostname, username: "")
        if let port = optionValue("--port", in: args), let p = Int(port) {
            host.screenPort = p
        }
        let password = optionValue("--password", in: args)

        let session = ScreenSession(host: host, mode: .observe)
        do {
            try session.connect(password: password)
            guard let client = session.client else { return 1 }
            print("Connected: \(client.serverName)")
            if let dims = client.dimensions {
                print("Framebuffer: \(dims.width)x\(dims.height)")
            }
            let securityLabel = client.negotiatedSecurity.map { String(describing: $0) } ?? "unknown"
            print("Security: \(securityLabel)")
            print("Handshake OK — pixel streaming begins in GUI phase (Phase 3).")
            session.disconnect()
            return 0
        } catch {
            fputs("observe failed: \(error)\n", stderr)
            return 1
        }
    }

    // MARK: - distribution

    static func handleCopy(_ args: [String]) -> Int32 {
        guard let hostname = optionValue("--host", in: args),
              let local = optionValue("--local", in: args),
              let remote = optionValue("--remote", in: args) else {
            fputs("copy: usage: opendesk copy --host <h> --local <path> --remote <path>\n", stderr)
            return 1
        }
        let registry = HostRegistry()
        guard let host = registry.loadAll().first(where: { $0.hostname == hostname }) else {
            fputs("copy: host \(hostname) not registered\n", stderr)
            return 1
        }
        let result = try? DistributionEngine().copyItem(localPath: local, toHost: host, remotePath: remote)
        if let result {
            printResults([result])
            return result.succeeded ? 0 : 2
        }
        fputs("copy failed\n", stderr)
        return 1
    }

    static func handleInstall(_ args: [String]) -> Int32 {
        guard let hostname = optionValue("--host", in: args),
              let pkg = optionValue("--pkg", in: args) else {
            fputs("install: usage: opendesk install --host <h> --pkg <path>\n", stderr)
            return 1
        }
        let registry = HostRegistry()
        guard let host = registry.loadAll().first(where: { $0.hostname == hostname }) else {
            fputs("install: host \(hostname) not registered\n", stderr)
            return 1
        }
        do {
            let result = try DistributionEngine().installPackage(localPath: pkg, toHost: host)
            printResults([result])
            return result.succeeded ? 0 : 2
        } catch {
            fputs("install failed: \(error)\n", stderr)
            return 1
        }
    }

    // MARK: - helpers

    static func resolveTargets(args: [String], registry: HostRegistry) -> [OpenDeskCore.Host] {
        if let host = optionValue("--host", in: args) {
            let known = registry.loadAll().first { $0.hostname == host }
            return known.map { [$0] } ?? [OpenDeskCore.Host(hostname: host, username: currentUserName())]
        }
        if let groups = optionValue("--groups", in: args) {
            let groupList = groups.split(separator: ",").map(String.init)
            return registry.hosts(inGroups: groupList)
        }
        return registry.loadAll()
    }

    static func currentUserName() -> String {
        NSUserName()
    }

    static func optionValue(_ flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func printResults(_ results: [TaskResult]) {
        for result in results {
            let status = result.succeeded ? "OK" : "FAIL"
            print("[\(status)] \(result.host) (\(result.durationMs)ms)")
            if !result.stdout.isEmpty { print("  stdout: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))") }
            if !result.stderr.isEmpty { print("  stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))") }
            if let err = result.errorDescription { print("  error: \(err)") }
        }
    }

    static func printReport(_ report: MachineReport) {
        print("Hostname:    \(report.hostname)")
        print("Model:       \(report.modelName)")
        print("Arch:        \(report.chipArchitecture)")
        print("macOS:       \(report.osVersion)")
        print("Serial:      \(report.serialNumber)")
        print("Memory (MB): \(report.totalMemoryMB)")
        print("Apps:        \(report.installedApps.count)")
        for app in report.installedApps.prefix(10) {
            print("  - \(app.name) \(app.version)")
        }
        if report.installedApps.count > 10 {
            print("  … and \(report.installedApps.count - 10) more")
        }
    }
}
