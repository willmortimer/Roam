import SwiftUI

/// Expandable session info panel shown when tapping the terminal status bar.
/// Displays connection details, transfer stats, latency, host info, and quick actions.
struct SessionInfoPanel: View {
    let session: ManagedSession
    let sessionState: TerminalSessionState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                terminalSection
                transferSection
                gitSection
                hostSection
                actionsSection
            }
            .navigationTitle("Session Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent("Status") {
                HStack(spacing: Spacing.xs) {
                    ConnectionDot(state: session.connectionLiveness)
                    Text(connectionLabel)
                        .foregroundStyle(connectionColor)
                }
            }

            LabeledContent("Transport") {
                TransportBadge(transport: session.transportType)
            }

            LabeledContent("Uptime") {
                Text(sessionState.uptimeString)
                    .monospacedDigit()
            }

            if let latency = sessionState.latencyMS {
                LabeledContent("Latency") {
                    Text("\(latency) ms")
                        .monospacedDigit()
                        .foregroundStyle(latencyColor(latency))
                }
            }
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        Section("Terminal") {
            LabeledContent("Size") {
                Text(sessionState.sizeString)
                    .font(.system(.body, design: .monospaced))
            }

            if let title = sessionState.terminalTitle, !title.isEmpty {
                LabeledContent("Title") {
                    Text(title)
                        .lineLimit(2)
                }
            }

            if let cwd = sessionState.currentWorkingDirectory, !cwd.isEmpty {
                LabeledContent("Working Directory") {
                    Text(cwd)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Transfer

    private var transferSection: some View {
        Section("Data Transfer") {
            LabeledContent("Sent") {
                Text(formattedBytes(sessionState.bytesSent))
                    .monospacedDigit()
            }

            LabeledContent("Received") {
                Text(formattedBytes(sessionState.bytesReceived))
                    .monospacedDigit()
            }

            LabeledContent("Total") {
                Text(formattedBytes(sessionState.bytesSent + sessionState.bytesReceived))
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Git

    @ViewBuilder
    private var gitSection: some View {
        if sessionState.gitBranch != nil {
            Section("Git") {
                if let branch = sessionState.gitBranch {
                    LabeledContent("Branch") {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(sessionState.gitDirty ? .Roam.caution : .Roam.alive)
                            Text(branch)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }

                LabeledContent("Status") {
                    Text(sessionState.gitDirty ? "Dirty" : "Clean")
                        .foregroundStyle(sessionState.gitDirty ? .Roam.caution : .Roam.alive)
                }

                if sessionState.gitUncommittedCount > 0 {
                    LabeledContent("Uncommitted Changes") {
                        Text("\(sessionState.gitUncommittedCount)")
                            .monospacedDigit()
                            .foregroundStyle(.Roam.caution)
                    }
                }
            }
        }
    }

    // MARK: - Host

    private var hostSection: some View {
        Section("Host") {
            LabeledContent("Alias") {
                Text(session.hostAlias)
            }

            LabeledContent("Hostname") {
                Text(session.hostname)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }

            LabeledContent("User") {
                Text(session.username)
                    .font(.system(.body, design: .monospaced))
            }

            LabeledContent("Port") {
                Text("\(session.port)")
                    .monospacedDigit()
            }

            if session.isHelperAvailable {
                LabeledContent("Helper") {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.Roam.alive)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                let text = "\(session.username)@\(session.hostname):\(session.port)"
                UIPasteboard.general.string = text
            } label: {
                Label("Copy Connection String", systemImage: "doc.on.doc")
            }

            if let cwd = sessionState.currentWorkingDirectory, !cwd.isEmpty {
                Button {
                    UIPasteboard.general.string = cwd
                } label: {
                    Label("Copy Working Directory", systemImage: "folder")
                }
            }
        }
    }

    // MARK: - Helpers

    private var connectionLabel: String {
        switch session.connectionLiveness {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        case .unknown: "Unknown"
        }
    }

    private var connectionColor: Color {
        switch session.connectionLiveness {
        case .connected: .Roam.alive
        case .connecting: .Roam.caution
        case .disconnected: .Roam.danger
        case .unknown: .Roam.dormant
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 100 { return .Roam.alive }
        if ms < 300 { return .Roam.caution }
        return .Roam.danger
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
