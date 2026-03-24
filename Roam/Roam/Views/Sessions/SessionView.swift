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
                fontFamily: terminalFontFamily,
                fontSize: terminalFontSize
            )
                .ignoresSafeArea(.keyboard, edges: .bottom)

            ModifierKeyBar { key in
                Task {
                    try? await session.bridge.sendToRemote(key.bytes)
                }
            }
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
