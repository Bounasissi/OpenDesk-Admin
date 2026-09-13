// OpenDeskCore — shared types for all OpenDesk Admin modules.
// API-first: UI, CLI, App Intents, and JSON API all consume these services.

import Foundation

// MARK: - Device

public struct Device: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var hostname: String
    public var ips: [String]
    public var macAddress: String?
    public var osVersion: String?
    public var architecture: String?
    public var rfbAvailable: Bool
    public var sshAvailable: Bool
    public var online: Bool
    public var lastSeen: Date?

    public init(
        id: UUID = UUID(),
        hostname: String,
        ips: [String] = [],
        macAddress: String? = nil,
        osVersion: String? = nil,
        architecture: String? = nil,
        rfbAvailable: Bool = false,
        sshAvailable: Bool = false,
        online: Bool = false,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.hostname = hostname
        self.ips = ips
        self.macAddress = macAddress
        self.osVersion = osVersion
        self.architecture = architecture
        self.rfbAvailable = rfbAvailable
        self.sshAvailable = sshAvailable
        self.online = online
        self.lastSeen = lastSeen
    }
}

// MARK: - Task

/// Universal task object. Every management operation is a Task:
/// Target Set + Action + Parameters + Execution Strategy + Schedule + Result.
public struct ODTask: Codable, Identifiable, Sendable, Equatable {
    public enum TaskType: String, Codable, Sendable, CaseIterable {
        case executeCommand = "execute_command"
        case runScript = "run_script"
        case copyFiles = "copy_files"
        case fetchFiles = "fetch_files"
        case installPackage = "install_package"
        case inventoryCollect = "inventory_collect"
        case wake, sleep, restart, shutdown, logout
        case lockScreen = "lock_screen"
        case sendMessage = "send_message"
        case fileSearch = "file_search"
        case softwareCompare = "software_compare"
    }

    public enum Status: String, Codable, Sendable {
        case created, queued, available, offlineWait = "offline_wait"
        case dispatched, running, success, failed, cancelled
    }

    public enum ExecutionMode: String, Codable, Sendable {
        case immediate
        case onReconnect = "on_reconnect"
        case onPredicate = "on_predicate"
    }

    public struct Execution: Codable, Sendable, Equatable {
        public var mode: ExecutionMode
        public init(mode: ExecutionMode = .immediate) { self.mode = mode }
    }

    public let id: UUID
    public let type: TaskType
    public var targets: [UUID]
    public var parameters: [String: String]
    public var execution: Execution
    public var status: Status
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var results: [String: String]

    public init(
        id: UUID = UUID(),
        type: TaskType,
        targets: [UUID],
        parameters: [String: String] = [:],
        execution: Execution = Execution(),
        status: Status = .created,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        results: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.targets = targets
        self.parameters = parameters
        self.execution = execution
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.results = results
    }
}

// MARK: - Task Result

public struct TaskResult: Codable, Sendable, Equatable {
    public let deviceID: UUID
    public let status: ODTask.Status
    public let exitCode: Int?
    public let stdout: String?
    public let stderr: String?
    public let error: String?

    public init(
        deviceID: UUID,
        status: ODTask.Status,
        exitCode: Int? = nil,
        stdout: String? = nil,
        stderr: String? = nil,
        error: String? = nil
    ) {
        self.deviceID = deviceID
        self.status = status
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.error = error
    }
}

// MARK: - Application Service Protocol (API-first boundary)

/// UI, CLI, Shortcuts, and JSON API all call this protocol — one implementation,
/// multiple interfaces. No module above this layer imports SwiftUI.
public protocol DeviceManaging: Sendable {
    func restart(_ devices: [UUID]) async throws -> [TaskResult]
    func shutdown(_ devices: [UUID]) async throws -> [TaskResult]
    func execute(command: String, on devices: [UUID]) async throws -> [TaskResult]
}

// MARK: - Errors

public enum OpenDeskError: Error, Sendable, Equatable {
    case deviceNotFound(UUID)
    case authenticationFailed(String)
    case transportUnavailable(String)
    case taskInvalid(String)
}
