import Foundation
import SwiftData

/// ViewModel for per-workspace command history timeline.
@Observable
final class CommandTimelineViewModel {
    private(set) var commands: [CommandRecord] = []
    var searchText = ""
    var filterRole: PaneRole?

    private var modelContext: ModelContext?
    private var workspaceReference: String?

    func configure(modelContext: ModelContext, workspaceReference: String) {
        self.modelContext = modelContext
        self.workspaceReference = workspaceReference
        refresh()
    }

    func refresh() {
        guard let modelContext, let workspaceReference else { return }

        let descriptor = FetchDescriptor<CommandRecord>(
            predicate: #Predicate { record in
                record.workspaceReference == workspaceReference
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            var results = try modelContext.fetch(descriptor)

            // Apply filters
            if let filterRole {
                results = results.filter { $0.paneRole == filterRole }
            }
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                results = results.filter { $0.command.lowercased().contains(query) }
            }

            commands = results
        } catch {
            commands = []
        }
    }

    /// Record a new command.
    func recordCommand(
        command: String,
        paneRole: PaneRole? = nil,
        paneID: String? = nil,
        source: CommandSource = .terminal
    ) {
        guard let modelContext, let workspaceReference else { return }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let record = CommandRecord(
            workspaceReference: workspaceReference,
            command: trimmed,
            paneRole: paneRole,
            paneID: paneID,
            source: source
        )
        modelContext.insert(record)
        try? modelContext.save()
        refresh()
    }

    /// Delete a command record.
    func deleteCommand(_ command: CommandRecord) {
        modelContext?.delete(command)
        try? modelContext?.save()
        refresh()
    }
}
