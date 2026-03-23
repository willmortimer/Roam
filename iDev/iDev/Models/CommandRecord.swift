import Foundation
import SwiftData

// MARK: - Command Source

nonisolated enum CommandSource: String, Codable, Sendable {
    case terminal
    case snippet
    case helperSendKeys
}

// MARK: - Command Record

@Model
final class CommandRecord {
    @Attribute(.unique) var id: String
    var workspaceReference: String
    var command: String
    var paneRole: PaneRole?
    var paneID: String?
    var timestamp: Date
    var source: CommandSource
    var exitCode: Int?

    init(
        workspaceReference: String,
        command: String,
        paneRole: PaneRole? = nil,
        paneID: String? = nil,
        source: CommandSource = .terminal,
        exitCode: Int? = nil
    ) {
        self.id = "cmd_\(UUID().uuidString.prefix(8).lowercased())"
        self.workspaceReference = workspaceReference
        self.command = command
        self.paneRole = paneRole
        self.paneID = paneID
        self.timestamp = Date()
        self.source = source
        self.exitCode = exitCode
    }
}
