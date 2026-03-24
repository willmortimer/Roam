import SwiftUI
import SwiftData

struct WorkspaceDetailView: View {
    @Environment(WorkspaceResumeOrchestrator.self) private var resumeOrchestrator
    let workspaceID: String
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [WorkspaceRecord]
    @Query(sort: \HostRecord.alias) private var hosts: [HostRecord]
    @State private var isResuming = false
    @State private var resumeErrorMessage: String?
    @State private var presentedSession: ManagedSession?
    @State private var showingEditor = false

    private var workspace: WorkspaceRecord? {
        workspaces.first { $0.id == workspaceID }
    }

    private var workspaceHost: HostRecord? {
        guard let workspace else { return nil }
        return hosts.first { $0.id == workspace.hostReference }
    }

    var body: some View {
        if let workspace {
            List {
                // Host warning
                if workspaceHost == nil {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("Host not found")
                                    .font(.subheadline.bold())
                                Text("The host this workspace references has been deleted. Edit this workspace to select a new host before resuming.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.Roam.caution)
                        }
                    }
                }

                Section("Connection") {
                    if let host = workspaceHost {
                        LabeledContent("Host", value: "\(host.alias) (\(host.hostname))")
                    } else {
                        LabeledContent("Host") {
                            Text("Missing")
                                .foregroundStyle(.Roam.danger)
                        }
                    }
                    if !workspace.shell.isEmpty {
                        LabeledContent("Shell", value: workspace.shell)
                    }
                    if !workspace.repoPath.isEmpty {
                        LabeledContent("Repo", value: workspace.repoPath)
                    }
                    if !workspace.environment.isEmpty {
                        LabeledContent("Environment") {
                            Text(workspace.environment.capitalized)
                                .codeBadge(color: environmentColor(workspace.environment))
                        }
                    }
                }

                Section("tmux") {
                    LabeledContent("Session", value: workspace.tmuxSessionName)
                    if let layout = workspace.tmuxLayoutTemplate {
                        LabeledContent("Layout", value: layout)
                    }
                    if workspace.tmuxPanes.isEmpty {
                        Text("No panes defined. Roles will be auto-detected on resume.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workspace.tmuxPanes, id: \.self) { pane in
                            LabeledContent(pane.role.rawValue.capitalized, value: pane.window)
                        }
                    }
                }

                if !workspace.savedForwards.isEmpty {
                    Section("Port Forwards") {
                        ForEach(workspace.savedForwards, id: \.self) { fwd in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(fwd.name.isEmpty ? "Port \(fwd.remotePort)" : fwd.name)
                                        .font(.subheadline)
                                    Text("\(fwd.remoteHost):\(fwd.remotePort)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if fwd.autoPreview {
                                    Text("Preview")
                                        .codeBadge(color: .accentColor)
                                }
                            }
                        }
                    }
                }

                if let agent = workspace.preferredAgentCommand {
                    Section("AI Agent") {
                        LabeledContent("Command", value: agent)
                    }
                }

                if !workspace.notes.isEmpty {
                    Section("Notes") {
                        Text(workspace.notes)
                            .font(.body)
                    }
                }

                if !workspace.tags.isEmpty {
                    Section("Tags") {
                        WorkspaceTagFlowLayout(spacing: Spacing.xs) {
                            ForEach(workspace.tags, id: \.self) { tag in
                                Text(tag)
                                    .codeBadge(color: .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(workspace.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Resume") {
                        Task { await resumeWorkspace(workspace) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResuming || workspaceHost == nil)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Edit", systemImage: "pencil") {
                        showingEditor = true
                    }
                }
            }
            .sheet(isPresented: $isResuming) {
                if let host = workspaceHost {
                    WorkspaceResumeSheet(
                        workspaceName: workspace.name,
                        host: host
                    )
                }
            }
            .sheet(isPresented: $showingEditor) {
                NavigationStack {
                    WorkspaceEditorView(existingWorkspace: workspace)
                }
            }
            .alert("Resume Failed", isPresented: .init(
                get: { resumeErrorMessage != nil },
                set: { if !$0 { resumeErrorMessage = nil } }
            )) {
                Button("OK") { resumeErrorMessage = nil }
            } message: {
                Text(resumeErrorMessage ?? "")
            }
            .fullScreenCover(item: $presentedSession) { session in
                NavigationStack {
                    SessionView(session: session)
                }
            }
        } else {
            ContentUnavailableView("Workspace not found", systemImage: "exclamationmark.triangle")
        }
    }

    private func environmentColor(_ env: String) -> Color {
        switch env {
        case "prod": .Roam.danger
        case "staging": .Roam.caution
        default: .Roam.alive
        }
    }

    private func resumeWorkspace(_ workspace: WorkspaceRecord) async {
        guard let host = workspaceHost else {
            resumeErrorMessage = "This workspace references a host that no longer exists. Edit the workspace to select a new host."
            return
        }

        isResuming = true
        defer { isResuming = false }

        do {
            let managed = try await resumeOrchestrator.resume(
                workspace: workspace,
                host: host,
                modelContext: modelContext
            )
            presentedSession = managed
        } catch {
            resumeErrorMessage = error.localizedDescription
        }
    }
}

// MARK: - Flow Layout for Tags

private struct WorkspaceTagFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
