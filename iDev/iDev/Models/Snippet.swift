import Foundation
import SwiftData

@Model
final class SnippetRecord {
    @Attribute(.unique) var id: String
    var name: String
    var scopeData: Data?
    var targetPaneRole: PaneRole?
    var variablesData: Data?
    var stepsData: Data?
    var tags: [String]
    var vaultScope: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        name: String,
        scope: SnippetScope = .global,
        targetPaneRole: PaneRole? = nil,
        variables: [SnippetVariable] = [],
        steps: [SnippetStep] = [],
        tags: [String] = []
    ) {
        self.id = "snip_\(UUID().uuidString.prefix(8).lowercased())"
        self.name = name
        self.scopeData = try? JSONEncoder().encode(scope)
        self.targetPaneRole = targetPaneRole
        self.variablesData = try? JSONEncoder().encode(variables)
        self.stepsData = try? JSONEncoder().encode(steps)
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Coded accessors

    var scope: SnippetScope {
        get {
            guard let data = scopeData else { return .global }
            return (try? JSONDecoder().decode(SnippetScope.self, from: data)) ?? .global
        }
        set {
            scopeData = try? JSONEncoder().encode(newValue)
        }
    }

    var variables: [SnippetVariable] {
        get {
            guard let data = variablesData else { return [] }
            return (try? JSONDecoder().decode([SnippetVariable].self, from: data)) ?? []
        }
        set {
            variablesData = try? JSONEncoder().encode(newValue)
        }
    }

    var steps: [SnippetStep] {
        get {
            guard let data = stepsData else { return [] }
            return (try? JSONDecoder().decode([SnippetStep].self, from: data)) ?? []
        }
        set {
            stepsData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Supporting Types

nonisolated enum SnippetScope: Codable, Hashable, Sendable {
    case global
    case host(String)
    case workspace(String)
}

nonisolated struct SnippetVariable: Codable, Hashable, Sendable {
    var name: String
    var type: String
    var defaultValue: String?
    var prompt: String?

    init(name: String, type: String = "string", defaultValue: String? = nil, prompt: String? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
        self.prompt = prompt
    }
}

nonisolated struct SnippetStep: Codable, Hashable, Sendable {
    var command: String
}
