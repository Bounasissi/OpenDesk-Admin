import XCTest
@testable import OpenDeskCore

/// Plan 15 §5 (Addendum §21): onboarding must DETECT permission state, not
/// display documentation. Injectable probes keep the checks testable; the OS
/// reporting path is authoritative ("never claim granted until OS reports it").
final class OnboardingDetectionTests: XCTestCase {

    func testAllRequiredPermissionsDetected() {
        let detector = OnboardingDetector(probes: FakeProbes(allGranted: false))
        let report = detector.detect()
        let names = report.checks.map { $0.name }
        XCTAssertEqual(Set(names), [
            "Screen Recording", "Accessibility", "Remote Management",
            "SSH", "OpenDesk Agent", "Network Capability",
        ], "Addendum §21 detection list")
    }

    func testMissingPermissionProducesCorrectiveGuidance() {
        let detector = OnboardingDetector(probes: FakeProbes(allGranted: false))
        let report = detector.detect()
        let screenRecording = report.checks.first { $0.name == "Screen Recording" }
        XCTAssertEqual(screenRecording?.granted, false)
        XCTAssertTrue(screenRecording?.guidance.contains("System Settings") ?? false, "corrective instruction present")
        XCTAssertFalse(report.allGranted)
    }

    func testNeverClaimsGrantedWhenOSNotReporting() {
        // A probe that cannot confirm state must report NOT granted — never
        // silently assume (Plan 15 §5: "Never claim permission was granted
        // until the OS reports it").
        let detector = OnboardingDetector(probes: FakeProbes(allGranted: false, ambiguous: true))
        let report = detector.detect()
        for check in report.checks where check.unknown {
            XCTAssertEqual(check.granted, false, "unknown state must not read as granted")
        }
    }

    func testFullyGrantedEnvironment() {
        let detector = OnboardingDetector(probes: FakeProbes(allGranted: true))
        let report = detector.detect()
        XCTAssertTrue(report.allGranted)
    }
}

/// Injectable probe bundle (the GUI wires real OS checks; tests inject fakes).
final class FakeProbes: OnboardingProbes {
    let allGranted: Bool
    let ambiguous: Bool
    init(allGranted: Bool, ambiguous: Bool = false) {
        self.allGranted = allGranted
        self.ambiguous = ambiguous
    }

    func screenRecording() -> PermissionProbeResult { ambiguous ? .unknown : (allGranted ? .granted : .missing) }
    func accessibility() -> PermissionProbeResult { ambiguous ? .unknown : (allGranted ? .granted : .missing) }
    func remoteManagement() -> PermissionProbeResult { ambiguous ? .unknown : (allGranted ? .granted : .missing) }
    func sshAvailable() -> PermissionProbeResult { allGranted ? .granted : .missing }
    func agentState() -> PermissionProbeResult { allGranted ? .granted : .missing }
    func networkCapability() -> PermissionProbeResult { allGranted ? .granted : .missing }
}
