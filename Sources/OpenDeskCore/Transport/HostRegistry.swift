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

/// Persistent roster of managed hosts with swappable storage backends.
/// Default: JSON file. For multi-admin setups pass a shared SQLiteBackend.
public final class HostRegistry: @unchecked Sendable {
    private let backend: RegistryBackend

    public init(directory: URL? = nil, backend: RegistryBackend? = nil) {
        if let backend {
            self.backend = backend
        } else {
            let base = directory ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".opendesk", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.backend = JSONFileBackend(fileURL: base.appendingPathComponent("hosts.json"))
        }
    }

    public func loadAll() -> [Host] {
        backend.loadAll()
    }

    public func save(_ hosts: [Host]) {
        backend.save(hosts)
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
