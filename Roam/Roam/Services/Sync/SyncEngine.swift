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
    var pendingConflict: SyncConflictState?

    private let syncKey = "roam-sync-latest"
    private var pendingRemoteBlob: Data?

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case complete
        case error(String)
    }

    /// Full sync cycle: pull remote changes, reconcile if safe, then push the merged state.
    func sync(
        password: String,
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord],
        modelContext: ModelContext,
        vault: VaultService
    ) async {
        guard let provider else {
            setError("No sync provider configured")
            return
        }

        beginSyncRun()

        do {
            let exportService = ExportService()
            let localManifest = try exportService.manifest(
                hosts: hosts,
                workspaces: workspaces,
                snippets: snippets,
                includeKeys: false
            )

            if let remoteState = try await loadRemoteState(password: password, provider: provider) {
                let remoteChanges = buildConflictState(
                    localManifest: localManifest,
                    remotePreview: remoteState.preview
                )

                if let remoteChanges, remoteChanges.hasConflicts {
                    pendingConflict = remoteChanges
                    pendingRemoteBlob = remoteState.blob
                    setError(remoteChanges.statusMessage)
                    return
                }

                if let remoteChanges, remoteChanges.hasRemoteOnlyChanges {
                    try importRemoteState(
                        remoteState.preview,
                        existingHostIDs: Set(hosts.map(\.id)),
                        existingWorkspaceIDs: Set(workspaces.map(\.id)),
                        existingSnippetIDs: Set(snippets.map(\.id)),
                        modelContext: modelContext,
                        vault: vault
                    )

                    let mergedRecords = try fetchAllRecords(modelContext: modelContext)
                    try await pushSnapshot(
                        password: password,
                        hosts: mergedRecords.hosts,
                        workspaces: mergedRecords.workspaces,
                        snippets: mergedRecords.snippets,
                        provider: provider
                    )
                } else {
                    try await pushSnapshot(
                        password: password,
                        hosts: hosts,
                        workspaces: workspaces,
                        snippets: snippets,
                        provider: provider
                    )
                }
            } else {
                try await pushSnapshot(
                    password: password,
                    hosts: hosts,
                    workspaces: workspaces,
                    snippets: snippets,
                    provider: provider
                )
            }

            clearPendingConflict()
            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            finishSyncRun(with: error)
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
            setError("No sync provider configured")
            return
        }

        beginSyncRun()

        do {
            try await pushSnapshot(
                password: password,
                hosts: hosts,
                workspaces: workspaces,
                snippets: snippets,
                provider: provider
            )

            clearPendingConflict()
            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            finishSyncRun(with: error)
        }
    }

    /// Pull remote state and import it. If overlapping records differ, pause for a resolution choice.
    func pull(
        password: String,
        existingHostIDs: Set<String>,
        existingWorkspaceIDs: Set<String>,
        existingSnippetIDs: Set<String>,
        modelContext: ModelContext,
        vault: VaultService
    ) async {
        guard let provider else {
            setError("No sync provider configured")
            return
        }

        beginSyncRun()

        do {
            guard let remoteState = try await loadRemoteState(password: password, provider: provider) else {
                throw SyncError.notFound(syncKey)
            }

            let currentRecords = try fetchAllRecords(modelContext: modelContext)
            let localManifest = try ExportService().manifest(
                hosts: currentRecords.hosts,
                workspaces: currentRecords.workspaces,
                snippets: currentRecords.snippets,
                includeKeys: false
            )

            if let conflict = buildConflictState(localManifest: localManifest, remotePreview: remoteState.preview),
               conflict.hasConflicts {
                pendingConflict = conflict
                pendingRemoteBlob = remoteState.blob
                setError(conflict.statusMessage)
                return
            }

            try importRemoteState(
                remoteState.preview,
                existingHostIDs: existingHostIDs,
                existingWorkspaceIDs: existingWorkspaceIDs,
                existingSnippetIDs: existingSnippetIDs,
                modelContext: modelContext,
                vault: vault
            )

            clearPendingConflict()
            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            finishSyncRun(with: error)
        }
    }

    /// Resolve the current pending conflict by applying the remote version locally,
    /// then pushing the merged state back to the provider.
    func useRemoteChanges(
        password: String,
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord],
        modelContext: ModelContext,
        vault: VaultService
    ) async {
        guard let provider else {
            setError("No sync provider configured")
            return
        }

        guard let pendingConflict else {
            setError("No pending sync conflict to resolve")
            return
        }

        beginSyncRun(resetConflict: false)

        do {
            let preview: ImportPreview
            if let pendingRemoteBlob {
                preview = try ImportService().preview(blob: pendingRemoteBlob, password: password)
            } else {
                guard let remoteState = try await loadRemoteState(password: password, provider: provider) else {
                    throw SyncError.notFound(syncKey)
                }
                preview = remoteState.preview
            }

            try importRemoteState(
                preview,
                existingHostIDs: Set(hosts.map(\.id)),
                existingWorkspaceIDs: Set(workspaces.map(\.id)),
                existingSnippetIDs: Set(snippets.map(\.id)),
                modelContext: modelContext,
                vault: vault
            )

            let mergedRecords = try fetchAllRecords(modelContext: modelContext)
            try await pushSnapshot(
                password: password,
                hosts: mergedRecords.hosts,
                workspaces: mergedRecords.workspaces,
                snippets: mergedRecords.snippets,
                provider: provider
            )

            clearPendingConflict()
            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            self.pendingConflict = pendingConflict
            finishSyncRun(with: error, preserveConflict: true)
        }
    }

    /// Resolve the current pending conflict by treating the local snapshot as authoritative.
    func keepLocalChanges(
        password: String,
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord]
    ) async {
        guard let provider else {
            setError("No sync provider configured")
            return
        }

        guard pendingConflict != nil else {
            setError("No pending sync conflict to resolve")
            return
        }

        beginSyncRun(resetConflict: false)

        do {
            try await pushSnapshot(
                password: password,
                hosts: hosts,
                workspaces: workspaces,
                snippets: snippets,
                provider: provider
            )

            clearPendingConflict()
            lastSyncDate = .now
            syncStatus = .complete
        } catch {
            finishSyncRun(with: error, preserveConflict: true)
        }
    }

    func clearPendingConflict() {
        pendingConflict = nil
        pendingRemoteBlob = nil
    }

    private func beginSyncRun(resetConflict: Bool = true) {
        syncStatus = .syncing
        errorMessage = nil
        if resetConflict {
            clearPendingConflict()
        }
    }

    private func finishSyncRun(with error: Error, preserveConflict: Bool = false) {
        if !preserveConflict {
            pendingRemoteBlob = nil
        }
        setError(error.localizedDescription)
    }

    private func setError(_ message: String) {
        syncStatus = .error(message)
        errorMessage = message
    }

    private func loadRemoteState(
        password: String,
        provider: any SyncProvider
    ) async throws -> (blob: Data, preview: ImportPreview)? {
        do {
            let blob = try await provider.download(key: syncKey)
            let preview = try ImportService().preview(blob: blob, password: password)
            return (blob, preview)
        } catch SyncError.notFound {
            return nil
        }
    }

    private func importRemoteState(
        _ preview: ImportPreview,
        existingHostIDs: Set<String>,
        existingWorkspaceIDs: Set<String>,
        existingSnippetIDs: Set<String>,
        modelContext: ModelContext,
        vault: VaultService
    ) throws {
        _ = try ImportService().apply(
            preview,
            existingHostIDs: existingHostIDs,
            existingWorkspaceIDs: existingWorkspaceIDs,
            existingSnippetIDs: existingSnippetIDs,
            modelContext: modelContext,
            vault: vault,
            conflictStrategy: .replaceExisting
        )
    }

    private func fetchAllRecords(
        modelContext: ModelContext
    ) throws -> (hosts: [HostRecord], workspaces: [WorkspaceRecord], snippets: [SnippetRecord]) {
        (
            try modelContext.fetch(FetchDescriptor<HostRecord>()),
            try modelContext.fetch(FetchDescriptor<WorkspaceRecord>()),
            try modelContext.fetch(FetchDescriptor<SnippetRecord>())
        )
    }

    private func pushSnapshot(
        password: String,
        hosts: [HostRecord],
        workspaces: [WorkspaceRecord],
        snippets: [SnippetRecord],
        provider: any SyncProvider
    ) async throws {
        let exportService = ExportService()
        let blob = try exportService.exportAll(
            password: password,
            includeKeys: false,
            hosts: hosts,
            workspaces: workspaces,
            snippets: snippets
        )
        try await provider.upload(blob: blob, key: syncKey)
    }

    private func buildConflictState(
        localManifest: ExportManifest,
        remotePreview: ImportPreview
    ) -> SyncConflictState? {
        let remoteManifest = remotePreview.manifest

        let localHosts = Dictionary(uniqueKeysWithValues: localManifest.hosts.map { ($0.id, $0) })
        let localWorkspaces = Dictionary(uniqueKeysWithValues: localManifest.workspaces.map { ($0.id, $0) })
        let localSnippets = Dictionary(uniqueKeysWithValues: localManifest.snippets.map { ($0.id, $0) })

        var remoteOnlyHosts = 0
        var remoteOnlyWorkspaces = 0
        var remoteOnlySnippets = 0
        var conflicts: [SyncConflictItem] = []

        for remoteHost in remoteManifest.hosts {
            guard let localHost = localHosts[remoteHost.id] else {
                remoteOnlyHosts += 1
                continue
            }

            if localHost != remoteHost {
                conflicts.append(
                    SyncConflictItem(
                        entity: .host,
                        id: remoteHost.id,
                        title: remoteHost.alias
                    )
                )
            }
        }

        for remoteWorkspace in remoteManifest.workspaces {
            guard let localWorkspace = localWorkspaces[remoteWorkspace.id] else {
                remoteOnlyWorkspaces += 1
                continue
            }

            if localWorkspace != remoteWorkspace {
                conflicts.append(
                    SyncConflictItem(
                        entity: .workspace,
                        id: remoteWorkspace.id,
                        title: remoteWorkspace.name
                    )
                )
            }
        }

        for remoteSnippet in remoteManifest.snippets {
            guard let localSnippet = localSnippets[remoteSnippet.id] else {
                remoteOnlySnippets += 1
                continue
            }

            if localSnippet != remoteSnippet {
                conflicts.append(
                    SyncConflictItem(
                        entity: .snippet,
                        id: remoteSnippet.id,
                        title: remoteSnippet.name
                    )
                )
            }
        }

        guard remoteOnlyHosts > 0 || remoteOnlyWorkspaces > 0 || remoteOnlySnippets > 0 || !conflicts.isEmpty else {
            return nil
        }

        conflicts.sort { lhs, rhs in
            if lhs.entity.sortOrder != rhs.entity.sortOrder {
                return lhs.entity.sortOrder < rhs.entity.sortOrder
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return SyncConflictState(
            preview: remotePreview,
            remoteOnlyHosts: remoteOnlyHosts,
            remoteOnlyWorkspaces: remoteOnlyWorkspaces,
            remoteOnlySnippets: remoteOnlySnippets,
            conflicts: conflicts
        )
    }
}

struct SyncConflictState: Equatable {
    var preview: ImportPreview
    var remoteOnlyHosts: Int
    var remoteOnlyWorkspaces: Int
    var remoteOnlySnippets: Int
    var conflicts: [SyncConflictItem]

    var totalRemoteOnlyCount: Int {
        remoteOnlyHosts + remoteOnlyWorkspaces + remoteOnlySnippets
    }

    var hasConflicts: Bool {
        !conflicts.isEmpty
    }

    var hasRemoteOnlyChanges: Bool {
        totalRemoteOnlyCount > 0
    }

    var statusMessage: String {
        var parts: [String] = []
        if hasConflicts {
            parts.append("\(conflicts.count) conflicts")
        }
        if hasRemoteOnlyChanges {
            parts.append("\(totalRemoteOnlyCount) remote additions")
        }

        if parts.isEmpty {
            return "Remote changes need review"
        }

        return "Remote changes need review: \(parts.joined(separator: ", "))"
    }
}

struct SyncConflictItem: Identifiable, Equatable {
    var entity: SyncConflictEntity
    var id: String
    var title: String

    var displayTitle: String {
        "\(entity.label): \(title)"
    }
}

enum SyncConflictEntity: Equatable {
    case host
    case workspace
    case snippet

    var label: String {
        switch self {
        case .host: "Host"
        case .workspace: "Workspace"
        case .snippet: "Snippet"
        }
    }

    var sortOrder: Int {
        switch self {
        case .host: 0
        case .workspace: 1
        case .snippet: 2
        }
    }
}
