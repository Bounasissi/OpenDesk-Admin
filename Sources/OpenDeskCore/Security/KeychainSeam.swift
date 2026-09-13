import Foundation
import Security

/// Keychain seam (Plan 03 §7.4). Implementation details land in Plan 05;
/// the interface is established now so services can depend on the port.
/// Reference IDs (CredentialID) are stored in SQLite; secrets never are.
public protocol SecretStore {
    /// Store a secret; returns the reference identifier to persist in SQLite.
    func store(secret: String, for reference: CredentialID, kind: String) throws
    /// Read a secret by reference. Returns nil if absent.
    func read(reference: CredentialID) throws -> String?
    /// Remove a secret (credential rotation/removal — Plan 05 A1.1).
    func delete(reference: CredentialID) throws
}

/// macOS Keychain-backed implementation of the seam (used from Plan 05 onward).
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    let service: String
    public init(service: String = "com.opendesk.credentials") {
        self.service = service
    }

    public func store(secret: String, for reference: CredentialID, kind: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(secret.utf8)
        attributes[kSecAttrDescription as String] = kind
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConfigurationError.invalidValue(key: "keychain", reason: "SecItemAdd status \(status)")
        }
    }

    public func read(reference: CredentialID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw ConfigurationError.invalidValue(key: "keychain", reason: "SecItemCopyMatching status \(status)")
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func delete(reference: CredentialID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConfigurationError.invalidValue(key: "keychain", reason: "SecItemDelete status \(status)")
        }
    }
}
