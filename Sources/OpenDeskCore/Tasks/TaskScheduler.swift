import Foundation

/// A recurring fleet task schedule (ARD "Recurring Tasks" equivalent).
public struct ScheduleDefinition: Codable, Hashable, Identifiable, Sendable {
    public enum Trigger: Codable, Hashable, Sendable {
        /// Run every N seconds while the scheduler is running.
        case interval(seconds: Int)
        /// Run daily at HH:mm local time.
        case daily(hour: Int, minute: Int)
    }

    public var id: UUID
    public var name: String
    public var taskName: String       // saved task name (TaskStore) to run
    public var targetGroups: [String]
    public var trigger: Trigger
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        taskName: String,
        targetGroups: [String] = [],
        trigger: Trigger,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.taskName = taskName
        self.targetGroups = targetGroups
        self.trigger = trigger
        self.enabled = enabled
    }
}

/// Computes when a schedule is next due. Pure function, unit-testable.
public enum ScheduleMath {
    /// Seconds from `from` until the schedule's next due time.
    /// - Returns: nil for disabled schedules.
    public static func secondsUntilDue(_ schedule: ScheduleDefinition, from: Date = Date(), calendar: Calendar = .current) -> TimeInterval? {
        guard schedule.enabled else { return nil }
        switch schedule.trigger {
        case .interval(let seconds):
            return TimeInterval(max(1, seconds))
        case .daily(let hour, let minute):
            let components = calendar.dateComponents([.year, .month, .day], from: from)
            var dueComponents = components
            dueComponents.hour = hour
            dueComponents.minute = minute
            dueComponents.second = 0
            guard var due = calendar.date(from: dueComponents) else { return nil }
            if due <= from {
                due = calendar.date(byAdding: .day, value: 1, to: due) ?? due
            }
            return due.timeIntervalSince(from)
        }
    }

    /// Human-readable description of the trigger.
    public static func describe(_ trigger: ScheduleDefinition.Trigger) -> String {
        switch trigger {
        case .interval(let seconds):
            return "every \(seconds)s"
        case .daily(let hour, let minute):
            return String(format: "daily at %02d:%02d", hour, minute)
        }
    }
}

/// Persistent store of schedule definitions (JSON at ~/.opendesk/schedules.json).
public final class ScheduleStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "opendesk.schedulestore")

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opendesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("schedules.json")
    }

    public func loadAll() -> [ScheduleDefinition] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder().decode([ScheduleDefinition].self, from: data)) ?? []
        }
    }

    public func save(_ schedules: [ScheduleDefinition]) {
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(schedules) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    @discardableResult
    public func add(_ schedule: ScheduleDefinition) -> Bool {
        var all = loadAll()
        guard !all.contains(where: { $0.name == schedule.name }) else { return false }
        all.append(schedule)
        save(all)
        return true
    }

    public func remove(named name: String) -> Bool {
        var all = loadAll()
        let before = all.count
        all.removeAll { $0.name == name }
        save(all)
        return all.count < before
    }

    public func setEnabled(_ enabled: Bool, named name: String) -> Bool {
        var all = loadAll()
        guard let index = all.firstIndex(where: { $0.name == name }) else { return false }
        all[index].enabled = enabled
        save(all)
        return true
    }
}

/// In-process scheduler: executes due schedules against the fleet while the
/// host process lives (CLI `schedule daemon` or long-running GUI session).
/// For boot-persistent scheduling, a launchd plist wrapping the daemon is
/// documented in docs/ROADMAP.md.
public final class TaskScheduler: @unchecked Sendable {
    private let scheduleStore: ScheduleStore
    private let taskStore: TaskStore
    private let hostRegistry: HostRegistry
    private let engine: TaskEngine
    private var timer: DispatchSourceTimer?
    private let stateLock = NSLock()
    private var nextDue: [UUID: Date] = [:]
    private var runningFlag = false

    public var onRun: ((String, [TaskResult]) -> Void)?

    public init(
        scheduleStore: ScheduleStore = ScheduleStore(),
        taskStore: TaskStore = TaskStore(),
        hostRegistry: HostRegistry = HostRegistry(),
        engine: TaskEngine = TaskEngine()
    ) {
        self.scheduleStore = scheduleStore
        self.taskStore = taskStore
        self.hostRegistry = hostRegistry
        self.engine = engine
    }

    public func start() {
        stateLock.lock()
        if runningFlag {
            stateLock.unlock()
            return
        }
        runningFlag = true
        stateLock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5) // check every 5s
        timer.setEventHandler { [weak self] in
            self?.checkAndRun()
        }
        timer.resume()
        stateLock.lock()
        self.timer = timer
        stateLock.unlock()
    }

    public func stop() {
        stateLock.lock()
        timer?.cancel()
        timer = nil
        runningFlag = false
        stateLock.unlock()
    }

    /// Run one schedule immediately, bypassing its due time.
    @discardableResult
    public func runNow(named scheduleName: String) -> [TaskResult]? {
        guard let schedule = scheduleStore.loadAll().first(where: { $0.name == scheduleName }) else { return nil }
        return execute(schedule)
    }

    func checkAndRun() {
        let schedules = scheduleStore.loadAll()
        let now = Date()
        for schedule in schedules {
            guard let seconds = ScheduleMath.secondsUntilDue(schedule, from: now) else { continue }
            stateLock.lock()
            let due = nextDue[schedule.id] ?? .distantPast
            let shouldRun = now >= due
            stateLock.unlock()
            if shouldRun {
                stateLock.lock()
                nextDue[schedule.id] = now.addingTimeInterval(seconds)
                stateLock.unlock()
                _ = execute(schedule)
            }
        }
    }

    private func execute(_ schedule: ScheduleDefinition) -> [TaskResult] {
        guard let task = taskStore.task(named: schedule.taskName) else { return [] }
        let hosts = hostRegistry.hosts(inGroups: schedule.targetGroups)
        let results = engine.runAcrossHosts(task.command, hosts: hosts, timeoutSeconds: task.timeoutSeconds)
        onRun?(schedule.name, results)
        return results
    }
}
