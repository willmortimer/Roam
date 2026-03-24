import SwiftUI
import SwiftData

struct WorkspaceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkspaceRecord.lastOpened, order: .reverse) private var workspaces: [WorkspaceRecord]
    @State private var searchText = ""
    @State private var showingEditor = false

    var body: some View {
        List {
            if filteredWorkspaces.isEmpty {
                ContentUnavailableView(
                    "No Workspaces",
                    systemImage: "square.stack.3d.up",
                    description: Text("Create a workspace to bundle a host, repo, tmux session, and port forwards into a one-tap resume flow.")
                )
            } else {
                ForEach(filteredWorkspaces, id: \.id) { workspace in
                    NavigationLink(value: WorkspaceNavigationTarget(id: workspace.id)) {
                        WorkspaceRow(workspace: workspace)
                    }
                }
                .onDelete(perform: deleteWorkspaces)
            }
        }
        .searchable(text: $searchText, prompt: "Search workspaces")
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Workspace", systemImage: "plus") {
                    showingEditor = true
                }
            }
        }
        .navigationDestination(for: WorkspaceNavigationTarget.self) { target in
            WorkspaceDetailView(workspaceID: target.id)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                WorkspaceEditorView()
            }
        }
    }

    private var filteredWorkspaces: [WorkspaceRecord] {
        if searchText.isEmpty { return workspaces }
        return workspaces.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private func deleteWorkspaces(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredWorkspaces[index])
        }
    }
}

private struct WorkspaceNavigationTarget: Hashable {
    let id: String
}

struct WorkspaceRow: View {
    let workspace: WorkspaceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(workspace.name)
                .font(.headline)

            if !workspace.descriptionText.isEmpty {
                Text(workspace.descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !workspace.repoPath.isEmpty {
                Text(workspace.repoPath)
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: Spacing.sm) {
                EnvironmentBadge(environment: workspace.environment)

                if let lastOpened = workspace.lastOpened {
                    Text(lastOpened, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !workspace.tags.isEmpty {
                    Text(workspace.tags.prefix(2).joined(separator: ", "))
                        .codeBadge(color: .Roam.dormant)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workspace.name), \(workspace.environment) workspace")
    }
}
