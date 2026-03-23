import SwiftUI
import SwiftData

struct SnippetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SnippetRecord.name) private var allSnippets: [SnippetRecord]

    var workspaceID: String?
    var hostID: String?
    var onExecute: (String) -> Void

    @State private var variableValues: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                if filteredSnippets.isEmpty {
                    ContentUnavailableView(
                        "No Snippets",
                        systemImage: "text.badge.star",
                        description: Text("Create snippets in Settings to use them here.")
                    )
                } else {
                    ForEach(filteredSnippets, id: \.id) { snippet in
                        SnippetRow(
                            snippet: snippet,
                            variableValues: $variableValues,
                            onExecute: { command in
                                onExecute(command)
                                dismiss()
                            }
                        )
                    }
                }
            }
            .navigationTitle("Snippets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filteredSnippets: [SnippetRecord] {
        allSnippets.filter { snippet in
            switch snippet.scope {
            case .global:
                true
            case .workspace(let id):
                id == workspaceID
            case .host(let id):
                id == hostID
            }
        }
    }
}

struct SnippetRow: View {
    let snippet: SnippetRecord
    @Binding var variableValues: [String: String]
    var onExecute: (String) -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(snippet.variables, id: \.name) { variable in
                TextField(
                    variable.prompt ?? variable.name,
                    text: Binding(
                        get: { variableValues[variable.name] ?? variable.defaultValue ?? "" },
                        set: { variableValues[variable.name] = $0 }
                    )
                )
                .textInputAutocapitalization(.never)
            }

            Button("Run") {
                let resolved = resolveSteps()
                onExecute(resolved)
            }
            .buttonStyle(.borderedProminent)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.name)
                    .font(.headline)
                if let role = snippet.targetPaneRole {
                    Text("Target: \(role.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resolveSteps() -> String {
        snippet.steps.map { step in
            var command = step.command
            for variable in snippet.variables {
                let value = variableValues[variable.name] ?? variable.defaultValue ?? ""
                command = command.replacingOccurrences(of: "{{\(variable.name)}}", with: value)
            }
            return command
        }.joined(separator: " && ")
    }
}
