import Foundation
import Security
import LocalAuthentication

/// Manages secrets in the iOS Keychain — SSH private keys and passphrases.
/// All operations are nonisolated since Keychain APIs are thread-safe.
nonisolated final class VaultService: Sendable {

    static let shared = VaultService()

    private let serviceName = "com.idev.vault"

    // MARK: - Private Key Storage

    /// Store a private key in the Keychain, optionally protected by biometrics.
    func storePrivateKey(id: String, data: Data, requireBiometrics: Bool = true) throws {
        // Delete existing item if any
        try? deletePrivateKey(id: id)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "key_\(id)",
            kSecValueData as String: data,
            kSecAttrLabel as String: "SSH Private Key: \(id)",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        if requireBiometrics {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                nil
            )
            if let access {
                query[kSecAttrAccessControl as String] = access
                query.removeValue(forKey: kSecAttrAccessible as String)
            }
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keychainError(status)
        }
    }

    /// Load a private key from the Keychain. May trigger Face ID/Touch ID.
    func loadPrivateKey(id: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "key_\(id)",
            kSecReturnData as String: true,
            kSecUseOperationPrompt as String: "Authenticate to access SSH key",
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw VaultError.keychainError(status)
        }

        return data
    }

    /// Delete a private key from the Keychain.
    func deletePrivateKey(id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "key_\(id)",
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychainError(status)
        }
    }

    // MARK: - Passphrase Storage

    /// Store a passphrase for an encrypted key.
    func storePassphrase(keyID: String, passphrase: String) throws {
        guard let data = passphrase.data(using: .utf8) else {
            throw VaultError.encodingError
        }

        try? deletePassphrase(keyID: keyID)

        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        )

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "passphrase_\(keyID)",
            kSecValueData as String: data,
            kSecAttrLabel as String: "Key Passphrase: \(keyID)",
        ]

        if let access {
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keychainError(status)
        }
    }

    /// Load a passphrase. May trigger biometric auth.
    func loadPassphrase(keyID: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "passphrase_\(keyID)",
            kSecReturnData as String: true,
            kSecUseOperationPrompt as String: "Authenticate to access key passphrase",
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let passphrase = String(data: data, encoding: .utf8) else {
            throw VaultError.keychainError(status)
        }

        return passphrase
    }

    /// Delete a stored passphrase.
    func deletePassphrase(keyID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "passphrase_\(keyID)",
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychainError(status)
        }
    }
}

// MARK: - Errors

nonisolated enum VaultError: Error, LocalizedError {
    case keychainError(OSStatus)
    case encodingError

    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            "Keychain error: \(status)"
        case .encodingError:
            "Failed to encode data"
        }
    }
}
