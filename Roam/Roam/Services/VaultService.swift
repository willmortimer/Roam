import Foundation
import Security
import LocalAuthentication

/// Manages secrets in the iOS Keychain — SSH private keys and passphrases.
/// All operations are nonisolated since Keychain APIs are thread-safe.
nonisolated final class VaultService: Sendable {

    static let shared = VaultService()

    private let serviceName = "com.roam.vault"

    private var supportsProtectedKeyAccess: Bool {
        AuthGateService.shared.supportsProtectedKeyAccess
    }

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

        if requireBiometrics && supportsProtectedKeyAccess {
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
    func loadPrivateKey(
        id: String,
        reason: String = "Authenticate to access SSH key"
    ) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "key_\(id)",
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: authenticationContext(reason: reason),
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

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "passphrase_\(keyID)",
            kSecValueData as String: data,
            kSecAttrLabel as String: "Key Passphrase: \(keyID)",
        ]

        if supportsProtectedKeyAccess {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                nil
            )

            if let access {
                query[kSecAttrAccessControl as String] = access
            } else {
                query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keychainError(status)
        }
    }

    /// Load a passphrase. May trigger biometric auth.
    func loadPassphrase(
        keyID: String,
        reason: String = "Authenticate to access key passphrase"
    ) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "passphrase_\(keyID)",
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: authenticationContext(reason: reason),
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

    // MARK: - Generic Secret Storage

    /// Store an arbitrary app secret without biometric prompts so it can be
    /// reused automatically for background or one-tap flows like sync.
    func storeSecret(id: String, secret: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw VaultError.encodingError
        }

        try? deleteSecret(id: id)

        let query = baseSecretQuery(
            account: "secret_\(id)",
            data: data,
            label: "App Secret: \(id)"
        )

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keychainError(status)
        }
    }

    /// Load a previously stored generic app secret.
    func loadSecret(id: String) throws -> String {
        let query = secretLookupQuery(account: "secret_\(id)")

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw VaultError.keychainError(status)
        }

        return secret
    }

    /// Delete a previously stored generic app secret.
    func deleteSecret(id: String) throws {
        try deleteGenericPassword(account: "secret_\(id)")
    }

    // MARK: - Helpers

    private func baseSecretQuery(account: String, data: Data, label: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }

    private func secretLookupQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
    }

    private func deleteGenericPassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychainError(status)
        }
    }

    private func authenticationContext(reason: String) -> LAContext {
        let context = LAContext()
        context.localizedReason = reason
        context.localizedFallbackTitle = "Use Passcode"
        return context
    }
}

// MARK: - Errors

nonisolated enum VaultError: Error, LocalizedError {
    case keychainError(OSStatus)
    case encodingError

    var errorDescription: String? {
        switch self {
        case .keychainError(let status):
            if status == errSecItemNotFound {
                return "The requested item was not found in Keychain. It may need to be re-imported on this device."
            }

            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }

            return "Keychain error: \(status)"
        case .encodingError:
            return "Failed to encode data"
        }
    }
}
