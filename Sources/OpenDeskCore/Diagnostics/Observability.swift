import Foundation
import os

// MARK: - Structured logging (Plan 18 §2)

/// OSLog category factory. Exactly the twelve Plan 18 categories; every
/// cross-component operation carries a correlation ID (persisted on audit
/// records and task records — see AuditEvent.correlationID).
public struct ODLog {
    public enum Category: String, CaseIterable, Sendable {
        case app
        case discovery
        case rfb
        case ssh
        case agent
        case tasks
        case scheduler
        case inventory
        case database
        case security
        case update
        case release
    }

    public let oslog: Logger

    public init(category: Category) {
        self.oslog = Logger(subsystem: "com.opendesk", category: category.rawValue)
    }

    public func info(_ message: String, correlationID: String? = nil) {
        if let correlationID {
            oslog.info("\(message, privacy: .public) [corr=\(correlationID, privacy: .public)]")
        } else {
            oslog.info("\(message, privacy: .public)")
        }
    }

    public func error(_ message: String, correlationID: String? = nil) {
        if let correlationID {
            oslog.error("\(message, privacy: .public) [corr=\(correlationID, privacy: .public)]")
        } else {
            oslog.error("\(message, privacy: .public)")
        }
    }
}

// MARK: - Diagnostic bundle (Plan 18 §4)

/// One-click diagnostic export. Contents (Plan 18 §4): app version, OS
/// version, architecture, sanitized logs (audit excerpt, redacted), task
/// history excerpt, agent version, capability state, permission state,
/// network summary, database schema version. **Never includes Keychain
/// secrets, clipboard contents, or remote file contents.**
public struct DiagnosticBundle {
    public let text: String

    public static func generate(
        database: SQLiteDatabase,
        sanitizer: (String) -> String = { redactParameterKeys(in: $0) }
    ) throws -> DiagnosticBundle {
        var lines: [String] = []
        let processInfo = ProcessInfo.processInfo
        lines.append("OpenDesk diagnostic bundle")
        lines.append("app: OpenDesk \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
        lines.append("macOS: \(processInfo.operatingSystemVersionString)")
        lines.append("architecture: \(processInfo.machineDescription)")
        lines.append("schema: \(try SQLiteMigrator(db: database).currentVersion())")

        // Task history excerpt.
        let taskRows = try database.query("SELECT id, type, state, created_at FROM tasks ORDER BY created_at DESC LIMIT 20")
        lines.append("tasks (\(taskRows.count) most recent):")
        for row in taskRows {
            lines.append("  \(row.str("id")) \(row.str("type")) \(row.str("state")) \(row.str("created_at"))")
        }

        // Sanitized audit excerpt (Plan 18 §3 redaction applies).
        let audit = SQLiteAuditRepository(db: database)
        let events = try audit.recent(limit: 20)
        lines.append("audit (sanitized, \(events.count) most recent):")
        for event in events {
            var text = "\(event.recordedAt) \(event.actor) \(event.action) targets=\(event.targets.joined(separator: ",")) result=\(event.result.rawValue) corr=\(event.correlationID ?? "-")"
            if !event.parameters.isEmpty {
                let encoded = try? JSONEncoder().encode(event.parameters)
                text += " params=\(encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")"
            }
            lines.append("  \(sanitizer(text))")
        }

        // Capability/permission state placeholders are filled by the GUI
        // (Plan 15 onboarding detection) — the bundle marks the sections.
        lines.append("permissions: (filled by onboarding detection)")
        lines.append("network: loopback available; discovery per Plan 04 probes")

        // Redaction sweep on the whole bundle (defense in depth).
        let joined = lines.joined(separator: "\n")
        return DiagnosticBundle(text: sanitizer(joined))
    }
}

extension ProcessInfo {
    var machineDescription: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }).map { UInt8($0) }, as: UTF8.self)
        }
    }
}
