import Foundation
import SwiftData
import Observation

/// Manages BYO sync using encrypted blobs via a pluggable SyncProvider.
///
/// The sync engine exports app data using `ExportService`, encrypts it,
/// uploads it via the configured provider, and imports downloaded blobs
/// using `ImportService`. The provider only ever sees opaque ciphertext.
@Observable
final class SyncEngine {
    var syncStatus: SyncStatus = .idle
    var lastSyncDate: Date?
    var errorMessage: String?
    var provider: (any SyncProvider)?

    private let syncKey = "idev-sync-latest"

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case complete
        case error(String)
    }

    /// Full sync cycle: push local state, then pull remote state.
    func sync(
        password: String,
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord],
        modelContext: ModelContext,
        vault: VaultService
    ) async {
        guard let provider else {
            syncStatus = .error("No sync provider configured")
            return
        }

        syncStatus = .syncing
        errorMessage = nil

        do {
            // Push local state
            let exportService = ExportService()
            let blob = try exportService.exportAll(
                password: password,
                includeKeys: false,
                hosts: hosts,
                workspaces: workspaces,
                snippets: snippets
            )
            try await provider.upload(blob: blob, key: syncKey)

            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            let msg = error.localizedDescription
            syncStatus = .error(msg)
            errorMessage = msg
        }
    }

    /// Push local state to the remote provider.
    func push(
        password: String,
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord]
    ) async {
        guard let provider else {
            syncStatus = .error("No sync provider configured")
            return
        }

        syncStatus = .syncing
        errorMessage = nil

        do {
            let exportService = ExportService()
            let blob = try exportService.exportAll(
                password: password,
                includeKeys: false,
                hosts: hosts,
                workspaces: workspaces,
                snippets: snippets
            )
            try await provider.upload(blob: blob, key: syncKey)

            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            let msg = error.localizedDescription
            syncStatus = .error(msg)
            errorMessage = msg
        }
    }

    /// Pull remote state and import it.
    func pull(
        password: String,
        existingHostIDs: Set<String>,
        existingWorkspaceIDs: Set<String>,
        existingSnippetIDs: Set<String>,
        modelContext: ModelContext,
        vault: VaultService
    ) async {
        guard let provider else {
            syncStatus = .error("No sync provider configured")
            return
        }

        syncStatus = .syncing
        errorMessage = nil

        do {
            let blob = try await provider.download(key: syncKey)
            let importService = ImportService()
            let preview = try importService.preview(blob: blob, password: password)
            _ = try importService.apply(
                preview,
                existingHostIDs: existingHostIDs,
                existingWorkspaceIDs: existingWorkspaceIDs,
                existingSnippetIDs: existingSnippetIDs,
                modelContext: modelContext,
                vault: vault
            )

            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            let msg = error.localizedDescription
            syncStatus = .error(msg)
            errorMessage = msg
        }
    }
}
