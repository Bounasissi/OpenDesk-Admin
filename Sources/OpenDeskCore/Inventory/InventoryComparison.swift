import Foundation

/// Convenience for tests and partial snapshots (extension preserves the
/// memberwise initializer).
public extension MachineReport {
    init(hostname: String) {
        self.init(
            hostname: hostname, modelName: "", chipArchitecture: "", osVersion: "",
            serialNumber: "", totalMemoryMB: 0, uptimeSeconds: nil,
            installedApps: [], collectedAt: Date()
        )
    }
}

// MARK: - Snapshot diff (Plan 09 §6 + A1.1)

public struct SnapshotDiff: Equatable, Sendable {
    public var newApps: [String]
    public var removedApps: [String]
    public var osChanged: Bool
    public var agentDisappeared: Bool
    public var managementChanged: Bool
    public var findings: [String]

    /// Device-vs-previous comparison (drift).
    public static func between(
        before: MachineReport,
        after: MachineReport,
        storageThresholdGB: Int = 25
    ) -> SnapshotDiff {
        let beforeNames = Set(before.installedApps.map { $0.name })
        let afterNames = Set(after.installedApps.map { $0.name })
        var findings: [String] = []
        if before.osVersion != after.osVersion {
            findings.append("OS changed: \(before.osVersion) → \(after.osVersion)")
        }
        if let beforeStorage = before.storageFreeGB, let afterStorage = after.storageFreeGB {
            if beforeStorage > storageThresholdGB, afterStorage <= storageThresholdGB {
                findings.append("storage crossed threshold: \(afterStorage)GB free")
            }
        }
        if before.agentInstalled == true, after.agentInstalled == false {
            findings.append("agent disappeared")
        }
        if before.managementStatus != after.managementStatus {
            findings.append("management status changed")
        }
        return SnapshotDiff(
            newApps: afterNames.subtracting(beforeNames).sorted(),
            removedApps: beforeNames.subtracting(afterNames).sorted(),
            osChanged: before.osVersion != after.osVersion,
            agentDisappeared: before.agentInstalled == true && after.agentInstalled == false,
            managementChanged: before.managementStatus != after.managementStatus,
            findings: findings
        )
    }

    // MARK: Device-vs-device comparison

    public struct DeviceComparison: Equatable, Sendable {
        public var osDifferent: Bool
        public var architectureDifferent: Bool
        public var appVersionDeltas: [String: String]
        public var appSetsDiffer: Bool
    }

    /// Device-vs-device comparison (Plan 09 A1.1).
    public static func betweenDevice(deviceA: MachineReport, deviceB: MachineReport) -> DeviceComparison {
        let aApps = Dictionary(uniqueKeysWithValues: deviceA.installedApps.map { ($0.name, $0.version) })
        let bApps = Dictionary(uniqueKeysWithValues: deviceB.installedApps.map { ($0.name, $0.version) })
        var deltas: [String: String] = [:]
        for name in Set(aApps.keys).union(bApps.keys) {
            if aApps[name] != bApps[name] {
                deltas[name] = "\(aApps[name] ?? "—") vs \(bApps[name] ?? "—")"
            }
        }
        return DeviceComparison(
            osDifferent: deviceA.osVersion != deviceB.osVersion,
            architectureDifferent: deviceA.chipArchitecture != deviceB.chipArchitecture,
            appVersionDeltas: deltas,
            appSetsDiffer: Set(aApps.keys) != Set(bApps.keys)
        )
    }
}

// MARK: - Group aggregates (Plan 09 A1.1)

public struct InventoryAggregates: Equatable, Sendable {
    public var total: Int
    public var byArchitecture: [String: Int]
    public var byOS: [String: Int]
    public var byLifecycle: [String: Int]
    public var appPresence: [String: Int]

    public init(of reports: [MachineReport], lifecycles: [String] = []) {
        total = reports.count
        var arch: [String: Int] = [:]
        var os: [String: Int] = [:]
        var presence: [String: Int] = [:]
        for report in reports {
            arch[report.chipArchitecture, default: 0] += 1
            os[report.osVersion, default: 0] += 1
            for app in report.installedApps {
                presence[app.name, default: 0] += 1
            }
        }
        byArchitecture = arch
        byOS = os
        byLifecycle = Dictionary(lifecycles.map { ($0, 1) }, uniquingKeysWith: +)
        appPresence = presence
    }
}
