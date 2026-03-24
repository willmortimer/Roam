import Foundation
import SwiftData

/// Exports app data (hosts, workspaces, snippets) as an encrypted blob.
nonisolated final class ExportService: @unchecked Sendable {
    private let blobService = EncryptedBlobService()
    private let encoder = JSONEncoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// Export all app data as an encrypted blob.
    func exportAll(
        password: String,
        includeKeys: Bool,
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord]
    ) throws -> Data {
        let manifest = try manifest(
            hosts: hosts,
            workspaces: workspaces,
            snippets: snippets,
            includeKeys: includeKeys
        )
        let manifestData = try encoder.encode(manifest)
        return try blobService.encrypt(data: manifestData, password: password)
    }

    /// Export a single workspace with its associated host.
    func exportWorkspace(
        _ workspace: WorkspaceRecord,
        host: HostRecord?,
        password: String
    ) throws -> Data {
        let hosts = host.map { [$0] } ?? []
        let manifest = try manifest(
            hosts: hosts,
            workspaces: [workspace],
            snippets: [],
            includeKeys: false
        )
        let manifestData = try encoder.encode(manifest)
        return try blobService.encrypt(data: manifestData, password: password)
    }

    // MARK: - Manifest

    func manifest(
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord],
        includeKeys: Bool
    ) throws -> ExportManifest {
        let exportedHosts = hosts.map { host in
            ExportedHost(
                id: host.id,
                alias: host.alias,
                hostname: host.hostname,
                port: host.port,
                username: host.username,
                authMethod: host.authMethod.rawValue,
                keyReference: host.keyReference,
                jumpChain: host.jumpChain,
                tags: host.tags,
                folder: host.folder,
                notes: host.notes,
                environment: host.environment,
                trustClass: host.trustClass.rawValue
            )
        }

        let exportedWorkspaces = workspaces.map { ws in
            ExportedWorkspace(
                id: ws.id,
                name: ws.name,
                descriptionText: ws.descriptionText,
                environment: ws.environment,
                hostReference: ws.hostReference,
                shell: ws.shell,
                repoPath: ws.repoPath,
                startupDir: ws.startupDir,
                tmuxSessionName: ws.tmuxSessionName,
                tmuxLayoutTemplate: ws.tmuxLayoutTemplate,
                tmuxPanes: ws.tmuxPanes,
                preferredAgentCommand: ws.preferredAgentCommand,
                savedForwards: ws.savedForwards,
                previewRules: ws.previewRules,
                artifactRoots: ws.artifactRoots,
                notes: ws.notes,
                tags: ws.tags,
                trustZone: ws.trustZone
            )
        }

        let exportedSnippets = snippets.map { snip in
            ExportedSnippet(
                id: snip.id,
                name: snip.name,
                scope: snip.scope,
                targetPaneRole: snip.targetPaneRole?.rawValue,
                variables: snip.variables,
                steps: snip.steps,
                tags: snip.tags
            )
        }

        var keys: [ExportedKey] = []
        if includeKeys {
            for host in hosts {
                guard let keyRef = host.keyReference else { continue }
                if let keyData = try? VaultService.shared.loadPrivateKey(id: keyRef) {
                    keys.append(ExportedKey(
                        id: keyRef,
                        data: keyData.base64EncodedString()
                    ))
                }
            }
        }

        return ExportManifest(
            version: 1,
            exported_at: ISO8601DateFormatter().string(from: .now),
            hosts: exportedHosts,
            workspaces: exportedWorkspaces,
            snippets: exportedSnippets,
            keys: keys.isEmpty ? nil : keys
        )
    }
}

// MARK: - Export Manifest Types

nonisolated struct ExportManifest: Codable, Equatable, Sendable {
    var version: Int
    var exported_at: String
    var hosts: [ExportedHost]
    var workspaces: [ExportedWorkspace]
    var snippets: [ExportedSnippet]
    var keys: [ExportedKey]?
}

nonisolated struct ExportedHost: Codable, Hashable, Sendable {
    var id: String
    var alias: String
    var hostname: String
    var port: Int
    var username: String
    var authMethod: String
    var keyReference: String?
    var jumpChain: [String]
    var tags: [String]
    var folder: String?
    var notes: String
    var environment: String
    var trustClass: String
}

nonisolated struct ExportedWorkspace: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var descriptionText: String
    var environment: String
    var hostReference: String
    var shell: String
    var repoPath: String
    var startupDir: String
    var tmuxSessionName: String
    var tmuxLayoutTemplate: String?
    var tmuxPanes: [PaneDefinition]
    var preferredAgentCommand: String?
    var savedForwards: [ForwardDefinition]
    var previewRules: PreviewRulesConfig
    var artifactRoots: [String]
    var notes: String
    var tags: [String]
    var trustZone: String
}

nonisolated struct ExportedSnippet: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var scope: SnippetScope
    var targetPaneRole: String?
    var variables: [SnippetVariable]
    var steps: [SnippetStep]
    var tags: [String]
}

nonisolated struct ExportedKey: Codable, Hashable, Sendable {
    var id: String
    var data: String // base64-encoded
}
