import Foundation

// MARK: - CIDR parsing (Plan 04 §2.3)

/// A parsed CIDR block enumerating probeable host addresses.
/// Bounded: refuses ranges larger than `maxAddresses` to prevent runaway scans.
public struct CIDRRange: Equatable, Sendable {
    public static let maxAddresses = 65_536

    public let addresses: [String]
    public let isIPv6: Bool

    public init(addresses: [String], isIPv6: Bool) {
        self.addresses = addresses
        self.isIPv6 = isIPv6
    }

    public enum ParseError: Error { case invalid }

    public static func parse(_ input: String) throws -> CIDRRange {
        let parts = input.split(separator: "/").map(String.init)
        guard parts.count == 2, let prefix = Int(parts[1]) else { throw ParseError.invalid }
        if parts[0].contains(":") {
            return try parseIPv6(base: parts[0], prefix: prefix)
        }
        return try parseIPv4(base: parts[0], prefix: prefix)
    }

    private static func parseIPv4(base: String, prefix: Int) throws -> CIDRRange {
        guard prefix >= 0, prefix <= 32 else { throw ParseError.invalid }
        let octets = base.split(separator: ".").map(String.init)
        guard octets.count == 4 else { throw ParseError.invalid }
        var value: UInt32 = 0
        for octet in octets {
            guard let byte = UInt8(octet) else { throw ParseError.invalid }
            value = (value << 8) | UInt32(byte)
        }
        let mask: UInt32 = prefix == 0 ? 0 : (~0 << (32 - prefix)) & 0xFFFF_FFFF
        guard value & ~mask == 0 else { throw ParseError.invalid }
        let total = 1 << (32 - prefix)
        guard total <= maxAddresses else { throw ParseError.invalid }
        var addresses: [String] = []
        addresses.reserveCapacity(total)
        for offset in 0..<total {
            let v = value | UInt32(offset)
            let a = String((v >> 24) & 255)
            let b = String((v >> 16) & 255)
            let c = String((v >> 8) & 255)
            let d = String(v & 255)
            addresses.append(a + "." + b + "." + c + "." + d)
        }
        return CIDRRange(addresses: addresses, isIPv6: false)
    }

    private static func parseIPv6(base: String, prefix: Int) throws -> CIDRRange {
        guard prefix >= 0, prefix <= 128 else { throw ParseError.invalid }
        guard let v6 = IPv6Pair(parsing: base) else { throw ParseError.invalid }
        let bitsRemaining = 128 - prefix
        guard bitsRemaining <= 16 else { throw ParseError.invalid } // cap enumeration cost
        let total = 1 << bitsRemaining
        guard total <= maxAddresses else { throw ParseError.invalid }
        var addresses: [String] = []
        addresses.reserveCapacity(total)
        var value = v6
        for _ in 0..<total {
            addresses.append(value.formatted)
            value = value.incrementLowGroup()
        }
        return CIDRRange(addresses: addresses, isIPv6: true)
    }
}

/// Minimal IPv6 address as a (high, low) 64-bit pair — avoids UInt128,
/// which is unavailable below macOS 15.
public struct IPv6Pair: Equatable, Sendable {
    public let high: UInt64
    public let low: UInt64

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    public init?(parsing string: String) {
        // Expand "::" first: split on it and fill the missing zero groups.
        var sections: [String]
        if let range = string.range(of: "::") {
            let left = String(string[string.startIndex..<range.lowerBound])
            let right = String(string[range.upperBound...])
            let leftGroups = left.isEmpty ? [] : left.split(separator: ":").map(String.init)
            let rightGroups = right.isEmpty ? [] : right.split(separator: ":").map(String.init)
            let fill = 8 - leftGroups.count - rightGroups.count
            guard fill >= 1 else { return nil }
            sections = leftGroups + Array(repeating: "0", count: fill) + rightGroups
        } else {
            sections = string.split(separator: ":").map(String.init)
        }
        guard sections.count == 8 else { return nil }
        var high: UInt64 = 0
        var low: UInt64 = 0
        for (index, section) in sections.enumerated() {
            guard let group = UInt16(section, radix: 16) else { return nil }
            if index < 4 {
                high = (high << 16) | UInt64(group)
            } else {
                low = (low << 16) | UInt64(group)
            }
        }
        self.high = high
        self.low = low
    }

