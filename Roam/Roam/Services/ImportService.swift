import Foundation
import SwiftData

nonisolated enum ImportConflictStrategy: Sendable {
    case duplicate
    case replaceExisting
    case skipExisting
}

/// Decrypts and imports app data from an encrypted blob.
nonisolated final class ImportService: @unchecked Sendable {
    private let blobService = EncryptedBlobService()
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Decrypt blob and return a preview of what will be imported.
    func preview(blob: Data, password: String) throws -> ImportPreview {
        let manifestData = try blobService.decrypt(blob: blob, password: password)
        let manifest = try decoder.decode(ExportManifest.self, from: manifestData)
        return ImportPreview(
            manifest: manifest,
            hostCount: manifest.hosts.count,
            workspaceCount: manifest.workspaces.count,
            snippetCount: manifest.snippets.count,
            keyCount: manifest.keys?.count ?? 0,
            exportedAt: manifest.exported_at
        )
    }

    /// Apply the import: create records in SwiftData and store keys in Keychain.
    func apply(
        _ preview: ImportPreview,
        existingHostIDs: Set<String>,
        existingWorkspaceIDs: Set<String>,
        existingSnippetIDs: Set<String>,
        modelContext: ModelContext,
        vault: VaultService,
        conflictStrategy: ImportConflictStrategy = .duplicate
    ) throws -> ImportResult {
        var hostsCreated = 0
        var hostsUpdated = 0
        var hostsSkipped = 0
        var workspacesCreated = 0
        var workspacesUpdated = 0
        var workspacesSkipped = 0
        var snippetsCreated = 0
        var snippetsUpdated = 0
        var snippetsSkipped = 0
        var keysImported = 0

        let existingHosts = try Dictionary(
            uniqueKeysWithValues: modelContext.fetch(FetchDescriptor<HostRecord>()).map { ($0.id, $0) }
        )
        let existingWorkspaces = try Dictionary(
            uniqueKeysWithValues: modelContext.fetch(FetchDescriptor<WorkspaceRecord>()).map { ($0.id, $0) }
        )
        let existingSnippets = try Dictionary(
            uniqueKeysWithValues: modelContext.fetch(FetchDescriptor<SnippetRecord>()).map { ($0.id, $0) }
        )

        // Import hosts
        for exported in preview.manifest.hosts {
            if let existing = existingHosts[exported.id] {
                switch conflictStrategy {
                case .duplicate:
                    let host = HostRecord(
                        alias: exported.alias,
                        hostname: exported.hostname,
                        port: exported.port,
                        username: exported.username,
                        authMethod: AuthMethod(rawValue: exported.authMethod) ?? .key,
                        keyReference: exported.keyReference,
                        jumpChain: exported.jumpChain,
                        tags: exported.tags,
                        folder: exported.folder,
                        notes: exported.notes,
                        environment: exported.environment,
                        trustClass: TrustClass(rawValue: exported.trustClass) ?? .trustedDev
                    )
                    modelContext.insert(host)
                    hostsCreated += 1
                case .replaceExisting:
                    apply(exported, to: existing)
                    hostsUpdated += 1
                case .skipExisting:
                    hostsSkipped += 1
                }
                continue
            }

            let host = HostRecord(
                alias: exported.alias,
                hostname: exported.hostname,
                port: exported.port,
                username: exported.username,
                authMethod: AuthMethod(rawValue: exported.authMethod) ?? .key,
                keyReference: exported.keyReference,
                jumpChain: exported.jumpChain,
                tags: exported.tags,
                folder: exported.folder,
                notes: exported.notes,
                environment: exported.environment,
                trustClass: TrustClass(rawValue: exported.trustClass) ?? .trustedDev
            )
            if !existingHostIDs.contains(exported.id) {
                host.id = exported.id
            }
            modelContext.insert(host)
            hostsCreated += 1
        }

        // Import workspaces
        for exported in preview.manifest.workspaces {
            if let existing = existingWorkspaces[exported.id] {
                switch conflictStrategy {
                case .duplicate:
                    let ws = WorkspaceRecord(
                        name: exported.name,
                        descriptionText: exported.descriptionText,
                        environment: exported.environment,
                        hostReference: exported.hostReference,
                        shell: exported.shell,
                        repoPath: exported.repoPath,
                        startupDir: exported.startupDir,
                        tmuxSessionName: exported.tmuxSessionName,
                        tmuxLayoutTemplate: exported.tmuxLayoutTemplate,
                        preferredAgentCommand: exported.preferredAgentCommand,
                        artifactRoots: exported.artifactRoots,
                        notes: exported.notes,
                        tags: exported.tags,
                        trustZone: exported.trustZone
                    )
                    ws.tmuxPanes = exported.tmuxPanes
                    ws.savedForwards = exported.savedForwards
                    ws.previewRules = exported.previewRules
                    modelContext.insert(ws)
                    workspacesCreated += 1
                case .replaceExisting:
                    apply(exported, to: existing)
                    workspacesUpdated += 1
                case .skipExisting:
                    workspacesSkipped += 1
                }
                continue
            }

            let ws = WorkspaceRecord(
                name: exported.name,
                descriptionText: exported.descriptionText,
                environment: exported.environment,
                hostReference: exported.hostReference,
                shell: exported.shell,
                repoPath: exported.repoPath,
                startupDir: exported.startupDir,
                tmuxSessionName: exported.tmuxSessionName,
                tmuxLayoutTemplate: exported.tmuxLayoutTemplate,
                preferredAgentCommand: exported.preferredAgentCommand,
                artifactRoots: exported.artifactRoots,
                notes: exported.notes,
                tags: exported.tags,
                trustZone: exported.trustZone
            )

            if !existingWorkspaceIDs.contains(exported.id) {
                ws.id = exported.id
            }
            ws.tmuxPanes = exported.tmuxPanes
            ws.savedForwards = exported.savedForwards
            ws.previewRules = exported.previewRules

            modelContext.insert(ws)
            workspacesCreated += 1
        }

        // Import snippets
        for exported in preview.manifest.snippets {
            if let existing = existingSnippets[exported.id] {
                switch conflictStrategy {
                case .duplicate:
                    let snip = SnippetRecord(
                        name: exported.name,
                        scope: exported.scope,
                        targetPaneRole: exported.targetPaneRole.flatMap { PaneRole(rawValue: $0) },
                        variables: exported.variables,
                        steps: exported.steps,
                        tags: exported.tags
                    )
                    modelContext.insert(snip)
                    snippetsCreated += 1
                case .replaceExisting:
                    apply(exported, to: existing)
                    snippetsUpdated += 1
                case .skipExisting:
                    snippetsSkipped += 1
                }
                continue
            }

            let snip = SnippetRecord(
                name: exported.name,
                scope: exported.scope,
                targetPaneRole: exported.targetPaneRole.flatMap { PaneRole(rawValue: $0) },
                variables: exported.variables,
                steps: exported.steps,
                tags: exported.tags
            )
            if !existingSnippetIDs.contains(exported.id) {
                snip.id = exported.id
            }
            modelContext.insert(snip)
            snippetsCreated += 1
        }

        // Import keys
        if let keys = preview.manifest.keys {
            for key in keys {
                if let data = Data(base64Encoded: key.data) {
                    let requireBio = UserDefaults.standard.object(forKey: "biometric_requireForKeys") as? Bool ?? true
                    try vault.storePrivateKey(id: key.id, data: data, requireBiometrics: requireBio)
                    keysImported += 1
                }
            }
        }

        try modelContext.save()

        return ImportResult(
            hostsCreated: hostsCreated,
            hostsUpdated: hostsUpdated,
            hostsSkipped: hostsSkipped,
            workspacesCreated: workspacesCreated,
            workspacesUpdated: workspacesUpdated,
            workspacesSkipped: workspacesSkipped,
            snippetsCreated: snippetsCreated,
            snippetsUpdated: snippetsUpdated,
            snippetsSkipped: snippetsSkipped,
            keysImported: keysImported
        )
    }

    private func apply(_ exported: ExportedHost, to host: HostRecord) {
        host.alias = exported.alias
        host.hostname = exported.hostname
        host.port = exported.port
        host.username = exported.username
        host.authMethod = AuthMethod(rawValue: exported.authMethod) ?? .key
        host.keyReference = exported.keyReference
        host.jumpChain = exported.jumpChain
        host.tags = exported.tags
        host.folder = exported.folder
        host.notes = exported.notes
        host.environment = exported.environment
        host.trustClass = TrustClass(rawValue: exported.trustClass) ?? .trustedDev
    }

    private func apply(_ exported: ExportedWorkspace, to workspace: WorkspaceRecord) {
        workspace.name = exported.name
        workspace.descriptionText = exported.descriptionText
        workspace.environment = exported.environment
        workspace.hostReference = exported.hostReference
        workspace.shell = exported.shell
        workspace.repoPath = exported.repoPath
        workspace.startupDir = exported.startupDir
        workspace.tmuxSessionName = exported.tmuxSessionName
        workspace.tmuxLayoutTemplate = exported.tmuxLayoutTemplate
        workspace.preferredAgentCommand = exported.preferredAgentCommand
        workspace.artifactRoots = exported.artifactRoots
        workspace.notes = exported.notes
        workspace.tags = exported.tags
        workspace.trustZone = exported.trustZone
        workspace.tmuxPanes = exported.tmuxPanes
        workspace.savedForwards = exported.savedForwards
        workspace.previewRules = exported.previewRules
    }

    private func apply(_ exported: ExportedSnippet, to snippet: SnippetRecord) {
        snippet.name = exported.name
        snippet.scope = exported.scope
        snippet.targetPaneRole = exported.targetPaneRole.flatMap { PaneRole(rawValue: $0) }
        snippet.variables = exported.variables
        snippet.steps = exported.steps
        snippet.tags = exported.tags
    }
}

