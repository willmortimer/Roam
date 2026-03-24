import Foundation
import SwiftData

@Model
final class WorkspaceRecord {
    @Attribute(.unique) var id: String
    var name: String
    var descriptionText: String
    var environment: String
    var hostReference: String
    var shell: String
    var repoPath: String
    var startupDir: String
    var tmuxSessionName: String
    var tmuxLayoutTemplate: String?
    var tmuxPanesData: Data?
    var preferredAgentCommand: String?
    var savedForwardsData: Data?
    var previewRulesData: Data?
    var artifactRoots: [String]
    var notes: String
    var tags: [String]
    var trustZone: String
    var lastOpened: Date?
    var vaultScope: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        descriptionText: String = "",
        environment: String = "dev",
        hostReference: String,
        shell: String = "/bin/zsh",
        repoPath: String = "",
        startupDir: String = "",
        tmuxSessionName: String,
        tmuxLayoutTemplate: String? = nil,
        preferredAgentCommand: String? = nil,
        artifactRoots: [String] = [],
        notes: String = "",
        tags: [String] = [],
        trustZone: String = "trusted_dev"
    ) {
        self.id = "ws_\(UUID().uuidString.prefix(8).lowercased())"
        self.name = name
        self.descriptionText = descriptionText
        self.environment = environment
        self.hostReference = hostReference
        self.shell = shell
        self.repoPath = repoPath
        self.startupDir = startupDir
        self.tmuxSessionName = tmuxSessionName
        self.tmuxLayoutTemplate = tmuxLayoutTemplate
        self.tmuxPanesData = nil
        self.preferredAgentCommand = preferredAgentCommand
        self.savedForwardsData = nil
        self.previewRulesData = nil
        self.artifactRoots = artifactRoots
        self.notes = notes
        self.tags = tags
        self.trustZone = trustZone
        self.lastOpened = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Coded accessors for JSON-encoded fields

    var tmuxPanes: [PaneDefinition] {
        get {
            guard let data = tmuxPanesData else { return [] }
            return (try? JSONDecoder().decode([PaneDefinition].self, from: data)) ?? []
        }
        set {
            tmuxPanesData = try? JSONEncoder().encode(newValue)
        }
    }

    var savedForwards: [ForwardDefinition] {
        get {
            guard let data = savedForwardsData else { return [] }
            return (try? JSONDecoder().decode([ForwardDefinition].self, from: data)) ?? []
        }
        set {
            savedForwardsData = try? JSONEncoder().encode(newValue)
        }
    }

    var previewRules: PreviewRulesConfig {
        get {
            guard let data = previewRulesData else {
                return PreviewRulesConfig(autoDetect: true, openInApp: true)
            }
            return (try? JSONDecoder().decode(PreviewRulesConfig.self, from: data))
                ?? PreviewRulesConfig(autoDetect: true, openInApp: true)
        }
        set {
            previewRulesData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Supporting Types

nonisolated struct PaneDefinition: Codable, Hashable, Sendable {
    var role: PaneRole
    var window: String
}

nonisolated enum PaneRole: String, Codable, CaseIterable, Hashable, Sendable {
    case shell
    case agent
    case tests
    case server
    case logs
    case db
    case scratch
}

nonisolated struct ForwardDefinition: Codable, Hashable, Sendable {
    var name: String
    var remoteHost: String
    var remotePort: Int
    var localPort: Int?
    var autoPreview: Bool

    init(name: String, remoteHost: String = "127.0.0.1", remotePort: Int, localPort: Int? = nil, autoPreview: Bool = false) {
        self.name = name
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.localPort = localPort
        self.autoPreview = autoPreview
    }
}

nonisolated struct PreviewRulesConfig: Codable, Hashable, Sendable {
    var autoDetect: Bool
    var openInApp: Bool
}
