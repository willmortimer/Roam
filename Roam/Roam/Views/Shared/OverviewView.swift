import SwiftUI
import SwiftData

struct OverviewView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(WorkspaceResumeOrchestrator.self) private var resumeOrchestrator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkspaceRecord.lastOpened, order: .reverse) private var workspaces: [WorkspaceRecord]
    @Query(sort: \HostRecord.lastSeen, order: .reverse) private var hosts: [HostRecord]

    @State private var showingHostEditor = false
    @State private var showingWorkspaceEditor = false

    private var recentWorkspaces: [WorkspaceRecord] {
        Array(workspaces.prefix(4))
    }

    private var recentHosts: [HostRecord] {
        Array(hosts.sorted { ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast) }.prefix(4))
    }

    private var recentRestorableSessions: [PersistedSessionSnapshot] {
        sessionManager.restorableSessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(4)
            .map { $0 }
    }

    private var totalSessionCount: Int {
        sessionManager.sessions.count + sessionManager.restorableSessions.count
    }

    private var isEmptyState: Bool {
        workspaces.isEmpty && hosts.isEmpty && sessionManager.sessions.isEmpty && sessionManager.restorableSessions.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                heroCard
                quickActionsCard

                if !sessionManager.sessions.isEmpty {
                    activeSessionsCard
                }

                if !recentRestorableSessions.isEmpty {
                    restorableSessionsCard
                }

                if !recentWorkspaces.isEmpty {
                    recentWorkspacesCard
                }

                if !recentHosts.isEmpty {
                    recentHostsCard
                }

                if isEmptyState {
                    gettingStartedCard
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Workspace", systemImage: "plus.square.on.square") {
                        showingWorkspaceEditor = true
                    }
                    Button("New Host", systemImage: "server.rack") {
                        showingHostEditor = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create")
            }
        }
        .sheet(isPresented: $showingWorkspaceEditor) {
            NavigationStack {
                WorkspaceEditorView()
            }
        }
        .sheet(isPresented: $showingHostEditor) {
            NavigationStack {
                HostEditorView()
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("ROAM")
                .font(.caption.weight(.bold))
                .tracking(4)
                .foregroundStyle(.secondary)

            Text("Remote Work, Ready to Resume")
                .font(.title2.bold())

            Text("Jump back into recent workspaces, reconnect to hosts, and recover session context without digging through separate tools.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.md) {
                OverviewStat(title: "Workspaces", value: workspaces.count, symbol: "square.stack.3d.up")
                OverviewStat(title: "Hosts", value: hosts.count, symbol: "server.rack")
                OverviewStat(title: "Sessions", value: totalSessionCount, symbol: "terminal")
            }
        }
        .cardStyle()
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(
                title: "Quick Actions",
                symbol: "bolt.fill"
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.md),
                    GridItem(.flexible(), spacing: Spacing.md),
                ],
                spacing: Spacing.md
            ) {
                NavigationLink {
                    WorkspaceListView()
                } label: {
                    OverviewActionTile(
                        title: "Workspaces",
                        subtitle: "Browse and resume saved setups",
                        symbol: "square.stack.3d.up"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    HostListView()
                } label: {
                    OverviewActionTile(
                        title: "Hosts",
                        subtitle: "Open host records and connect",
                        symbol: "server.rack"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    SessionListView()
                } label: {
                    OverviewActionTile(
                        title: "Sessions",
                        subtitle: "See active and restorable shells",
                        symbol: "terminal"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    FileBrowserView(sftpChannel: nil)
                } label: {
                    OverviewActionTile(
                        title: "Files",
                        subtitle: "Open the remote file browser",
                        symbol: "folder"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private var activeSessionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Active Sessions",
                symbol: "terminal",
                accessory: AnyView(
                    NavigationLink("All") {
                        SessionListView()
                    }
                    .font(.caption.weight(.semibold))
                )
            )
            .padding(.bottom, Spacing.sm)

            ForEach(Array(sessionManager.sessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                if index > 0 {
                    Divider().padding(.leading, 20)
                }
                NavigationLink {
                    SessionView(session: session)
                } label: {
                    OverviewActiveSessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private var restorableSessionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Resume Sessions",
                symbol: "arrow.clockwise",
                accessory: AnyView(
                    NavigationLink("All") {
                        SessionListView()
                    }
                    .font(.caption.weight(.semibold))
                )
            )
            .padding(.bottom, Spacing.sm)

            ForEach(Array(recentRestorableSessions.enumerated()), id: \.element.id) { index, snapshot in
                if index > 0 {
                    Divider().padding(.leading, 20)
                }
                Button {
                    Task {
                        await sessionManager.retryRestorableSession(
                            id: snapshot.id,
                            modelContext: modelContext,
                            resumeOrchestrator: resumeOrchestrator
                        )
                    }
                } label: {
                    OverviewRestorableSessionRow(snapshot: snapshot)
                }
                .buttonStyle(.plain)
                .disabled(snapshot.restoreStatus == .restoring)
            }
        }
        .cardStyle()
    }

    private var recentWorkspacesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Recent Workspaces",
                symbol: "square.stack.3d.up",
                accessory: AnyView(
                    NavigationLink("All") {
                        WorkspaceListView()
                    }
                    .font(.caption.weight(.semibold))
                )
            )
            .padding(.bottom, Spacing.sm)

            ForEach(Array(recentWorkspaces.enumerated()), id: \.element.id) { index, workspace in
                if index > 0 {
                    Divider().padding(.leading, 20)
                }
                NavigationLink {
                    WorkspaceDetailView(workspaceID: workspace.id)
                } label: {
                    WorkspaceRow(workspace: workspace)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private var recentHostsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                title: "Recent Hosts",
                symbol: "server.rack",
                accessory: AnyView(
                    NavigationLink("All") {
                        HostListView()
                    }
                    .font(.caption.weight(.semibold))
                )
            )
            .padding(.bottom, Spacing.sm)

            ForEach(Array(recentHosts.enumerated()), id: \.element.id) { index, host in
                if index > 0 {
                    Divider().padding(.leading, 20)
                }
                NavigationLink {
                    HostDetailView(hostID: host.id)
                } label: {
                    HostRow(host: host)
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private var gettingStartedCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader(title: "Getting Started", symbol: "sparkles")

            Text("Create a host or workspace to turn this into a one-tap launchpad for your remote development flow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: Spacing.sm) {
                Button("New Workspace", systemImage: "plus.square.on.square") {
                    showingWorkspaceEditor = true
                }
                .buttonStyle(.borderedProminent)

                Button("New Host", systemImage: "server.rack") {
                    showingHostEditor = true
                }
                .buttonStyle(.bordered)
            }
        }
        .cardStyle()
    }

    private func sectionHeader(
        title: String,
        symbol: String,
        accessory: AnyView? = nil
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Label(title, systemImage: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Spacer()

            accessory
        }
    }
}

private struct OverviewStat: View {
    let title: String
    let value: Int
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
            Text("\(value)")
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OverviewActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.Roam.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OverviewActiveSessionRow: View {
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
                }
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
    }
}

private struct OverviewRestorableSessionRow: View {
    let snapshot: PersistedSessionSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if snapshot.restoreStatus == .restoring {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            } else {
                Image(systemName: snapshot.source == .workspace ? "arrow.clockwise.circle" : "terminal")
                    .foregroundStyle(snapshot.restoreStatus == .failed ? .Roam.caution : .accentColor)
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
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xs)
    }
}
