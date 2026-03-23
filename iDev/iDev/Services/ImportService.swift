import Foundation
import SwiftData

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
        vault: VaultService
    ) throws -> ImportResult {
        var hostsCreated = 0
        var workspacesCreated = 0
        var snippetsCreated = 0
        var keysImported = 0

        // Import hosts
        for exported in preview.manifest.hosts {
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
            // Override the auto-generated ID if not conflicting
            if !existingHostIDs.contains(exported.id) {
                host.id = exported.id
            }
            modelContext.insert(host)
            hostsCreated += 1
        }

        // Import workspaces
        for exported in preview.manifest.workspaces {
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
            workspacesCreated: workspacesCreated,
            snippetsCreated: snippetsCreated,
            keysImported: keysImported
        )
    }
}

// MARK: - Import Types

struct ImportPreview {
    var manifest: ExportManifest
    var hostCount: Int
    var workspaceCount: Int
    var snippetCount: Int
    var keyCount: Int
    var exportedAt: String
}

struct ImportResult {
    var hostsCreated: Int
    var workspacesCreated: Int
    var snippetsCreated: Int
    var keysImported: Int

    var summary: String {
        var parts: [String] = []
        if hostsCreated > 0 { parts.append("\(hostsCreated) hosts") }
        if workspacesCreated > 0 { parts.append("\(workspacesCreated) workspaces") }
        if snippetsCreated > 0 { parts.append("\(snippetsCreated) snippets") }
        if keysImported > 0 { parts.append("\(keysImported) keys") }
        return parts.isEmpty ? "Nothing imported" : "Imported: \(parts.joined(separator: ", "))"
    }
}
