import Foundation
import SwiftData
import iDevSSH

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
    func resolveCredential(for host: HostRecord, passphrase: String? = nil) async throws -> AuthCredential {
        let username = host.username

        switch host.authMethod {
        case .key:
            guard let keyRef = host.keyReference, !keyRef.isEmpty else {
                throw SSHError.authenticationFailed("No key reference configured for host")
            }

            // Trigger biometric auth before loading key
            let authenticated = try await authGateService.authenticate(
                reason: "Authenticate to use SSH key for \(host.alias)"
            )
            guard authenticated else {
                throw SSHError.authenticationFailed("Biometric authentication denied")
            }

            let keyData = try vaultService.loadPrivateKey(id: keyRef)

            // Try to load passphrase from Keychain if not provided
            let resolvedPassphrase: String?
            if let passphrase {
                resolvedPassphrase = passphrase
            } else {
                resolvedPassphrase = try? vaultService.loadPassphrase(keyID: keyRef)
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
}
