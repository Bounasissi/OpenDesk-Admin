import XCTest
@testable import OpenDeskCore

/// Plan 09 tests: JSON export shape (§25 gap #18), snapshot diff,
/// device-vs-device comparison, group aggregates.
final class InventoryComparisonTests: XCTestCase {

    private func makeReport(hostname: String, os: String, arch: String, apps: [MachineReport.AppEntry], storageFreeGB: Int? = nil, agentInstalled: Bool? = nil) -> MachineReport {
        var report = MachineReport(hostname: hostname)
        report.osVersion = os
        report.chipArchitecture = arch
        report.installedApps = apps
        report.storageFreeGB = storageFreeGB
        report.agentInstalled = agentInstalled
        return report
    }

    private func app(_ name: String, _ version: String) -> MachineReport.AppEntry {
        MachineReport.AppEntry(name: name, version: version, path: "/Applications/\(name).app")
    }

    // MARK: JSON export shape (§25 gap #18 — dedicated test)

    func testJSONExportShape() throws {
        let report = makeReport(hostname: "lab-01", os: "15.5", arch: "arm64", apps: [app("Xcode", "16.4")], storageFreeGB: 42)
        let data = try ReportExporter.reportsJSON([report])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(object.count, 1)
        let entry = try XCTUnwrap(object.first)
        XCTAssertEqual(entry["hostname"] as? String, "lab-01")
        XCTAssertEqual(entry["osVersion"] as? String, "15.5")
        let apps = try XCTUnwrap(entry["installedApps"] as? [[String: Any]])
        XCTAssertEqual(apps.first?["name"] as? String, "Xcode")
        XCTAssertEqual(entry["storageFreeGB"] as? Int, 42, "optional drift fields export when present")
    }

    // MARK: Snapshot diff (drift detection concretized)

    func testSnapshotDiffDetectsAppAndOSChanges() {
        let before = makeReport(hostname: "lab-01", os: "15.4", arch: "arm64", apps: [app("Old", "1.0"), app("Kept", "2.0")], storageFreeGB: 50)
        let after = makeReport(hostname: "lab-01", os: "15.5", arch: "arm64", apps: [app("New", "3.0"), app("Kept", "2.0")], storageFreeGB: 20)
        let diff = SnapshotDiff.between(before: before, after: after, storageThresholdGB: 25)
        XCTAssertEqual(diff.newApps, ["New"])
        XCTAssertEqual(diff.removedApps, ["Old"])
        XCTAssertEqual(diff.osChanged, true)
        XCTAssertTrue(diff.findings.contains { $0.contains("storage") }, "storage threshold crossing detected")
    }

    func testAgentMissingIsFirstClassFinding() {
        let before = makeReport(hostname: "lab-02", os: "15.5", arch: "arm64", apps: [], agentInstalled: true)
        let after = makeReport(hostname: "lab-02", os: "15.5", arch: "arm64", apps: [], agentInstalled: false)
        let diff = SnapshotDiff.between(before: before, after: after)
        XCTAssertTrue(diff.agentDisappeared, "agent disappearance is a first-class drift finding")
    }

    // MARK: Device-vs-device comparison (Plan 09 A1.1)

    func testDeviceVsDeviceComparison() {
        let a = makeReport(hostname: "a", os: "15.5", arch: "arm64", apps: [app("Keynote", "15")], storageFreeGB: 100)
        let b = makeReport(hostname: "b", os: "14.7", arch: "x86_64", apps: [app("Keynote", "14")], storageFreeGB: 10)
        let comparison = SnapshotDiff.betweenDevice(deviceA: a, deviceB: b)
        XCTAssertTrue(comparison.osDifferent)
        XCTAssertTrue(comparison.architectureDifferent)
        XCTAssertEqual(comparison.appVersionDeltas["Keynote"], "15 vs 14")
    }

    // MARK: Group aggregates (Plan 09 A1.1)

    func testGroupAggregates() {
        let fleet = [
            makeReport(hostname: "a", os: "15.5", arch: "arm64", apps: [app("Slack", "4.0")]),
            makeReport(hostname: "b", os: "15.5", arch: "x86_64", apps: [app("Slack", "4.0"), app("Zoom", "6")]),
            makeReport(hostname: "c", os: "14.7", arch: "arm64", apps: []),
        ]
        let aggregates = InventoryAggregates(of: fleet)
        XCTAssertEqual(aggregates.byArchitecture["arm64"], 2)
        XCTAssertEqual(aggregates.byArchitecture["x86_64"], 1)
        XCTAssertEqual(aggregates.byOS["15.5"], 2)
        XCTAssertEqual(aggregates.byOS["14.7"], 1)
        XCTAssertEqual(aggregates.appPresence["Slack"], 2)
        XCTAssertEqual(aggregates.appPresence["Zoom"], 1)
        XCTAssertEqual(aggregates.total, 3)
    }
}
