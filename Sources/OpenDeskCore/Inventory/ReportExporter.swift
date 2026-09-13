import Foundation

/// Exports task results and machine reports as CSV or JSON for archiving
/// and spreadsheet import.
public enum ReportExporter {
    // MARK: - TaskResult export

    public static func resultsCSV(_ results: [TaskResult]) -> String {
        var rows = ["host,exit_code,succeeded,duration_ms,started_at,stdout,stderr,error"]
        for r in results {
            let fields = [
                r.host,
                String(r.exitCode),
                r.succeeded ? "1" : "0",
                String(r.durationMs),
                ISO8601DateFormatter().string(from: r.startedAt),
                r.stdout,
                r.stderr,
                r.errorDescription ?? "",
            ]
            rows.append(fields.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    public static func resultsJSON(_ results: [TaskResult]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(results)
    }

    // MARK: - MachineReport export

    public static func reportsCSV(_ reports: [MachineReport]) -> String {
        var rows = ["hostname,model,architecture,os_version,serial,memory_mb,app_count,collected_at"]
        for report in reports {
            let fields = [
                report.hostname,
                report.modelName,
                report.chipArchitecture,
                report.osVersion,
                report.serialNumber,
                String(report.totalMemoryMB),
                ISO8601DateFormatter().string(from: report.collectedAt),
            ]
            rows.append(fields.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    public static func reportsJSON(_ reports: [MachineReport]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(reports)
    }

    /// Inventory app list export (one row per installed app per machine).
    public static func appsCSV(_ reports: [MachineReport]) -> String {
        var rows = ["hostname,app_name,app_version,app_path"]
        for report in reports {
            for app in report.installedApps {
                let fields = [report.hostname, app.name, app.version, app.path]
                rows.append(fields.map(csvEscape).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    /// RFC 4180 quoting: wrap in double quotes, escape embedded quotes.
    static func csvEscape(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\r") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
