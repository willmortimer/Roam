import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SessionManager.self) private var sessionManager
    @Query private var workspaces: [WorkspaceRecord]
    @State private var showCommandPalette = false
    @State private var showCommitSheet = false
    @State private var gitOperationMessage: String?

    /// First active session with a helper, used for command palette actions.
    private var activeSession: ManagedSession? {
        sessionManager.sessions.first { $0.isHelperAvailable }
            ?? sessionManager.sessions.first
    }

    private var activeWorkspace: WorkspaceRecord? {
        guard let wsID = activeSession?.restorationContext.workspaceID else { return nil }
        return workspaces.first { $0.id == wsID }
    }

    private var paletteContext: PaletteContext {
        let session = activeSession
        let ws = activeWorkspace
        return PaletteContext(
            hasActiveSession: !sessionManager.sessions.isEmpty,
            hasHelper: session?.isHelperAvailable ?? false,
            repoPath: ws?.repoPath.isEmpty == false ? ws?.repoPath : nil,
            hasSFTP: session?.sftpChannel != nil,
            hasActivePreview: session?.forwardService?.activeForwards.isEmpty == false,
            hasTeamVault: false
        )
    }

    private var paletteProvider: DefaultPaletteActionProvider {
        DefaultPaletteActionProvider(
            navigateToTab: { tab in
                selectedSection = AppSection(rawValue: tab)
                showCommandPalette = false
            },
            onSwitchLens: { _ in
                selectedSection = .sessions
                showCommandPalette = false
            },
            onSharePreview: {
                selectedSection = .sessions
                showCommandPalette = false
            },
            onParseTestReport: {
                selectedSection = .sessions
                showCommandPalette = false
            },
            onGitCommit: {
                showCommandPalette = false
                showCommitSheet = true
            },
            onGitPush: {
                guard let helper = activeSession?.helperClient,
                      let repoPath = activeWorkspace?.repoPath, !repoPath.isEmpty else { return }
                showCommandPalette = false
                do {
                    let result = try await helper.gitPush(repoPath: repoPath, setUpstream: false)
                    gitOperationMessage = result.message.isEmpty ? "Push complete." : result.message
                } catch {
                    gitOperationMessage = error.localizedDescription
                }
            },
            onGitPull: {
                guard let helper = activeSession?.helperClient,
                      let repoPath = activeWorkspace?.repoPath, !repoPath.isEmpty else { return }
                showCommandPalette = false
                do {
                    let result = try await helper.gitPull(repoPath: repoPath, rebase: false)
                    gitOperationMessage = result.message.isEmpty ? "Pull complete." : result.message
                } catch {
                    gitOperationMessage = error.localizedDescription
                }
            }
        )
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                sidebarNavigation
            } else {
                tabNavigation
            }
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                provider: paletteProvider,
                context: paletteContext
            )
        }
        .sheet(isPresented: $showCommitSheet) {
            if let helper = activeSession?.helperClient,
               let repoPath = activeWorkspace?.repoPath, !repoPath.isEmpty {
                CommitSheet(helperClient: helper, repoPath: repoPath) {
                    showCommitSheet = false
                }
            }
        }
        .alert("Git", isPresented: .init(
            get: { gitOperationMessage != nil },
            set: { if !$0 { gitOperationMessage = nil } }
        )) {
            Button("OK") { gitOperationMessage = nil }
        } message: {
            Text(gitOperationMessage ?? "")
        }
        .background {
            // Hidden buttons for hardware keyboard shortcuts
            Group {
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("") { selectedSection = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedSection = .hosts }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedSection = .sessions }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selectedSection = .files }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { selectedSection = .vault }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { selectedSection = .settings }
                    .keyboardShortcut("6", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    // MARK: - iPhone (compact)

    private var tabNavigation: some View {
        TabView {
            Tab("Overview", systemImage: "house") {
                NavigationStack {
                    OverviewView()
                }
            }
            Tab("Hosts", systemImage: "server.rack") {
                NavigationStack {
                    HostListView()
                }
            }
            Tab("Sessions", systemImage: "terminal") {
                NavigationStack {
                    SessionListView()
                }
            }
            Tab("Files", systemImage: "folder") {
                NavigationStack {
                    FileBrowserView(sftpChannel: nil)
                }
            }
            Tab("Vault", systemImage: "lock.shield") {
                NavigationStack {
                    VaultView()
                }
            }
            Tab("Settings", systemImage: "gear") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }

    @State private var selectedSection: AppSection? = .overview

    // MARK: - iPad (regular)

    @State private var detailPath = NavigationPath()

    private var sidebarNavigation: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
            }
            .navigationTitle("Roam")
        } detail: {
            if let section = selectedSection {
                NavigationStack(path: $detailPath) {
                    section.destination
                }
            } else {
                ContentUnavailableView(
                    "Welcome to Roam",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Choose a section to jump into hosts, workspaces, files, or active sessions.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedSection) { _, _ in
            detailPath = NavigationPath()
        }
    }
}

// MARK: - App Sections

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case hosts
    case sessions
    case files
    case vault
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .hosts: "Hosts"
        case .sessions: "Sessions"
        case .files: "Files"
        case .vault: "Vault"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: "house"
        case .hosts: "server.rack"
        case .sessions: "terminal"
        case .files: "folder"
        case .vault: "lock.shield"
        case .settings: "gear"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .overview: OverviewView()
        case .hosts: HostListView()
        case .sessions: SessionListView()
        case .files: FileBrowserView(sftpChannel: nil)
        case .vault: VaultView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    let sessionManager = SessionManager()
    let resumeOrchestrator = WorkspaceResumeOrchestrator(
        sessionManager: sessionManager,
        vaultService: VaultService.shared,
        authGateService: AuthGateService.shared
    )

    MainTabView()
        .modelContainer(for: [
            HostRecord.self,
            WorkspaceRecord.self,
            SnippetRecord.self,
        ], inMemory: true)
        .environment(sessionManager)
        .environment(resumeOrchestrator)
}
