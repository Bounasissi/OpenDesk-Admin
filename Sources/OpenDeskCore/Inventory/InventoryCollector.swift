import Foundation

/// Collected report for a single machine (ARD "System Overview Report" equivalent).
public struct MachineReport: Codable, Sendable {
    public struct AppEntry: Codable, Hashable, Sendable {
        public var name: String
        public var version: String
        public var path: String
    }

    public var hostname: String
    public var modelName: String
    public var chipArchitecture: String
    public var osVersion: String
    public var serialNumber: String
    public var totalMemoryMB: Int
    public var uptimeSeconds: Int?
    public var installedApps: [AppEntry]
    public var collectedAt: Date
}

/// Collects hardware and software inventory from a machine.
/// `local` mode runs commands directly; `remote` mode runs them over SSH.
public final class InventoryCollector: @unchecked Sendable {
    public init() {}

    /// Collect a full report from the local machine.
    public func collectLocal() throws -> MachineReport {
        let hostname = try runLocal("hostname").trimmingCharacters(in: .whitespacesAndNewlines)
        let swVersVersion = try runLocal("sw_vers -productVersion").trimmingCharacters(in: .whitespacesAndNewlines)
        let arch = try runLocal("uname -m").trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (try? runLocal("system_profiler SPHardwareDataType -json")) ?? "{}"
        let modelName = parseModelName(from: model)
        let serial = parseSerial(from: model)
        let memoryMB = parseMemoryMB(from: model)
        let uptimeSeconds = localUptimeSeconds()
        let apps = collectLocalApps()

        return MachineReport(
            hostname: hostname,
            modelName: modelName,
            chipArchitecture: arch,
            osVersion: swVersVersion,
            serialNumber: serial,
            totalMemoryMB: memoryMB,
            uptimeSeconds: uptimeSeconds,
            installedApps: apps,
            collectedAt: Date()
        )
    }

    /// Collect a full report from a remote host over SSH.
    public func collectRemote(host: Host) throws -> MachineReport {
        let transport = SSHTransport(host: host)
        let hostname = try transport.run(command: "hostname").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let osVersion = try transport.run(command: "sw_vers -productVersion").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let arch = try transport.run(command: "uname -m").stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let hardwareJSON = (try? transport.run(command: "system_profiler SPHardwareDataType -json").stdout) ?? "{}"
        let apps = try collectRemoteApps(host: host)

        return MachineReport(
            hostname: hostname,
            modelName: parseModelName(from: hardwareJSON),
            chipArchitecture: arch,
            osVersion: osVersion,
            serialNumber: parseSerial(from: hardwareJSON),
            totalMemoryMB: parseMemoryMB(from: hardwareJSON),
            uptimeSeconds: nil,
            installedApps: apps,
            collectedAt: Date()
        )
    }

    // MARK: - App scanning

    private func collectLocalApps() -> [MachineReport.AppEntry] {
        let appDirs = ["/Applications", "/System/Applications"]
        var apps: [MachineReport.AppEntry] = []
        let fm = FileManager.default
        for dir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in contents where entry.hasSuffix(".app") {
                let name = (entry as NSString).deletingPathExtension
                let path = "\(dir)/\(entry)"
                let version = readBundleVersion(bundlePath: path)
                apps.append(MachineReport.AppEntry(name: name, version: version, path: path))
            }
        }
        return apps.sorted { $0.name < $1.name }
    }

    private func collectRemoteApps(host: Host) throws -> [MachineReport.AppEntry] {
        let transport = SSHTransport(host: host)
        let result = try transport.run(
            command: "find /Applications -maxdepth 1 -name '*.app' -print0 2>/dev/null | xargs -0 -I{} sh -c 'echo \"{}|$(defaults read \"{}_CFBundleVersion\" 2>/dev/null || echo unknown)\"'",
            timeoutSeconds: 60
        )
        return result.stdout
            .split(separator: "\n")
            .compactMap { line -> MachineReport.AppEntry? in
                let parts = line.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let path = String(parts[0])
                let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                return MachineReport.AppEntry(name: name, version: String(parts[1]).trimmingCharacters(in: .whitespaces), path: path)
            }
            .sorted { $0.name < $1.name }
    }

    private func readBundleVersion(bundlePath: String) -> String {
        let plistPath = bundlePath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any],
              let version = dict["CFBundleShortVersionString"] as? String else {
            return "unknown"
        }
        return version
    }

    // MARK: - system_profiler JSON parsing

    func parseModelName(from json: String) -> String {
        parseHardwareField(from: json, field: "machine_name")
            ?? parseHardwareField(from: json, field: "machine_model")
            ?? "unknown"
    }

    func parseSerial(from json: String) -> String {
        parseHardwareField(from: json, field: "serial_number") ?? "unknown"
    }

    func parseMemoryMB(from json: String) -> Int {
        // Modern macOS reports "physical_memory"; older versions used "memory".
        let raw = parseHardwareField(from: json, field: "physical_memory")
            ?? parseHardwareField(from: json, field: "memory")
        guard let raw else { return 0 }
        // e.g. "64 GB" or "8192 MB"
        let parts = raw.split(separator: " ")
        guard let number = Double(parts.first ?? "") else { return 0 }
        if raw.uppercased().contains("GB") {
            return Int(number * 1024)
        }
        return Int(number)
    }

    /// Reads a field from `system_profiler -json` output, handling both the
    /// modern flat shape (`SPHardwareDataType[0].field`) and the nested
    /// `_items` shape.
    private func parseHardwareField(from json: String, field: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hardware = root["SPHardwareDataType"] as? [[String: Any]],
              let first = hardware.first else {
            return nil
        }
        if let value = first[field] as? String { return value }
        if let items = first["_items"] as? [[String: Any]], let item = items.first,
           let value = item[field] as? String { return value }
        return nil
    }

    // MARK: - Local command runner

    /// Boot time in seconds via `sysctl kern.boottime`, or nil on failure.
    private func localUptimeSeconds() -> Int? {
        guard let output = try? runLocal("sysctl -n kern.boottime") else { return nil }
        // Format: { sec = 1757000000, usec = 123456 } ...
        guard let secRange = output.range(of: "sec = "),
              let commaIndex = output.range(of: ",", range: secRange.upperBound..<output.endIndex) else {
            return nil
        }
        let secString = String(output[secRange.upperBound..<commaIndex.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        guard let bootEpoch = Int(secString) else { return nil }
        return Int(Date().timeIntervalSince1970) - bootEpoch
    }

    private func runLocal(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
