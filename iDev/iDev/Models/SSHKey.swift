import Foundation
import SwiftData

@Model
final class SSHKeyRecord {
    @Attribute(.unique) var id: String
    var label: String
    var keyType: SSHKeyType
    var publicKeyData: Data
    var publicKeyAuthorizedFormat: String
    var isEncrypted: Bool
    var keychainReference: String
    var createdAt: Date
    var notes: String

    init(
        label: String,
        keyType: SSHKeyType,
        publicKeyData: Data,
        publicKeyAuthorizedFormat: String,
        isEncrypted: Bool = false,
        keychainReference: String,
        notes: String = ""
    ) {
        self.id = "key_\(UUID().uuidString.prefix(8).lowercased())"
        self.label = label
        self.keyType = keyType
        self.publicKeyData = publicKeyData
        self.publicKeyAuthorizedFormat = publicKeyAuthorizedFormat
        self.isEncrypted = isEncrypted
        self.keychainReference = keychainReference
        self.createdAt = Date()
        self.notes = notes
    }
}

nonisolated enum SSHKeyType: String, Codable, CaseIterable, Sendable {
    case ed25519
    case rsa4096
    case ecdsaP256
}
