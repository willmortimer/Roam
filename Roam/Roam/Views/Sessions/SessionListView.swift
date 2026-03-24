import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(WorkspaceResumeOrchestrator.self) private var resumeOrchestrator
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if sessionManager.sessions.isEmpty && sessionManager.restorableSessions.isEmpty {
                ContentUnavailableView(
                    "No Active Sessions",
                    systemImage: "terminal",
                    description: Text("Connect to a host or resume a workspace to start a session.")
                )
            } else {
                List {
                    if !sessionManager.sessions.isEmpty {
                        Section("Active") {
                            ForEach(sessionManager.sessions) { session in
                                NavigationLink {
                                    SessionView(session: session)
                                } label: {
                                    SessionRow(session: session)
                                }
                            }
                            .onDelete(perform: disconnectSessions)
                        }
                    }

                    if !sessionManager.restorableSessions.isEmpty {
                        Section("Restore") {
                            ForEach(sessionManager.restorableSessions) { snapshot in
                                Button {
                                    Task {
                                        await sessionManager.retryRestorableSession(
                                            id: snapshot.id,
                                            modelContext: modelContext,
                                            resumeOrchestrator: resumeOrchestrator
                                        )
                                    }
                                } label: {
                                    RestorableSessionRow(snapshot: snapshot)
                                }
                                .buttonStyle(.plain)
                                .disabled(snapshot.restoreStatus == .restoring)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Remove", role: .destructive) {
                                        sessionManager.removeRestorableSession(id: snapshot.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }

    private func disconnectSessions(at offsets: IndexSet) {
        let sessionIDs = offsets.map { sessionManager.sessions[$0].id }
        Task {
            for sessionID in sessionIDs {
                await sessionManager.disconnectSession(id: sessionID)
            }
        }
    }
}

private struct SessionRow: View {
    let session: ManagedSession

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ConnectionDot(state: session.connectionLiveness)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(session.hostAlias)
                    .font(.headline)

                AddressLabel(username: session.username, hostname: session.hostname, port: session.port)

                HStack(spacing: Spacing.sm) {
                    TransportBadge(transport: session.transportType)

                    if session.isHelperAvailable {
                        Text("Helper")
                            .codeBadge(color: .Roam.alive)
                    }

                    if session.isRestoring {
                        Text("Restoring")
                            .codeBadge(color: .Roam.dormant)
                    } else if session.restoreErrorMessage != nil {
                        Text("Reconnect Failed")
                            .codeBadge(color: .Roam.caution)
                    }
                }

                if let restoreErrorMessage = session.restoreErrorMessage {
                    Text(restoreErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.hostAlias), \(session.hostname), active session")
    }
}

private struct RestorableSessionRow: View {
    let snapshot: PersistedSessionSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if snapshot.restoreStatus == .restoring {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            } else {
                Image(systemName: snapshot.source == .workspace ? "arrow.clockwise.circle" : "terminal")
                    .foregroundStyle(snapshot.restoreStatus == .failed ? .Roam.caution : Color.accentColor)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(snapshot.displayName)
                    .font(.headline)

                AddressLabel(username: snapshot.username, hostname: snapshot.hostname, port: snapshot.port)

                HStack(spacing: Spacing.sm) {
                    Text(snapshot.source == .workspace ? "Workspace" : "Shell")
                        .codeBadge(color: .Roam.dormant)

                    Text(snapshot.restoreStatus.title)
                        .codeBadge(color: snapshot.restoreStatus == .failed ? .Roam.caution : .Roam.dormant)
                }

                if let lastErrorMessage = snapshot.lastErrorMessage {
                    Text(lastErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.displayName), \(snapshot.hostname), \(snapshot.restoreStatus.title)")
        .accessibilityHint("Tap to restore this session")
    }
}
