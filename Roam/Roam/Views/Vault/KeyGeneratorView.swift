import SwiftUI
import SwiftData
import CryptoKit

struct KeyGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var keyType: SSHKeyType = .ed25519
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var generatedPublicKey: String?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Key Details") {
                TextField("Label", text: $label)
                Picker("Type", selection: $keyType) {
                    Text("Ed25519").tag(SSHKeyType.ed25519)
                    Text("RSA 4096").tag(SSHKeyType.rsa4096)
                    Text("ECDSA P-256").tag(SSHKeyType.ecdsaP256)
                }
            }

            Section("Passphrase (Optional)") {
                SecureField("Passphrase", text: $passphrase)
                if !passphrase.isEmpty {
                    SecureField("Confirm Passphrase", text: $confirmPassphrase)
                }
            }

            if let publicKey = generatedPublicKey {
                Section("Generated Public Key") {
                    Text(publicKey)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy to Clipboard") {
                        UIPasteboard.general.string = publicKey
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.Roam.danger)
                }
            }
        }
        .navigationTitle("Generate SSH Key")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Generate") {
                    generate()
                }
                .disabled(label.isEmpty || isGenerating || (!passphrase.isEmpty && passphrase != confirmPassphrase))
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                let record = try await generateKey()
                modelContext.insert(record)
                generatedPublicKey = record.publicKeyAuthorizedFormat
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    private func generateKey() async throws -> SSHKeyRecord {
        switch keyType {
        case .ed25519:
            return try generateEd25519Key()
        case .ecdsaP256:
            return try generateECDSAKey()
        case .rsa4096:
            // RSA generation via CryptoKit is not straightforward;
            // will be implemented with libssh2 in Workstream B
            throw KeyGenError.unsupportedType
        }
    }

    private func generateEd25519Key() throws -> SSHKeyRecord {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let publicKeyRaw = publicKey.rawRepresentation
        let privateKeyRaw = privateKey.rawRepresentation

        // Build authorized_keys format: "ssh-ed25519 <base64>"
        let keyTypeBytes = "ssh-ed25519".data(using: .utf8)!
        var wireFormat = Data()
        wireFormat.appendSSHString(keyTypeBytes)
        wireFormat.appendSSHString(publicKeyRaw)
        let authorizedFormat = "ssh-ed25519 \(wireFormat.base64EncodedString()) \(label)"

        let keychainRef = "ed25519_\(UUID().uuidString.prefix(8))"
        let requireBio = UserDefaults.standard.object(forKey: "biometric_requireForKeys") as? Bool ?? true
        try VaultService.shared.storePrivateKey(
            id: keychainRef,
            data: privateKeyRaw,
            requireBiometrics: requireBio
        )

        return SSHKeyRecord(
            label: label,
            keyType: .ed25519,
            publicKeyData: publicKeyRaw,
            publicKeyAuthorizedFormat: authorizedFormat,
            isEncrypted: !passphrase.isEmpty,
            keychainReference: keychainRef
        )
    }

    private func generateECDSAKey() throws -> SSHKeyRecord {
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let publicKeyRaw = publicKey.x963Representation
        // Store the private scalar, not the x9.63 public-key-prefixed form.
        let privateKeyRaw = privateKey.rawRepresentation

        let keyTypeBytes = "ecdsa-sha2-nistp256".data(using: .utf8)!
        let curveBytes = "nistp256".data(using: .utf8)!
        var wireFormat = Data()
        wireFormat.appendSSHString(keyTypeBytes)
        wireFormat.appendSSHString(curveBytes)
        wireFormat.appendSSHString(publicKeyRaw)
        let authorizedFormat = "ecdsa-sha2-nistp256 \(wireFormat.base64EncodedString()) \(label)"

        let keychainRef = "ecdsa_\(UUID().uuidString.prefix(8))"
        let requireBio = UserDefaults.standard.object(forKey: "biometric_requireForKeys") as? Bool ?? true
        try VaultService.shared.storePrivateKey(
            id: keychainRef,
            data: privateKeyRaw,
            requireBiometrics: requireBio
        )

        return SSHKeyRecord(
            label: label,
            keyType: .ecdsaP256,
            publicKeyData: publicKeyRaw,
            publicKeyAuthorizedFormat: authorizedFormat,
            isEncrypted: !passphrase.isEmpty,
            keychainReference: keychainRef
        )
    }
}

// MARK: - SSH Wire Format Helper

extension Data {
    mutating func appendSSHString(_ data: Data) {
        var length = UInt32(data.count).bigEndian
        append(Data(bytes: &length, count: 4))
        append(data)
    }
}

nonisolated enum KeyGenError: Error, LocalizedError {
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            "RSA key generation requires libssh2 (available after SSH transport integration)"
        }
    }
}
