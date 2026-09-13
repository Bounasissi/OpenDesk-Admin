// Inventory — collectors normalized into SQLite snapshots.
// Behavior spec: reverse-engineering/behavior-specs/inventory-collect.yaml
// Collectors run over SSH in v1 (system_profiler, lsappinfo-free approaches,
// last/w, mdfind). Partial collector failure -> snapshot saved with per-collector
// error; task does not fail wholesale.

import Foundation

public struct InventorySnapshot: Codable, Sendable, Equatable {
    public var device: String
    public var collectedAt: String
    public var hardware: [String: String]?
    public var os: [String: String]?
    public var network: [[String: String]]?
    public var storage: [[String: String]]?
    public var applications: [[String: String]]?
    public var users: [String]?
    public var errors: [String: String]?

    public init(device: String, collectedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.device = device
        self.collectedAt = collectedAt
    }
}

public final class InventoryCollector: @unchecked Sendable {
    let ssh: SSHTransport

    public init(ssh: SSHTransport) {
        self.ssh = ssh
    }

    /// Collect a full snapshot from one host. Never throws for collector-level
    /// failures — errors are recorded in snapshot.errors.
    public func collect(host: SSHHost, deviceID: String) async -> InventorySnapshot {
        var snapshot = InventorySnapshot(device: deviceID)
        var errors: [String: String] = [:]

        // Hardware
        if let hw = await collectHardware(host: host) {
            snapshot.hardware = hw
        } else {
            errors["hardware"] = "system_profiler SPHardwareDataType failed"
        }

        // OS
        if let os = await collectOS(host: host) {
            snapshot.os = os
        } else {
            errors["os"] = "sw_vers failed"
        }

        // Network
        if let net = await collectNetwork(host: host) {
            snapshot.network = net
        } else {
            errors["network"] = "ifconfig/route failed"
        }

        // Storage
        if let storage = await collectStorage(host: host) {
            snapshot.storage = storage
        } else {
            errors["storage"] = "df failed"
        }

        // Applications
        if let apps = await collectApplications(host: host) {
            snapshot.applications = apps
        } else {
            errors["applications"] = "mdfind failed"
        }

        // Users (console)
        if let users = await collectUsers(host: host) {
            snapshot.users = users
        } else {
            errors["users"] = "who failed"
        }

        if !errors.isEmpty { snapshot.errors = errors }
        return snapshot
    }

    // MARK: Collectors

    func collectHardware(host: SSHHost) async -> [String: String]? {
        guard let result = try? await ssh.execute(
            "system_profiler SPHardwareDataType 2>/dev/null | grep -E 'Model Name|Model Identifier|Chip|Memory|Serial' | sed 's/^[[:space:]]*//'",
            on: host
        ), result.exitCode == 0 else { return nil }
        var out: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            out[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return out.isEmpty ? nil : out
    }

    func collectOS(host: SSHHost) async -> [String: String]? {
        guard let result = try? await ssh.execute(
            "sw_vers && uname -m",
            on: host
        ), result.exitCode == 0 else { return nil }
        var out: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                out[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            } else if line.contains("arm64") || line.contains("x86_64") {
                out["architecture"] = line.trimmingCharacters(in: .whitespaces)
            }
        }
        return out.isEmpty ? nil : out
    }

    func collectNetwork(host: SSHHost) async -> [[String: String]]? {
        guard let result = try? await ssh.execute(
            "ifconfig -a 2>/dev/null | grep -E '^[a-z]|inet '",
            on: host
        ), result.exitCode == 0 else { return nil }
        var interfaces: [[String: String]] = []
        var current: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if !s.hasPrefix("inet") && s.hasSuffix(":") {
                if !current.isEmpty { interfaces.append(current) }
                current = ["interface": s.trimmingCharacters(in: CharacterSet(charactersIn: ": "))]
            } else if s.hasPrefix("inet ") {
                let ip = s.split(separator: " ").dropFirst(1).first.map(String.init) ?? ""
                current["ipv4"] = ip
            }
        }
        if !current.isEmpty { interfaces.append(current) }
        return interfaces.isEmpty ? nil : interfaces
    }

    func collectStorage(host: SSHHost) async -> [[String: String]]? {
        guard let result = try? await ssh.execute(
            "df -h / 2>/dev/null | tail -1",
            on: host
        ), result.exitCode == 0 else { return nil }
        let cols = result.stdout.split(separator: " ").filter { !$0.isEmpty }
        guard cols.count >= 4 else { return nil }
        return [[
            "filesystem": String(cols[0]),
            "capacity": String(cols[1]),
            "used": String(cols[2]),
            "available": String(cols[3]),
            "mount": String(cols.count > 8 ? cols[8] : cols.last ?? ""),
        ]]
    }

    func collectApplications(host: SSHHost) async -> [[String: String]]? {
        guard let result = try? await ssh.execute(
            "mdfind 'kMDItemContentType == \"com.apple.application-bundle\"' 2>/dev/null | head -200",
            on: host
        ), result.exitCode == 0 else { return nil }
        let apps = result.stdout.split(separator: "\n").map { line -> [String: String] in
            let path = String(line)
            let name = (path as NSString).lastPathComponent
            return ["path": path, "name": name]
        }
        return apps.isEmpty ? nil : apps
    }

    func collectUsers(host: SSHHost) async -> [String]? {
        guard let result = try? await ssh.execute("who | awk '{print $1}' | sort -u", on: host),
              result.exitCode == 0 else { return nil }
        let users = result.stdout.split(separator: "\n").map(String.init)
        return users.isEmpty ? nil : users
    }
}
