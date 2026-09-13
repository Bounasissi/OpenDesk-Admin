import Foundation

/// A managed client machine in the roster.
public struct Host: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var hostname: String
    public var port: Int
    public var username: String
    public var authMethod: AuthMethod
    public var groups: [String]
    public var screenPort: Int
    public var macAddress: String?
    public var lastSeen: Date?

    public enum AuthMethod: String, Codable, Sendable {
        case key
        case password
    }

    public init(
        id: UUID = UUID(),
        hostname: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .key,
        groups: [String] = [],
        screenPort: Int = 5900,
        macAddress: String? = nil,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.groups = groups
        self.screenPort = screenPort
        self.macAddress = macAddress
        self.lastSeen = lastSeen
    }
}

/// Persistent roster of managed hosts, stored as JSON on disk.
public final class HostRegistry: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "opendesk.hostregistry")

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opendesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("hosts.json")
    }

    public func loadAll() -> [Host] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder().decode([Host].self, from: data)) ?? []
        }
    }

    public func save(_ hosts: [Host]) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(hosts) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    public func add(_ host: Host) {
        var hosts = loadAll()
        hosts.removeAll { $0.hostname == host.hostname && $0.username == host.username }
        hosts.append(host)
        save(hosts)
    }

    public func remove(id: UUID) {
        var hosts = loadAll()
        hosts.removeAll { $0.id == id }
        save(hosts)
    }

    public func hosts(inGroups groups: [String]) -> [Host] {
        let all = loadAll()
        guard !groups.isEmpty else { return all }
        return all.filter { host in !Set(host.groups).isDisjoint(with: groups) }
    }
}