// MARK: - Import Types

struct ImportPreview: Equatable {
    var manifest: ExportManifest
    var hostCount: Int
    var workspaceCount: Int
    var snippetCount: Int
    var keyCount: Int
    var exportedAt: String
}

struct ImportResult {
    var hostsCreated: Int
    var hostsUpdated: Int
    var hostsSkipped: Int
    var workspacesCreated: Int
    var workspacesUpdated: Int
    var workspacesSkipped: Int
    var snippetsCreated: Int
    var snippetsUpdated: Int
    var snippetsSkipped: Int
    var keysImported: Int

    var summary: String {
        var parts: [String] = []
        if hostsCreated > 0 { parts.append("\(hostsCreated) hosts") }
        if hostsUpdated > 0 { parts.append("\(hostsUpdated) hosts updated") }
        if hostsSkipped > 0 { parts.append("\(hostsSkipped) hosts skipped") }
        if workspacesCreated > 0 { parts.append("\(workspacesCreated) workspaces") }
        if workspacesUpdated > 0 { parts.append("\(workspacesUpdated) workspaces updated") }
        if workspacesSkipped > 0 { parts.append("\(workspacesSkipped) workspaces skipped") }
        if snippetsCreated > 0 { parts.append("\(snippetsCreated) snippets") }
        if snippetsUpdated > 0 { parts.append("\(snippetsUpdated) snippets updated") }
        if snippetsSkipped > 0 { parts.append("\(snippetsSkipped) snippets skipped") }
        if keysImported > 0 { parts.append("\(keysImported) keys") }
        return parts.isEmpty ? "Nothing imported" : "Imported: \(parts.joined(separator: ", "))"
    }
}
