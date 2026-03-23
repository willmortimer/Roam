import Foundation
import SwiftData

/// Manages team vault sync operations.
///
/// Reuses `ExportService` and `ImportService` internally, scoped to items
/// whose `vaultScope` matches the vault's ID.
@Observable
final class TeamVaultService {

    var syncStatus: SyncStatus = .idle
    var errorMessage: String?

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case complete
        case error(String)
    }

    private let syncKeyPrefix = "idev-team-vault-"

    private func syncKey(for vault: TeamVaultRecord) -> String {
        "\(syncKeyPrefix)\(vault.id)"
    }

    /// Push hosts/snippets/workspaces that belong to this vault.
    func pushToVault(
        _ vault: TeamVaultRecord,
        passphrase: String,
        hosts: [HostRecord],
        snippets: [SnippetRecord],
        workspaces: [WorkspaceRecord],
        provider: any SyncProvider
    ) async {
        syncStatus = .syncing
        errorMessage = nil

        do {
            // Filter to items belonging to this vault
            let vaultHosts = hosts.filter { $0.vaultScope == vault.id }
            let vaultSnippets = snippets.filter { $0.vaultScope == vault.id }
            let vaultWorkspaces = workspaces.filter { $0.vaultScope == vault.id }

            let exportService = ExportService()
            let blob = try exportService.exportAll(
                password: passphrase,
                includeKeys: false,
                hosts: vaultHosts,
                workspaces: vaultWorkspaces,
                snippets: vaultSnippets
            )

            try await provider.upload(blob: blob, key: syncKey(for: vault))

            vault.lastSyncDate = .now
            syncStatus = .complete
        } catch {
            let msg = error.localizedDescription
            syncStatus = .error(msg)
            errorMessage = msg
        }
    }

    /// Pull remote vault state and import items, tagging them with the vault scope.
    func pullFromVault(
        _ vault: TeamVaultRecord,
        passphrase: String,
        existingHostIDs: Set<String>,
        existingWorkspaceIDs: Set<String>,
        existingSnippetIDs: Set<String>,
        modelContext: ModelContext,
        vaultService: VaultService,
        provider: any SyncProvider
    ) async {
        syncStatus = .syncing
        errorMessage = nil

        do {
            let blob = try await provider.download(key: syncKey(for: vault))
            let importService = ImportService()
            let preview = try importService.preview(blob: blob, password: passphrase)

            _ = try importService.apply(
                preview,
                existingHostIDs: existingHostIDs,
                existingWorkspaceIDs: existingWorkspaceIDs,
                existingSnippetIDs: existingSnippetIDs,
                modelContext: modelContext,
                vault: vaultService
            )

            // Tag newly imported items with this vault's scope.
            // Items that were just imported won't have a vaultScope yet.
            let allHosts = try modelContext.fetch(FetchDescriptor<HostRecord>())
            for host in allHosts where !existingHostIDs.contains(host.id) {
                host.vaultScope = vault.id
            }

            let allWorkspaces = try modelContext.fetch(FetchDescriptor<WorkspaceRecord>())
            for ws in allWorkspaces where !existingWorkspaceIDs.contains(ws.id) {
                ws.vaultScope = vault.id
            }

            let allSnippets = try modelContext.fetch(FetchDescriptor<SnippetRecord>())
            for snippet in allSnippets where !existingSnippetIDs.contains(snippet.id) {
                snippet.vaultScope = vault.id
            }

            vault.lastSyncDate = .now
            syncStatus = .complete
        } catch {
            let msg = error.localizedDescription
            syncStatus = .error(msg)
            errorMessage = msg
        }
    }
}
