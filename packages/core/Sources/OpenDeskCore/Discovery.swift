// Discovery — Bonjour/mDNS browse + CIDR TCP probe + manual entry.
// Behavior spec: reverse-engineering/behavior-specs/discovery.yaml
// Scanner record: hostname, bonjour_name, ips, mac, rfb_available, ssh_available,
//                  latency, os_version, ard_client_version, auth_state, last_seen.
// Discovery never mutates target hosts.

import Foundation
import Network

public struct ScanResult: Codable, Sendable, Equatable {
    public var hostname: String
    public var bonjourName: String?
    public var ips: [String]
    public var macAddress: String?
    public var rfbAvailable: Bool
    public var sshAvailable: Bool
    public var latencyMs: Double?
    public var osVersion: String?
    public var ardClientVersion: String?
    public var authState: String?
    public var lastSeen: Date

    public init(
        hostname: String,
        bonjourName: String? = nil,
        ips: [String] = [],
        macAddress: String? = nil,
        rfbAvailable: Bool = false,
        sshAvailable: Bool = false,
        latencyMs: Double? = nil,
        osVersion: String? = nil,
        ardClientVersion: String? = nil,
        authState: String? = nil,
        lastSeen: Date = Date()
    ) {
        self.hostname = hostname
        self.bonjourName = bonjourName
        self.ips = ips
        self.macAddress = macAddress
        self.rfbAvailable = rfbAvailable
        self.sshAvailable = sshAvailable
        self.latencyMs = latencyMs
        self.osVersion = osVersion
        self.ardClientVersion = ardClientVersion
        self.authState = authState
        self.lastSeen = lastSeen
    }
}

public protocol DiscoverySource: Sendable {
    func scan() async throws -> [ScanResult]
}

// MARK: - Bonjour

public final class BonjourDiscovery: DiscoverySource, @unchecked Sendable {
    public init() {}

    public func scan() async throws -> [ScanResult] {
        // Browse for ARD's _apple-mobdev / _rfb services plus common Mac services.
        let serviceTypes = ["_rfb._tcp", "_workstation._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_adisk._tcp", "_smb._tcp"]
        var results: [ScanResult] = []
        for type in serviceTypes {
            let found = await browse(serviceType: type)
            for (name, host, port) in found {
                let hostKey = host ?? name
                if let idx = results.firstIndex(where: { $0.hostname == hostKey }) {
                    if type == "_rfb._tcp" { results[idx].rfbAvailable = true }
                    if type == "_ssh._tcp" || type == "_sftp-ssh._tcp" { results[idx].sshAvailable = true }
                    if results[idx].bonjourName == nil { results[idx].bonjourName = name }
                } else {
                    var r = ScanResult(hostname: hostKey, bonjourName: name)
                    if type == "_rfb._tcp" { r.rfbAvailable = true }
                    if type == "_ssh._tcp" || type == "_sftp-ssh._tcp" { r.sshAvailable = true }
                    results.append(r)
                }
                _ = port // port recorded implicitly via availability flags in v1
            }
        }
        return results
    }

    private func browse(serviceType: String) async -> [(String, String?, UInt16)] {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
            final class BrowseState: @unchecked Sendable {
                var found: [(String, String?, UInt16)] = []
                var finished = false
                let lock = NSLock()
            }
            let state = BrowseState()

            @Sendable func finish() {
                state.lock.lock()
                let alreadyDone = state.finished
                state.finished = true
                let snapshot = state.found
                state.lock.unlock()
                if !alreadyDone {
                    browser.cancel()
                    continuation.resume(returning: snapshot)
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                state.lock.lock()
                state.found = results.compactMap { result in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return (name, nil, 0)
                }
                state.lock.unlock()
            }

            browser.stateUpdateHandler = { state in
                if case .ready = state {
                    // Give the network a short window to answer, then finish.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { finish() }
                } else if case .failed = state {
                    finish()
                }
            }

            browser.start(queue: .global())
            // Hard timeout so discovery never hangs.
            DispatchQueue.global().asyncAfter(deadline: .now() + 4.0) { finish() }
        }
    }
}

// MARK: - CIDR Scanner

public final class CIDRScanner: DiscoverySource, @unchecked Sendable {
    public let cidr: String
    public let timeoutSeconds: Double

    public init(cidr: String, timeoutSeconds: Double = 1.0) {
        self.cidr = cidr
        self.timeoutSeconds = timeoutSeconds
    }

    public func scan() async throws -> [ScanResult] {
        let addresses = Self.expand(cidr: cidr)
        var results: [ScanResult] = []
        await withTaskGroup(of: ScanResult?.self) { group in
            for addr in addresses {
                group.addTask {
                    await self.probe(host: addr)
                }
            }
            for await result in group {
                if let result { results.append(result) }
            }
        }
        return results
    }

