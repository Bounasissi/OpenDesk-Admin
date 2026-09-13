import Foundation

// MARK: - Transfer path validation (Plan 16 §3)

public enum PathValidationError: OpenDeskError, Equatable {
    case escapesBase
    case homeReference

    public var userSafeDescription: String {
        switch self {
        case .escapesBase: return "The destination path escapes the allowed location."
        case .homeReference: return "Paths referencing the home directory are not permitted here."
        }
    }
}

/// Reject remote transfer paths that escape the intended staging base
/// (`..` traversal) or reference the home directory.
public func validateTransferPath(remotePath: String, base: String) throws {
    let resolved = (remotePath as NSString).standardizingPath
    let resolvedBase = (base as NSString).standardizingPath
    guard resolved.hasPrefix(resolvedBase + "/") || resolved == resolvedBase else {
        throw PathValidationError.escapesBase
    }
    if resolved.contains("/~/") || resolved.contains("~") {
        throw PathValidationError.homeReference
    }
}
