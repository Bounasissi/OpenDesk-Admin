import Foundation

// MARK: - Onboarding permission detection (Plan 15 §5)

public enum PermissionProbeResult: Equatable, Sendable {
    case granted
    case missing
    case unknown
}

/// Injectable probe bundle — the GUI wires the real OS checks; the detection
/// LOGIC is testable against fakes.
public protocol OnboardingProbes {
    func screenRecording() -> PermissionProbeResult
    func accessibility() -> PermissionProbeResult
    func remoteManagement() -> PermissionProbeResult
    func sshAvailable() -> PermissionProbeResult
    func agentState() -> PermissionProbeResult
    func networkCapability() -> PermissionProbeResult
}

public struct OnboardingCheck: Equatable, Sendable {
    public let name: String
    public let granted: Bool
    public let unknown: Bool
    public let guidance: String
}

public struct OnboardingReport: Equatable, Sendable {
    public let checks: [OnboardingCheck]
    public var allGranted: Bool { checks.allSatisfy { $0.granted } }
}

/// Detection engine. RULE: unknown state never reads as granted.
public struct OnboardingDetector {
    let probes: OnboardingProbes

    public init(probes: OnboardingProbes) {
        self.probes = probes
    }

    public func detect() -> OnboardingReport {
        let checks: [OnboardingCheck] = [
            check("Screen Recording", probes.screenRecording(),
                  guidance: "Grant Screen Recording in System Settings → Privacy & Security. OpenDesk will re-check automatically."),
            check("Accessibility", probes.accessibility(),
                  guidance: "Grant Accessibility in System Settings → Privacy & Security to allow remote control input."),
            check("Remote Management", probes.remoteManagement(),
                  guidance: "Enable Remote Management in System Settings → General → Sharing on the target Mac."),
            check("SSH", probes.sshAvailable(),
                  guidance: "Enable Remote Login (SSH) in System Settings → General → Sharing on the target Mac."),
            check("OpenDesk Agent", probes.agentState(),
                  guidance: "Install and enroll the OpenDesk agent: opendesk-agent enroll --token <token>"),
            check("Network Capability", probes.networkCapability(),
                  guidance: "Grant Local Network access so OpenDesk can discover Macs on your subnet."),
        ]
        return OnboardingReport(checks: checks)
    }

    private func check(_ name: String, _ result: PermissionProbeResult, guidance: String) -> OnboardingCheck {
        switch result {
        case .granted: return OnboardingCheck(name: name, granted: true, unknown: false, guidance: "")
        case .missing: return OnboardingCheck(name: name, granted: false, unknown: false, guidance: guidance)
        case .unknown: return OnboardingCheck(name: name, granted: false, unknown: true, guidance: guidance)
        }
    }
}
