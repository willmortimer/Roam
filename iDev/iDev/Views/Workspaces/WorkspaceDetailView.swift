import SwiftUI
import SwiftData

struct WorkspaceDetailView: View {
    let workspaceID: String
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [WorkspaceRecord]

    private var workspace: WorkspaceRecord? {
        workspaces.first { $0.id == workspaceID }
    }

    var body: some View {
        if let workspace {
            List {
                Section("Connection") {
                    LabeledContent("Host", value: workspace.hostReference)
                    LabeledContent("Shell", value: workspace.shell)
                    LabeledContent("Repo", value: workspace.repoPath)
                }
                Section("tmux") {
                    LabeledContent("Session", value: workspace.tmuxSessionName)
                    if let layout = workspace.tmuxLayoutTemplate {
                        LabeledContent("Layout", value: layout)
                    }
                    ForEach(workspace.tmuxPanes, id: \.self) { pane in
                        LabeledContent(pane.role.rawValue.capitalized, value: pane.window)
                    }
                }
                if !workspace.savedForwards.isEmpty {
                    Section("Port Forwards") {
                        ForEach(workspace.savedForwards, id: \.self) { fwd in
                            LabeledContent(fwd.name, value: "\(fwd.remoteHost):\(fwd.remotePort)")
                        }
                    }
                }
                if let agent = workspace.preferredAgentCommand {
                    Section("Agent") {
                        LabeledContent("Command", value: agent)
                    }
                }
                if !workspace.notes.isEmpty {
                    Section("Notes") {
                        Text(workspace.notes)
                            .font(.body)
                    }
                }
            }
            .navigationTitle(workspace.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Resume") {
                        // TODO: trigger workspace resume orchestrator
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            ContentUnavailableView("Workspace not found", systemImage: "exclamationmark.triangle")
        }
    }
}
