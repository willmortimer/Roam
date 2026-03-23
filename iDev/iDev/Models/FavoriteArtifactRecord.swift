import Foundation
import SwiftData

/// Tracks pinned/favorite artifacts for quick access in the artifact browser.
@Model
final class FavoriteArtifactRecord {
    @Attribute(.unique) var id: String
    var workspaceReference: String
    var remotePath: String
    var kind: String
    var label: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        workspaceReference: String,
        remotePath: String,
        kind: String,
        label: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.workspaceReference = workspaceReference
        self.remotePath = remotePath
        self.kind = kind
        self.label = label
        self.createdAt = createdAt
    }
}
