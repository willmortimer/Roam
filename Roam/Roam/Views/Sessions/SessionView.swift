import SwiftUI
import SwiftData

/// Full terminal session view: terminal + modifier key bar + transport chrome.
struct SessionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(WorkspaceResumeOrchestrator.self) private var resumeOrchestrator
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [WorkspaceRecord]
    @AppStorage(TerminalSettingsKeys.fontFamily) private var terminalFontFamily: TerminalFontFamily = .system
    @AppStorage(TerminalSettingsKeys.fontSize) private var terminalFontSize = 13.0
    let session: ManagedSession
    @Environment(\.dismiss) private var dismiss
    @State private var sessionState = TerminalSessionState()
    @State private var showingSaveAsWorkspace = false
    @State private var showingSnippetPicker = false
    @State private var showingSessionInfo = false

    var body: some View {
        VStack(spacing: 0) {
            if session.isRestoring {
                reconnectBanner(
                    title: "Restoring Session",
                    subtitle: "Reconnecting the SSH session."
                )
            } else if let restoreErrorMessage = session.restoreErrorMessage {
                reconnectBanner(
                    title: "Reconnect Failed",
                    subtitle: restoreErrorMessage,
                    showsRetry: true
                )
            }

            if let workspace {
                WorkspaceSessionCockpitView(session: session, workspace: workspace)
            }

            TerminalViewRepresentable(
                bridge: session.bridge,
                sessionState: sessionState,
                fontFamily: terminalFontFamily,
                fontSize: terminalFontSize
            )
                .ignoresSafeArea(.keyboard, edges: .bottom)

            TerminalStatusBar(
                session: session,
                sessionState: sessionState,
                onTap: { showingSessionInfo = true }
            )

            ModifierKeyBar { key in
                Task {
                    try? await session.bridge.sendToRemote(key.bytes)
                }
            }
        }
        .onAppear {
            sessionState.connectedAt = session.createdAt
            fetchGitInfo()
        }
        .navigationTitle(session.hostAlias)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: Spacing.sm) {
                    ConnectionDot(state: session.connectionLiveness)
                    TransportBadge(transport: session.transportType)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Snippets", systemImage: "text.badge.star") {
                        showingSnippetPicker = true
                    }
                    if session.restorationContext.workspaceID == nil {
                        Button("Save as Workspace", systemImage: "square.and.arrow.down.on.square") {
                            showingSaveAsWorkspace = true
                        }
                    }
                    Divider()
                    Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                        Task {
                            await sessionManager.disconnectSession(id: session.id)
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Session options")
            }
        }
        .sheet(isPresented: $showingSaveAsWorkspace) {
            NavigationStack {
                WorkspaceEditorView(prefill: SessionPrefill.from(session: session))
            }
        }
        .sheet(isPresented: $showingSnippetPicker) {
            SnippetPickerView(
                workspaceID: session.restorationContext.workspaceID,
                hostID: session.restorationContext.hostID
            ) { command in
                Task {
                    let commandWithNewline = command + "\n"
                    guard let data = commandWithNewline.data(using: .utf8) else { return }
                    try? await session.bridge.sendToRemote(data)
                }
            }
        }
        .sheet(isPresented: $showingSessionInfo) {
            SessionInfoPanel(session: session, sessionState: sessionState)
        }
    }

    private func fetchGitInfo() {
        guard let helper = session.helperClient,
              let ws = workspace,
              !ws.repoPath.isEmpty else { return }
        Task {
            do {
                let status = try await helper.gitStatus(repoPath: ws.repoPath)
                await MainActor.run {
                    sessionState.gitBranch = status.branch
                    sessionState.gitDirty = !status.clean
                    sessionState.gitUncommittedCount = status.staged + status.modified + status.untracked
                }
            } catch {
                // Helper may not support git_status — silently ignore
            }
        }
    }

    private var workspace: WorkspaceRecord? {
        guard let workspaceID = session.restorationContext.workspaceID else {
            return nil
        }

        return workspaces.first { $0.id == workspaceID }
    }

    @ViewBuilder
    private func reconnectBanner(
        title: String,
        subtitle: String,
        showsRetry: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: showsRetry ? "exclamationmark.triangle" : "arrow.clockwise")
                    .foregroundStyle(showsRetry ? .Roam.caution : Color.accentColor)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if showsRetry {
                    Button("Retry") {
                        Task {
                            await sessionManager.reconnectSession(
                                id: session.id,
                                modelContext: modelContext,
                                resumeOrchestrator: resumeOrchestrator
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
