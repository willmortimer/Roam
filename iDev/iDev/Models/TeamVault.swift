import Foundation
import SwiftData

/// A team vault is a shared encrypted blob that multiple users access via a
/// common passphrase. Items tagged with this vault's ID are synced together.
@Model
final class TeamVaultRecord {
    @Attribute(.unique) var id: String
    var name: String
    var syncProviderType: String
    var syncConfigData: Data?
    var lastSyncDate: Date?
    var createdAt: Date

    init(
        name: String,
        syncProviderType: String,
        syncConfigData: Data? = nil
    ) {
        self.id = "vault_\(UUID().uuidString.prefix(8).lowercased())"
        self.name = name
        self.syncProviderType = syncProviderType
        self.syncConfigData = syncConfigData
        self.lastSyncDate = nil
        self.createdAt = Date()
    }
}
