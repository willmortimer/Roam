import SwiftUI

/// Displays per-workspace command history with search, filter, and re-send.
struct CommandTimelineView: View {
    @Bindable var viewModel: CommandTimelineViewModel
    let onResend: (String) async -> Void

    var body: some View {
        List {
            if viewModel.commands.isEmpty {
                ContentUnavailableView(
                    "No Commands",
                    systemImage: "clock",
                    description: Text("Commands sent during this session will appear here.")
                )
            } else {
                ForEach(viewModel.commands, id: \.id) { command in
                    CommandRow(command: command) {
                        Task { await onResend(command.command) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.deleteCommand(command)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchText)
        .onChange(of: viewModel.searchText) { viewModel.refresh() }
        .navigationTitle("Commands")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("All Roles") {
                        viewModel.filterRole = nil
                        viewModel.refresh()
                    }
                    ForEach(PaneRole.allCases, id: \.self) { role in
                        Button {
                            viewModel.filterRole = role
                            viewModel.refresh()
                        } label: {
                            Label(role.rawValue.capitalized, systemImage: role.icon)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: CommandRecord
    let onResend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command.command)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(command.timestamp, style: .relative)

                if let role = command.paneRole {
                    RoleBadge(role: role)
                }

                Text(command.source.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.fill.tertiary, in: Capsule())
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Re-send", systemImage: "paperplane") {
                onResend()
            }
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = command.command
            }
        }
    }
}
