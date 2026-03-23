import Foundation
import SwiftData

@Model
final class PreviewRecord {
    @Attribute(.unique) var id: String
    var workspaceReference: String?
    var tunnelReference: String?
    var displayName: String
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
    var scheme: String
    var processLabel: String?
    var healthState: PreviewHealth
    var autoReconnect: Bool
    var lastAccessed: Date?

    init(
        workspaceReference: String? = nil,
        tunnelReference: String? = nil,
        displayName: String,
        localPort: Int,
        remoteHost: String = "127.0.0.1",
        remotePort: Int,
        scheme: String = "http",
        processLabel: String? = nil,
        autoReconnect: Bool = true
    ) {
        self.id = "prev_\(UUID().uuidString.prefix(8).lowercased())"
        self.workspaceReference = workspaceReference
        self.tunnelReference = tunnelReference
        self.displayName = displayName
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.scheme = scheme
        self.processLabel = processLabel
        self.healthState = .unknown
        self.autoReconnect = autoReconnect
        self.lastAccessed = nil
    }
}

nonisolated enum PreviewHealth: String, Codable, Sendable {
    case unknown
    case healthy
    case degraded
    case disconnected
}
