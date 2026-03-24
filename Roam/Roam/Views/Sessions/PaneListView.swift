import SwiftUI

/// Shows tmux panes with semantic role badges and role-specific actions.
struct PaneListView: View {
    let panes: [TmuxPaneDTO]
    let paneDefinitions: [PaneDefinition]
    let onRoleChanged: (String, PaneRole?) -> Void
    let onSendKeys: (String, String) async -> Void
    let onCapturePane: (String) async -> String?
    let onOpenLens: (Lens) -> Void

    @State private var capturedContent: String?
    @State private var capturedPaneID: String?
    @State private var showingCapture = false
    @State private var commandText = ""
    @State private var commandTargetPane: String?

    var body: some View {
        List {
            ForEach(panes, id: \.pane_id) { pane in
                PaneRow(
                    pane: pane,
                    role: roleForPane(pane),
                    onRoleChanged: { newRole in
                        onRoleChanged(pane.pane_id, newRole)
                    },
                    onCapture: {
                        Task {
                            if let content = await onCapturePane(pane.pane_id) {
                                capturedContent = content
                                capturedPaneID = pane.pane_id
                                showingCapture = true
                            }
                        }
                    },
                    onSendCommand: {
                        commandTargetPane = pane.pane_id
                    },
                    onOpenLens: { lens in
                        onOpenLens(lens)
                    }
                )
            }
        }
        .navigationTitle("Panes")
        .sheet(isPresented: $showingCapture) {
            NavigationStack {
                ScrollView {
                    Text(capturedContent ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("Pane \(capturedPaneID ?? "")")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingCapture = false }
                    }
                }
            }
        }
        .sheet(isPresented: .init(
            get: { commandTargetPane != nil },
            set: { if !$0 { commandTargetPane = nil } }
        )) {
            CommandInputSheet(
                commandText: $commandText,
                onSend: {
                    guard let paneID = commandTargetPane, !commandText.isEmpty else { return }
                    let cmd = commandText
                    commandText = ""
                    commandTargetPane = nil
                    Task { await onSendKeys(paneID, cmd) }
                },
                onCancel: {
                    commandText = ""
                    commandTargetPane = nil
                }
            )
        }
    }

    private func roleForPane(_ pane: TmuxPaneDTO) -> PaneRole? {
        paneDefinitions.first { $0.window == pane.window }?.role
    }
}

private struct CommandInputSheet: View {
    @Binding var commandText: String
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Send Command") {
                    TextField("Command", text: $commandText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        onSend()
                    } label: {
                        Label("Send", systemImage: "paperplane")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Send Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Pane Row

private struct PaneRow: View {
    let pane: TmuxPaneDTO
    let role: PaneRole?
    let onRoleChanged: (PaneRole?) -> Void
    let onCapture: () -> Void
    let onSendCommand: () -> Void
    let onOpenLens: (Lens) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(pane.window)
                    .font(.headline)

                if pane.active {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.Roam.alive)
                }

                Spacer()

                if let role {
                    RoleBadge(role: role)
                }
            }

            HStack {
                Label(pane.current_command, systemImage: "terminal")
                Spacer()
                Text("\(pane.width)x\(pane.height)")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !pane.cwd.isEmpty {
                Text(pane.cwd)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            if let primaryLens {
                Button {
                    onOpenLens(primaryLens)
                } label: {
                    Label("Open \(primaryLens.label)", systemImage: primaryLens.icon)
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            // Role picker
            Menu("Set Role") {
                Button("None") { onRoleChanged(nil) }
                ForEach(PaneRole.allCases, id: \.self) { r in
                    Button {
                        onRoleChanged(r)
                    } label: {
                        Label(r.rawValue.capitalized, systemImage: r.icon)
                    }
                }
            }

            Divider()

            Button("Capture Output", systemImage: "doc.text") {
                onCapture()
            }

            Button("Send Command", systemImage: "paperplane") {
                onSendCommand()
            }

            if let primaryLens {
                Button("Open \(primaryLens.label)", systemImage: primaryLens.icon) {
                    onOpenLens(primaryLens)
                }
            }
        }
    }

    private var primaryLens: Lens? {
        switch role {
        case .tests:
            .tests
        case .logs:
            .logs
        case .server:
            .ports
        default:
            nil
        }
    }
}

// MARK: - Role Badge

struct RoleBadge: View {
    let role: PaneRole

    var body: some View {
        Label(role.rawValue.capitalized, systemImage: role.icon)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(role.color.opacity(0.15), in: Capsule())
            .foregroundStyle(role.color)
    }
}

// MARK: - PaneRole UI Extensions

extension PaneRole {
    var icon: String {
        switch self {
        case .shell: "terminal"
        case .agent: "cpu"
        case .tests: "checkmark.circle"
        case .server: "server.rack"
        case .logs: "doc.text"
        case .db: "cylinder"
        case .scratch: "note.text"
        }
    }

    var color: Color {
        switch self {
        case .shell: .primary
        case .agent: .purple
        case .tests: .Roam.alive
        case .server: .accentColor
        case .logs: .Roam.caution
        case .db: .Roam.danger
        case .scratch: .secondary
        }
    }
}
