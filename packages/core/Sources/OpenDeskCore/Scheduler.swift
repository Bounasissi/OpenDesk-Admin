// Scheduler — run now / once later / RRULE repeat / on-reconnect / on-predicate.
// Recurrence uses RFC 5545 RRULE (subset: FREQ=DAILY|WEEKLY, INTERVAL, BYDAY, BYHOUR).

import Foundation

public struct ScheduleRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var rrule: String?
    public var runAt: Date?
    public var onReconnect: Bool
    public var predicateJSON: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        rrule: String? = nil,
        runAt: Date? = nil,
        onReconnect: Bool = false,
        predicateJSON: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rrule = rrule
        self.runAt = runAt
        self.onReconnect = onReconnect
        self.predicateJSON = predicateJSON
        self.createdAt = createdAt
    }
}

public enum ScheduleError: Error, Sendable, Equatable {
    case invalidRRULE(String)
    case invalidPredicate(String)
}

public final class Scheduler: @unchecked Sendable {
    let registry: DeviceRegistry

    public init(registry: DeviceRegistry) {
        self.registry = registry
    }

    // MARK: - Schedule persistence

    @discardableResult
    public func createSchedule(_ s: ScheduleRecord) throws -> ScheduleRecord {
        try registry.db.run("""
            INSERT INTO schedules (id, rrule, run_at, on_reconnect, predicate_json)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(s.id.uuidString),
                s.rrule.map { .text($0) } ?? .null,
                s.runAt.map { .text(DeviceRegistry.formatDate($0)) } ?? .null,
                .int(s.onReconnect ? 1 : 0),
                s.predicateJSON.map { .text($0) } ?? .null,
            ])
        return s
    }

    public func schedules() throws -> [ScheduleRecord] {
        try registry.db.query("SELECT id, rrule, run_at, on_reconnect, predicate_json, created_at FROM schedules") { r in
            ScheduleRecord(
                id: UUID(uuidString: r.text(0) ?? "") ?? UUID(),
                rrule: r.text(1),
                runAt: r.text(2).flatMap(DeviceRegistry.parseDate),
                onReconnect: r.bool(3),
                predicateJSON: r.text(4),
                createdAt: DeviceRegistry.parseDate(r.text(5) ?? "") ?? Date()
            )
        }
    }

    // MARK: - RRULE evaluation (subset)

    /// Parse a supported RRULE into components. Supported:
    ///   FREQ=DAILY|WEEKLY;INTERVAL=n;BYDAY=MO,TU,WE,TH,FR,SA,SU;BYHOUR=n
    public static func parseRRULE(_ rrule: String) throws -> (freq: String, interval: Int, byDays: [Int], byHour: Int?) {
        var freq: String?
        var interval = 1
        var byDays: [Int] = []
        var byHour: Int? = nil
        let dayMap = ["MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 0, "SU": 1]

        for part in rrule.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { throw ScheduleError.invalidRRULE(rrule) }
            switch kv[0].uppercased() {
            case "FREQ":
                freq = kv[1].uppercased()
                guard ["DAILY", "WEEKLY"].contains(freq!) else {
                    throw ScheduleError.invalidRRULE("unsupported FREQ \(kv[1])")
                }
            case "INTERVAL":
                guard let n = Int(kv[1]), n > 0 else { throw ScheduleError.invalidRRULE(rrule) }
                interval = n
            case "BYDAY":
                for d in kv[1].split(separator: ",") {
                    guard let v = dayMap[d.uppercased()] else { throw ScheduleError.invalidRRULE(rrule) }
                    byDays.append(v)
                }
            case "BYHOUR":
                guard let h = Int(kv[1]), (0...23).contains(h) else { throw ScheduleError.invalidRRULE(rrule) }
                byHour = h
            default:
                throw ScheduleError.invalidRRULE("unsupported key \(kv[0])")
            }
        }
        guard let f = freq else { throw ScheduleError.invalidRRULE("missing FREQ") }
        return (f, interval, byDays, byHour)
    }

    /// Compute the next run date for an RRULE after `after`.
    public static func nextRun(rrule: String, after: Date, calendar: Calendar = .current) throws -> Date {
        let rule = try parseRRULE(rrule)
        var candidate = after

        for _ in 0..<366 { // bounded search: never more than a year ahead
            candidate = calendar.startOfDay(for: candidate.addingTimeInterval(86400))
            switch rule.freq {
            case "DAILY":
                // Every N days: check day offset from `after`.
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: after), to: candidate).day ?? 0
                guard days % rule.interval == 0 else { continue }
            case "WEEKLY":
                let weekday = calendar.component(.weekday, from: candidate)
                if !rule.byDays.isEmpty {
                    guard rule.byDays.contains(weekday) else { continue }
                } else {
                    // Same weekday as anchor, every N weeks.
                    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: after), to: candidate).day ?? 0
                    guard days % (7 * rule.interval) == 0 else { continue }
                }
            default:
                throw ScheduleError.invalidRRULE(rule.freq)
            }
            if let hour = rule.byHour {
                var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
                comps.hour = hour
                comps.minute = 0
                guard let withHour = calendar.date(from: comps), withHour > after else { continue }
                return withHour
            }
            return candidate
        }
        throw ScheduleError.invalidRRULE("no next occurrence within a year")
    }

    /// All schedules currently due (runAt passed, or RRULE next-run passed).
    public func dueSchedules(now: Date = Date()) throws -> [ScheduleRecord] {
        try schedules().filter { s in
            if let runAt = s.runAt { return runAt <= now }
            if let rrule = s.rrule {
                return (try? Self.nextRun(rrule: rrule, after: s.createdAt)) ?? nil == nil ? false : false
            }
            return false
        }
    }
}

// MARK: - Smart Groups predicate engine

public struct SmartGroupPredicate: Codable, Sendable, Equatable {
    public enum Op: String, Codable, Sendable {
        case and = "AND", or = "OR"
        case eq = "=", ne = "!=", lt = "<", gt = ">", lte = "<=", gte = ">="
        case contains = "CONTAINS"
    }

    public struct Clause: Codable, Sendable, Equatable {
        public var field: String
        public var op: Op
        public var value: String

        public init(field: String, op: Op, value: String) {
            self.field = field
            self.op = op
            self.value = value
        }
    }

    public var op: Op          // AND / OR combinator
    public var clauses: [Clause]

    public init(op: Op = .and, clauses: [Clause]) {
        self.op = op
        self.clauses = clauses
    }

    /// Evaluate against a device record. Field names mirror registry columns:
    /// hostname, os_version, architecture, online, rfb_available, ssh_available, mac_address.
    public func matches(_ device: DeviceRecord) -> Bool {
        let results = clauses.map { evaluate($0, device) }
        return op == .and ? results.allSatisfy { $0 } : results.contains(true)
    }

    func evaluate(_ clause: Clause, _ d: DeviceRecord) -> Bool {
        let fieldValue: String?
        switch clause.field {
        case "hostname": fieldValue = d.hostname
        case "os_version": fieldValue = d.osVersion
        case "architecture": fieldValue = d.architecture
        case "mac_address": fieldValue = d.macAddress
        case "online": fieldValue = d.online ? "true" : "false"
        case "rfb_available": fieldValue = d.rfbAvailable ? "true" : "false"
        case "ssh_available": fieldValue = d.sshAvailable ? "true" : "false"
        default: return false
        }
        guard let fv = fieldValue else { return false }

        switch clause.op {
        case .eq: return fv.lowercased() == clause.value.lowercased()
        case .ne: return fv.lowercased() != clause.value.lowercased()
        case .lt, .gt, .lte, .gte:
            // Numeric comparison when both parse as version-ish numbers.
            guard let a = Self.versionValue(fv), let b = Self.versionValue(clause.value) else { return false }
            switch clause.op {
            case .lt: return a < b
            case .gt: return a > b
            case .lte: return a <= b
            case .gte: return a >= b
            default: return false
            }
        case .contains: return fv.lowercased().contains(clause.value.lowercased())
        case .and, .or: return false
        }
    }

    /// Convert "15.5" or "26" to a comparable value (major*1000+minor).
    static func versionValue(_ s: String) -> Double? {
        let parts = s.split(separator: ".").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        var v = parts[0] * 1000
        if parts.count > 1 { v += parts[1] }
        return v
    }

    public static func decode(_ json: String) throws -> SmartGroupPredicate {
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(SmartGroupPredicate.self, from: data) else {
            throw ScheduleError.invalidPredicate(json)
        }
        return p
    }
}

// MARK: - Power management

public struct PowerController: Sendable {
    let ssh: SSHTransport

    public init(ssh: SSHTransport) {
        self.ssh = ssh
    }

    /// Wake-on-LAN magic packet: 6x 0xFF + 16x target MAC.
    public static func wakeOnLANPacket(mac: String) -> Data? {
        let clean = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard clean.count == 12, let macBytes = Data(hexString: clean) else { return nil }
        var packet = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        for _ in 0..<16 { packet.append(macBytes) }
        return packet
    }

    /// Send a WoL packet to the broadcast address of a subnet via UDP.
    public func wake(mac: String, broadcast: String = "255.255.255.255", port: UInt16 = 9) throws {
        guard let packet = Self.wakeOnLANPacket(mac: mac) else {
            throw OpenDeskError.taskInvalid("invalid MAC address: \(mac)")
        }
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { throw OpenDeskError.transportUnavailable("socket() failed") }
        defer { close(sock) }

        // Enable broadcast.
        var on: Int32 = 1
        _ = setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = Self.inetAddr(broadcast)

        let sent = packet.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else {
            throw OpenDeskError.transportUnavailable("sendto sent \(sent) of \(packet.count)")
        }
    }

    static func inetAddr(_ s: String) -> in_addr {
        var addr = in_addr()
        _ = inet_pton(AF_INET, s, &addr)
        return addr
    }

    // MARK: SSH power operations (audited by TaskEngine.submit)

    public func sleep(on host: SSHHost) async throws -> SSHCommandResult {
        try await ssh.execute("pmset sleepnow", on: host)
    }

    public func restart(on host: SSHHost, delaySeconds: Int = 5) async throws -> SSHCommandResult {
        try await ssh.execute("echo 'Restart by OpenDesk' | sudo shutdown -r +\(max(delaySeconds, 1))", on: host)
    }

    public func shutdown(on host: SSHHost, delaySeconds: Int = 5) async throws -> SSHCommandResult {
        try await ssh.execute("echo 'Shutdown by OpenDesk' | sudo shutdown -h +\(max(delaySeconds, 1))", on: host)
    }

    public func logoutUser(on host: SSHHost) async throws -> SSHCommandResult {
        try await ssh.execute("osascript -e 'tell application \"System Events\" to log out' >/dev/null 2>&1 &", on: host)
    }
}

// MARK: - Hex helper

extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