    /// Increment the least-significant 16-bit group for range enumeration.
    public func incrementLowGroup() -> IPv6Pair {
        IPv6Pair(high: high, low: low &+ 1)
    }

    public var formatted: String {
        var groups: [String] = []
        groups.append(String(UInt16(truncatingIfNeeded: high >> 48), radix: 16))
        groups.append(String(UInt16(truncatingIfNeeded: high >> 32), radix: 16))
        groups.append(String(UInt16(truncatingIfNeeded: high >> 16), radix: 16))
        groups.append(String(UInt16(truncatingIfNeeded: high), radix: 16))
        groups.append(String(UInt16(truncatingIfNeeded: low >> 48), radix: 16))
        groups.append(String(UInt16(truncatingIfNeeded: low >> 32), radix: 16))
        groups.append(String(UInt16(truncatingIfNeeded: low >> 16), radix: 16))
        groups.append(String(UInt16(truncatingIfNeeded: low), radix: 16))
        // RFC 5952: compress the longest run of >= 2 zero groups to "::".
        var bestStart = -1
        var bestLength = 0
        var currentStart = -1
        var currentLength = 0
        for (index, group) in groups.enumerated() {
            if group == "0" {
                if currentStart < 0 { currentStart = index }
                currentLength += 1
                if currentLength > bestLength {
                    bestLength = currentLength
                    bestStart = currentStart
                }
            } else {
                currentStart = -1
                currentLength = 0
            }
        }
        guard bestLength >= 2 else { return groups.joined(separator: ":") }
        var compressed = groups[0..<bestStart]
        compressed.append("")
        compressed.append(contentsOf: groups[(bestStart + bestLength)...])
        let suffix = bestStart + bestLength == 8 ? ":" : ""
        return compressed.joined(separator: ":") + (bestStart == 0 && suffix.isEmpty && groups[bestStart + bestLength - 1] == "0" && bestStart + bestLength == 8 ? ":" : suffix)
    }
}

// MARK: - Scanner (Plan 04 §2.3)

public typealias PortProber = @Sendable (String, UInt16, Int) async -> Bool

/// Bounded, cancellable CIDR + capability probe scanner.
/// Probes are injected for testability; the default prober opens a TCP
/// connection with a timeout.
public struct CIDRScanner {
    public let concurrencyLimit: Int
    public let probeTimeoutMs: Int
    public let prober: PortProber

    public init(concurrencyLimit: Int = 16, probeTimeoutMs: Int = 1000, prober: PortProber? = nil) {
        self.concurrencyLimit = max(1, concurrencyLimit)
        self.probeTimeoutMs = probeTimeoutMs
        self.prober = prober ?? { host, port, timeoutMs in
            await Self.tcpProbe(host: host, port: port, timeoutMs: timeoutMs)
        }
    }

    public struct HostScanResult: Equatable, Sendable {
        public let host: String
        public let openPorts: [UInt16]
        public init(host: String, openPorts: [UInt16]) {
            self.host = host
            self.openPorts = openPorts
        }
    }

