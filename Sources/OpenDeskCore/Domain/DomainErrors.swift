import Foundation

/// Marker protocol for all OpenDesk typed errors (Plan 03 §6).
/// Every error carries a user-safe description that is safe to render/redact,
/// distinct from internal diagnostics (feeds Plan 18 redaction rules).
public protocol OpenDeskError: Error, CustomStringConvertible {
    var userSafeDescription: String { get }
}

extension OpenDeskError {
    /// Internal diagnostics form — deliberately differs from the user-safe text
    /// and is intended for OSLog/diagnostic bundles (Plan 18), never for UI.
    /// Describes the dynamic TYPE only: `String(describing: self)` would recurse
    /// through this very witness and overflow the stack.
    public var description: String {
        let caseName = Mirror(reflecting: self).children.first?.label ?? "base"
        return "<internal: \(String(describing: type(of: self))).\(caseName)>"
    }
}

// MARK: - Transport

public enum TransportError: OpenDeskError, Sendable, Equatable {
    case connectionRefused(host: String)
    case timedOut(host: String, seconds: Int)
    case tunnelFailed(reason: String)

    public var userSafeDescription: String {
        switch self {
        case .connectionRefused(let host): return "Could not connect to \(host). Check that the Mac is reachable and management services are enabled."
        case .timedOut(let host, let seconds): return "Connection to \(host) timed out after \(seconds)s."
        case .tunnelFailed: return "The secure connection tunnel could not be established."
        }
    }
}

// MARK: - Authentication / Authorization

public enum AuthenticationError: OpenDeskError, Sendable, Equatable {
    case hostKeyMismatch(fingerprint: String)
    case badCredentials(user: String)
    case vncAuthenticationFailed

    public var userSafeDescription: String {
        switch self {
        case .hostKeyMismatch: return "The remote Mac's identity changed since first connection. Verify the host key before continuing."
        case .badCredentials: return "Authentication failed. Check the username and stored credentials."
        case .vncAuthenticationFailed: return "Screen-sharing authentication failed."
        }
    }
}

public enum AuthorizationError: OpenDeskError, Sendable, Equatable {
    case permission(RBACPrivilege)

    public var userSafeDescription: String {
        switch self {
        case .permission(let privilege): return "Operation not permitted: \(privilege.displayName)."
        }
    }
}

// MARK: - Task execution

public enum TaskExecutionError: OpenDeskError, Sendable, Equatable {
    case nonZeroExit(code: Int32, taskID: TaskID)
    case targetOffline(taskID: TaskID)
    case deadlineExceeded(taskID: TaskID)

    public var userSafeDescription: String {
        switch self {
        case .nonZeroExit(let code, _): return "The command failed on the remote Mac (exit code \(code))."
        case .targetOffline: return "The target Mac is currently offline; the task will run when it reconnects."
        case .deadlineExceeded: return "The task did not complete before its deadline."
        }
    }
}

// MARK: - Persistence

public enum PersistenceError: OpenDeskError, Sendable, Equatable {
    case connectionFailed(String)
    case migrationFailed(step: Int, reason: String)
    case schemaVersionMismatch
    case queryFailed(String)
    case terminalStateImmutable
    case duplicateIdempotencyKey

    public var userSafeDescription: String {
        switch self {
        case .connectionFailed: return "The local database could not be opened. Try restarting OpenDesk."
        case .migrationFailed: return "The local database could not be updated. A backup will be offered before retry."
        case .schemaVersionMismatch: return "The local database was written by a newer version of OpenDesk."
        case .queryFailed: return "A local storage operation failed. Details are in diagnostics."
        case .terminalStateImmutable: return "The task already finished; its result cannot change."
        case .duplicateIdempotencyKey: return "An identical task is already recorded."
        }
    }
}

// MARK: - Protocol

public enum ProtocolError: OpenDeskError, Sendable, Equatable {
    case violation(String)
    case unsupportedVersion(String)

    public var userSafeDescription: String {
        switch self {
        case .violation: return "The remote Mac sent an unexpected protocol response."
        case .unsupportedVersion: return "The remote Mac uses a protocol version this app cannot negotiate."
        }
    }
}

// MARK: - Permissions (OS-level)

public enum PermissionError: OpenDeskError, Sendable, Equatable {
    case screenRecordingNotGranted
    case accessibilityNotGranted
    case notificationsNotGranted

    public var userSafeDescription: String {
        switch self {
        case .screenRecordingNotGranted: return "Screen Recording permission is required. Grant it in System Settings."
        case .accessibilityNotGranted: return "Accessibility permission is required for remote control input."
        case .notificationsNotGranted: return "Notification permission is required to inform remote users."
        }
    }
}

// MARK: - Configuration

public enum ConfigurationError: OpenDeskError, Sendable, Equatable {
    case missingValue(String)
    case invalidValue(key: String, reason: String)

    public var userSafeDescription: String {
        switch self {
        case .missingValue(let key): return "Required setting is missing: \(key)."
        case .invalidValue(let key, _): return "The setting '\(key)' is invalid."
        }
    }
}

// MARK: - RBAC privilege model (Plan 05 A1.2 — full v1 set)

public enum RBACPrivilege: String, Codable, Sendable, CaseIterable {
    case observe
    case control
    case clipboard
    case filesRead
    case filesWrite
    case install
    case execute
    case power
    case lock
    case message
    case inventory
    case configuration
    case administration

    public var displayName: String {
        switch self {
        case .filesRead: return "read files"
        case .filesWrite: return "write files"
        case .execute: return "run commands"
        default: return rawValue
        }
    }
}
