import Foundation
import SwiftData

@Model
final class TunnelRecord {
    @Attribute(.unique) var id: String
    var workspaceReference: String?
    var name: String
    var direction: TunnelDirection
    var bindHost: String
    var bindPort: Int
    var remoteHost: String
    var remotePort: Int
    var isActive: Bool
    var createdAt: Date

    init(
        workspaceReference: String? = nil,
        name: String,
        direction: TunnelDirection = .local,
        bindHost: String = "127.0.0.1",
        bindPort: Int,
        remoteHost: String = "127.0.0.1",
        remotePort: Int
    ) {
        self.id = "tun_\(UUID().uuidString.prefix(8).lowercased())"
        self.workspaceReference = workspaceReference
        self.name = name
        self.direction = direction
        self.bindHost = bindHost
        self.bindPort = bindPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.isActive = false
        self.createdAt = Date()
    }
}

nonisolated enum TunnelDirection: String, Codable, Sendable {
    case local
    case remote
}