    /// Scan a range against probe ports. Results are deduplicated per host.
    /// Cancellation aborts remaining probes promptly.
    public func scan(_ range: CIDRRange, ports: [UInt16]) async throws -> [HostScanResult] {
        let hosts = range.addresses
        // Result accumulation happens only in the group-consumer task (single
        // context), so a plain dictionary is race-free without async-unsafe locks.
        var results: [String: Set<UInt16>] = [:]
        let maxInFlight = max(1, concurrencyLimit)

        await withTaskGroup(of: (String, UInt16, Bool).self) { group in
            var inFlight = 0
            var nextIndex = 0

            func addNextProbe() {
                guard nextIndex < hosts.count else { return }
                let host = hosts[nextIndex]
                nextIndex += 1
                for port in ports {
                    let index = nextIndex - 1
                    group.addTask {
                        if Task.isCancelled { return (host, port, false) }
                        let open = await self.prober(host, port, self.probeTimeoutMs)
                        _ = index
                        return (host, port, open)
                    }
                    inFlight += 1
                }
            }

            addNextProbe()
            while inFlight > 0 {
                if let (host, port, open) = await group.next() {
                    inFlight -= 1
                    if open {
                        results[host, default: []].insert(port)
                    }
                    if !Task.isCancelled, nextIndex < hosts.count, inFlight < maxInFlight {
                        addNextProbe()
                    }
                }
            }
        }

        return results
            .map { HostScanResult(host: $0.key, openPorts: $0.value.sorted()) }
            .sorted { $0.host < $1.host }
    }

    /// Default TCP probe using a POSIX connect with timeout.
    static func tcpProbe(host: String, port: UInt16, timeoutMs: Int) async -> Bool {
        let timeout = TimeInterval(max(50, timeoutMs)) / 1000.0
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: Self.blockingProbe(host: host, port: port, timeout: timeout))
            }
        }
    }

    private static func blockingProbe(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        var hints = addrinfo()
        hints.ai_socktype = Int32(SOCK_STREAM)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let info else { return false }
        defer { freeaddrinfo(info) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let connectResult = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if connectResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pollSet = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let timeoutInt = Int32(max(1, Int(timeout * 1000)))
        guard poll(&pollSet, 1, timeoutInt) > 0 else { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
        return error == 0
    }
}

// MARK: - Scan observation + reconciliation (Plan 04 §2.4 / A1.2)

/// What a discovery probe observed about a candidate machine.
public struct ScanObservation: Equatable, Sendable {
    public let hostname: String
    public let endpoints: [Endpoint]
    public let stableSignals: [StableSignal]

    public init(hostname: String, endpoints: [Endpoint], stableSignals: [StableSignal]) {
        self.hostname = hostname
        self.endpoints = endpoints
        self.stableSignals = stableSignals
    }
}

/// Reconciles scan observations into stable device identities.
/// Confidence order (Plan 04 A1.2): hardwareMAC > machineUUID > sshHostKey >
/// hostname > subnetCorrelation. A machine is never duplicated merely because
/// its IP, interface, or Bonjour name changed.
public struct DeviceReconciler {
    let repository: DeviceRepository

    public init(repository: DeviceRepository) {
        self.repository = repository
    }

    static func confidence(of signal: StableSignal) -> Int {
        switch signal {
        case .hardwareMAC: return 4
        case .machineUUID: return 3
        case .sshHostKey: return 2
        case .hostname: return 1
        case .subnetCorrelation: return 0
        }
    }

    public func reconcile(_ observation: ScanObservation) throws {
        let devices = try repository.all()
        var best: (device: Device, confidence: Int)?

        for device in devices {
            for signal in observation.stableSignals {
                if device.stableSignals.contains(signal) {
                    let c = Self.confidence(of: signal)
                    if best == nil || c > best!.confidence {
                        best = (device, c)
                    }
                }
            }
        }

        guard var matched = best?.device else {
            var created = Device(hostname: observation.hostname, lifecycle: .online)
            created.stableSignals = observation.stableSignals
            created.endpoints = observation.endpoints
            try repository.upsert(created)
            return
        }

        matched.hostname = observation.hostname
        var endpoints = matched.endpoints
        for endpoint in observation.endpoints where !endpoints.contains(endpoint) {
            endpoints.append(endpoint)
        }
        matched.endpoints = endpoints
        var signals = matched.stableSignals
        for signal in observation.stableSignals where !signals.contains(signal) {
            signals.append(signal)
        }
        matched.stableSignals = signals
        matched.lifecycle = .online
        matched.updatedAt = Date()
        try repository.upsert(matched)
    }
}
