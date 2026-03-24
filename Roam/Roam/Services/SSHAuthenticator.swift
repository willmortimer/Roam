import Foundation
import SwiftData
import Security
import RoamSSH

/// Resolves a HostRecord's auth method into an SSH credential and authenticates.
@Observable
final class SSHAuthenticator {
    private let vaultService: VaultService
    private let authGateService: AuthGateService

    init(vaultService: VaultService, authGateService: AuthGateService) {
        self.vaultService = vaultService
        self.authGateService = authGateService
    }

    /// Build an AuthCredential from a HostRecord's configuration.
    func resolveCredential(
        for host: HostRecord,
        modelContext: ModelContext? = nil,
        passphrase: String? = nil
    ) async throws -> AuthCredential {
        let username = host.username

        switch host.authMethod {
        case .key:
            let resolvedKey = try resolvedKeyReference(for: host, modelContext: modelContext)

            let requireForKeys = UserDefaults.standard.object(forKey: "biometric_requireForKeys") as? Bool ?? true
            if requireForKeys && authGateService.supportsProtectedKeyAccess {
                let authenticated = try await authGateService.authenticate(
                    reason: "Authenticate to use SSH key for \(host.alias)"
                )
                guard authenticated else {
                    throw SSHError.authenticationFailed("Authentication denied")
                }
            }

            let keyData: Data
            do {
                keyData = try vaultService.loadPrivateKey(
                    id: resolvedKey.keychainReference,
                    reason: "Authenticate to access SSH key for \(host.alias)"
                )
            } catch let error as VaultError {
                throw keyLoadError(error, keyName: resolvedKey.displayName, hostAlias: host.alias)
            } catch {
                throw SSHError.authenticationFailed(error.localizedDescription)
            }

            // Try to load passphrase from Keychain if not provided
            let resolvedPassphrase: String?
            if let passphrase {
                resolvedPassphrase = passphrase
            } else {
                resolvedPassphrase = try? vaultService.loadPassphrase(
                    keyID: resolvedKey.keychainReference,
                    reason: "Authenticate to access the SSH key passphrase for \(host.alias)"
                )
            }

            if let generatedKey = generatedKeyMaterial(for: resolvedKey, storedKeyData: keyData) {
                return AuthCredential(
                    username: username,
                    method: .generatedKey(generatedKey)
                )
            }

            return AuthCredential(
                username: username,
                method: .privateKey(data: keyData, passphrase: resolvedPassphrase)
            )

        case .password:
            guard let passphrase, !passphrase.isEmpty else {
                throw SSHError.authenticationFailed("Password required")
            }
            return AuthCredential(
                username: username,
                method: .password(passphrase)
            )

        case .agent:
            // SSH agent forwarding not implemented in Phase 1
            throw SSHError.authenticationFailed("SSH agent auth not yet supported")
        }
    }

    private func resolvedKeyReference(
        for host: HostRecord,
        modelContext: ModelContext?
    ) throws -> ResolvedSSHKeyReference {
        guard let hostReference = host.keyReference, !hostReference.isEmpty else {
            throw SSHError.authenticationFailed("No SSH key is configured for this host")
        }

        guard let modelContext else {
            return ResolvedSSHKeyReference(
                keychainReference: hostReference,
                displayName: hostReference,
                keyType: nil,
                publicKeyData: nil
            )
        }

        let predicate = #Predicate<SSHKeyRecord> { key in
            key.id == hostReference || key.keychainReference == hostReference
        }
        let descriptor = FetchDescriptor<SSHKeyRecord>(predicate: predicate)

        if let keyRecord = try modelContext.fetch(descriptor).first {
            return ResolvedSSHKeyReference(
                keychainReference: keyRecord.keychainReference,
                displayName: keyRecord.label,
                keyType: keyRecord.keyType,
                publicKeyData: keyRecord.publicKeyData
            )
        }

        return ResolvedSSHKeyReference(
            keychainReference: hostReference,
            displayName: hostReference,
            keyType: nil,
            publicKeyData: nil
        )
    }

    private func generatedKeyMaterial(
        for resolvedKey: ResolvedSSHKeyReference,
        storedKeyData: Data
    ) -> AuthCredential.GeneratedKey? {
        guard let keyType = resolvedKey.keyType,
              let publicKeyData = resolvedKey.publicKeyData else {
            return nil
        }

        switch keyType {
        case .ed25519:
            guard storedKeyData.count == 32, publicKeyData.count == 32 else {
                return nil
            }
            return .ed25519(publicKey: publicKeyData, privateKey: storedKeyData)

        case .ecdsaP256:
            guard publicKeyData.count == 65 else {
                return nil
            }

            if storedKeyData.count == 32 {
                return .ecdsaP256(publicKey: publicKeyData, privateKey: storedKeyData)
            }

            if storedKeyData.count == 97, storedKeyData.starts(with: publicKeyData) {
                return .ecdsaP256(
                    publicKey: publicKeyData,
                    privateKey: Data(storedKeyData.suffix(32))
                )
            }

            return nil

        case .rsa4096:
            return nil
        }
    }

    private func keyLoadError(_ error: VaultError, keyName: String, hostAlias: String) -> SSHError {
        switch error {
        case .keychainError(let status) where status == errSecItemNotFound:
            return .authenticationFailed(
                "SSH key '\(keyName)' is not available on this device. Re-import it in Vault or edit \(hostAlias) to choose another key or password auth."
            )
        default:
            return .authenticationFailed(error.localizedDescription)
        }
    }
}

private struct ResolvedSSHKeyReference {
    let keychainReference: String
    let displayName: String
    let keyType: SSHKeyType?
    let publicKeyData: Data?
}