    /// Probe one host for SSH (22) and RFB (5900) with a TCP connect + latency measure.
    func probe(host: String) async -> ScanResult? {
        async let ssh = probePort(host: host, port: 22)
        async let rfb = probePortWithLatency(host: host, port: 5900)
        let (sshOK, rfbLatency) = await (ssh, rfb)
        guard sshOK || rfbLatency != nil else { return nil }
        return ScanResult(
            hostname: host,
            ips: [host],
            rfbAvailable: rfbLatency != nil,
            sshAvailable: sshOK,
            latencyMs: rfbLatency
        )
    }

    private func probePort(host: String, port: UInt16) async -> Bool {
        await probePortWithLatency(host: host, port: port) != nil
    }

    private func probePortWithLatency(host: String, port: UInt16) async -> Double? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            final class ProbeState: @unchecked Sendable {
                var finished = false
                let lock = NSLock()
            }
            let state = ProbeState()
            let start = Date()

            @Sendable func finish(_ ok: Bool) {
                state.lock.lock()
                let alreadyDone = state.finished
                state.finished = true
                state.lock.unlock()
                if !alreadyDone {
                    connection.cancel()
                    continuation.resume(returning: ok ? Date().timeIntervalSince(start) * 1000 : nil)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { finish(false) }
        }
    }

    // MARK: CIDR expansion

    /// Expand "192.168.1.0/24" or a single IP into a list of addresses.
    /// Caps at /24 (256 addresses) to prevent runaway scans.
    public static func expand(cidr: String) -> [String] {
        let parts = cidr.split(separator: "/")
        guard let base = ipv4(parts[0]) else { return [] }
        guard parts.count == 2, let prefix = Int(parts[1]), prefix >= 0, prefix <= 32 else {
            return [dotted(base)]
        }
        let hostBits = 32 - prefix
        let size = 1 << hostBits
        guard size <= 256 else { return [dotted(base)] } // refuse large ranges in v1
        let network = base & ~UInt32(size - 1)
        var out: [String] = []
        for i in 0..<max(size, 1) {
            let addr = network | UInt32(i)
            out.append(dotted(addr))
        }
        return out
    }

    private static func ipv4(_ s: Substring) -> UInt32? {
        let octets = s.split(separator: ".").compactMap { UInt32($0) }
        guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }) else { return nil }
        return (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
    }

    private static func dotted(_ v: UInt32) -> String {
        "\(v >> 24 & 255).\(v >> 16 & 255).\(v >> 8 & 255).\(v & 255)"
    }
}

// MARK: - Composite

public final class DiscoveryService: @unchecked Sendable {
    let registry: DeviceRegistry
    let sources: [DiscoverySource]

    public init(registry: DeviceRegistry, sources: [DiscoverySource]) {
        self.registry = registry
        self.sources = sources
    }

    /// Run all sources, dedupe into the registry (by MAC, then hostname), return merged results.
    @discardableResult
    public func discover() async throws -> [ScanResult] {
        var merged: [String: ScanResult] = [:]
        for source in sources {
            let results = try await source.scan()
            for r in results {
                let key = r.macAddress ?? r.hostname
                if var existing = merged[key] {
                    existing.rfbAvailable = existing.rfbAvailable || r.rfbAvailable
                    existing.sshAvailable = existing.sshAvailable || r.sshAvailable
                    existing.ips = Array(Set(existing.ips + r.ips)).sorted()
                    if existing.bonjourName == nil { existing.bonjourName = r.bonjourName }
                    merged[key] = existing
                } else {
                    merged[key] = r
                }
            }
        }
        let results = Array(merged.values).sorted { $0.hostname < $1.hostname }
        for r in results {
            // Dedupe against existing registry records.
            let existing = try registry.findDevice(mac: r.macAddress, hostname: r.hostname)
            let record = DeviceRecord(
                id: existing?.id ?? UUID(),
                hostname: r.hostname,
                bonjourName: r.bonjourName ?? existing?.bonjourName,
                ips: r.ips,
                macAddress: r.macAddress ?? existing?.macAddress,
                osVersion: r.osVersion ?? existing?.osVersion,
                architecture: existing?.architecture,
                ardVersion: r.ardClientVersion ?? existing?.ardVersion,
                rfbAvailable: r.rfbAvailable || (existing?.rfbAvailable ?? false),
                sshAvailable: r.sshAvailable || (existing?.sshAvailable ?? false),
                authState: r.authState ?? existing?.authState,
                latencyMs: r.latencyMs ?? existing?.latencyMs,
                online: true,
                lastSeen: r.lastSeen
            )
            try registry.upsertDevice(record)
        }
        return results
    }
}
