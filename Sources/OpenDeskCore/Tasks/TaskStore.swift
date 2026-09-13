import Foundation

/// Persistent store of saved task definitions with versioning (ARD "Saved Tasks").
/// Updates bump the task's version; history entries record each change.
public final class TaskStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "opendesk.taskstore")

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opendesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("tasks.json")
    }

    public func loadAll() -> [TaskDefinition] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder().decode([TaskDefinition].self, from: data)) ?? []
        }
    }

    public func save(_ tasks: [TaskDefinition]) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(tasks) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// Add a new task. Fails (returns nil) if a task with the same name exists.
    @discardableResult
    public func add(name: String, command: String, timeoutSeconds: Int = 30, targetGroups: [String] = []) -> TaskDefinition? {
        var tasks = loadAll()
        guard !tasks.contains(where: { $0.name == name }) else { return nil }
        let task = TaskDefinition(name: name, command: command, timeoutSeconds: timeoutSeconds, targetGroups: targetGroups)
        tasks.append(task)
        save(tasks)
        return task
    }

    /// Update a task's command/timeout/targets, bumping its version.
    @discardableResult
    public func update(id: UUID, command: String? = nil, timeoutSeconds: Int? = nil, targetGroups: [String]? = nil) -> TaskDefinition? {
        var tasks = loadAll()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        if let command { tasks[index].command = command }
        if let timeoutSeconds { tasks[index].timeoutSeconds = timeoutSeconds }
        if let targetGroups { tasks[index].targetGroups = targetGroups }
        tasks[index].version += 1
        save(tasks)
        return tasks[index]
    }

    public func remove(id: UUID) {
        var tasks = loadAll()
        tasks.removeAll { $0.id == id }
        save(tasks)
    }

    public func task(named name: String) -> TaskDefinition? {
        loadAll().first { $0.name == name }
    }
}
