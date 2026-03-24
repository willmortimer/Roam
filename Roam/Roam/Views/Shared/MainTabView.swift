import SwiftUI
import SwiftData
import RoamSSH

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SessionManager.self) private var sessionManager
    @Environment(URLSchemeHandler.self) private var urlSchemeHandler
    @Query private var workspaces: [WorkspaceRecord]
    @State private var showCommandPalette = false
    @State private var showCommitSheet = false
    @State private var showClipboardHistory = false
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
        .sheet(isPresented: $showClipboardHistory) {
            ClipboardHistoryView()
        }
        .background {
            // Hidden buttons for hardware keyboard shortcuts
            Group {
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("") { showClipboardHistory = true }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("") { selectedSection = .overview }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selectedSection = .hosts }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selectedSection = .workspaces }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selectedSection = .sessions }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { selectedSection = .files }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { selectedSection = .vault }
                    .keyboardShortcut("6", modifiers: .command)
                Button("") { selectedSection = .settings }
                    .keyboardShortcut("7", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .onChange(of: urlSchemeHandler.pendingAction) { _, action in
            guard let action else { return }
            handleDeepLink(action)
            urlSchemeHandler.pendingAction = nil
        }
    }

    private func handleDeepLink(_ action: URLSchemeHandler.DeepLinkAction) {
        switch action {
        case .navigateToSection(let rawValue):
            if let section = AppSection(rawValue: rawValue) {
                selectedSection = section
            }
        case .connectHost:
            selectedSection = .hosts
        case .openWorkspace:
            selectedSection = .workspaces
        case .openNotes, .openLocalFiles:
            selectedSection = .files
        case .openRemoteFiles:
            selectedSection = .files
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
            Tab("Workspaces", systemImage: "square.stack.3d.up") {
                NavigationStack {
                    WorkspaceListView()
                }
            }
            Tab("Sessions", systemImage: "terminal") {
                NavigationStack {
                    SessionListView()
                }
            }
            Tab("Files", systemImage: "folder") {
                NavigationStack {
                    ConnectedFileBrowserView()
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
    case workspaces
    case sessions
    case files
    case vault
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .hosts: "Hosts"
        case .workspaces: "Workspaces"
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
        case .workspaces: "square.stack.3d.up"
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
        case .workspaces: WorkspaceListView()
        case .sessions: SessionListView()
        case .files: ConnectedFileBrowserView()
        case .vault: VaultView()
        case .settings: SettingsView()
        }
    }
}

/// Files tab with Local/Remote segmented picker.
private struct ConnectedFileBrowserView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.modelContext) private var modelContext
    @Query private var workspaces: [WorkspaceRecord]
    @Query(sort: \HostRecord.alias) private var hosts: [HostRecord]

    @State private var fileMode: FileMode = .local
    @State private var standaloneSFTP: SFTPChannel?
    @State private var standaloneSession: LibSSH2Session?
    @State private var connectingHost: HostRecord?

    enum FileMode: String, CaseIterable {
        case local = "Local"
        case remote = "Remote"
    }

    private var activeSession: ManagedSession? {
        sessionManager.sessions.first { $0.sftpChannel != nil }
            ?? sessionManager.sessions.first
    }

    private var resolvedSFTP: SFTPChannel? {
        activeSession?.sftpChannel ?? standaloneSFTP
    }

    private var initialPath: String {
        guard let wsID = activeSession?.restorationContext.workspaceID,
              let ws = workspaces.first(where: { $0.id == wsID }),
              !ws.repoPath.isEmpty else {
            return "/"
        }
        return ws.repoPath
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("File Source", selection: $fileMode) {
                ForEach(FileMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)

            Group {
                switch fileMode {
                case .local:
                    LocalFileBrowserView()
                case .remote:
                    remoteFileBrowser
                }
            }
            .frame(maxHeight: .infinity)
        }
        .sheet(item: $connectingHost) { host in
            SFTPConnectionSheet(host: host) { session, sftp in
                standaloneSession = session
                standaloneSFTP = sftp
                connectingHost = nil
            }
        }
    }

    @ViewBuilder
    private var remoteFileBrowser: some View {
        if resolvedSFTP != nil {
            FileBrowserView(
                sftpChannel: resolvedSFTP,
                initialPath: initialPath
            )
            .toolbar {
                if standaloneSFTP != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Disconnect", systemImage: "xmark.circle") {
                            disconnectStandalone()
                        }
                    }
                }
            }
        } else {
            SFTPHostPickerView(hosts: hosts) { host in
                connectingHost = host
            }
        }
    }

    private func disconnectStandalone() {
        standaloneSFTP = nil
        if let session = standaloneSession {
            standaloneSession = nil
            Task { await session.disconnect() }
        }
    }
}

// MARK: - SFTP Host Picker

private struct SFTPHostPickerView: View {
    let hosts: [HostRecord]
    let onSelect: (HostRecord) -> Void

    @State private var searchText = ""

    private var filteredHosts: [HostRecord] {
        if searchText.isEmpty { return hosts }
        return hosts.filter {
            $0.alias.localizedCaseInsensitiveContains(searchText) ||
            $0.hostname.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if hosts.isEmpty {
                ContentUnavailableView(
                    "No Hosts",
                    systemImage: "server.rack",
                    description: Text("Add a host in the Hosts tab to browse files over SFTP.")
                )
            } else {
                List {
                    Section {
                        ForEach(filteredHosts, id: \.id) { host in
                            Button {
                                onSelect(host)
                            } label: {
                                HostRow(host: host)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Select a host to connect via SFTP")
                    }
                }
                .searchable(text: $searchText, prompt: "Search hosts")
            }
        }
        .navigationTitle("Files")
    }
}

// MARK: - SFTP Connection Sheet

private struct SFTPConnectionSheet: View {
    let host: HostRecord
    let onConnected: (LibSSH2Session, SFTPChannel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var phase: SFTPConnectionPhase = .connecting
    @State private var errorMessage: String?
    @State private var passwordPrompt = false
    @State private var password = ""
    @State private var activeSession: LibSSH2Session?
    @State private var pendingPasswordSession: LibSSH2Session?
    @State private var hostKeyVerification: HostKeyVerificationState?
    @State private var didHandOff = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Spacer()

                phaseIcon
                    .font(.largeTitle)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: Spacing.sm) {
                    Text(phaseTitle)
                        .font(.title3.bold())
                        .contentTransition(.numericText())

                    Text(phaseSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xxl)
                }

                if phase != .failed {
                    stepsIndicator
                }

                Spacer()

                if phase == .failed {
                    Button("Dismiss") {
                        Task { await cancelConnection() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .animation(.snappy(duration: 0.3), value: phase)
            .padding()
            .navigationTitle("SFTP Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { await cancelConnection() }
                    }
                }
            }
            .sheet(isPresented: $passwordPrompt) {
                PasswordPromptSheet(
                    username: host.username,
                    hostname: host.hostname,
                    password: $password,
                    onConnect: {
                        Task { await connectWithPassword() }
                    },
                    onCancel: {
                        Task { await cancelConnection() }
                    }
                )
            }
            .sheet(item: $hostKeyVerification) { verification in
                HostKeyVerificationSheet(
                    hostname: host.hostname,
                    port: host.port,
                    hostKey: verification.hostKey,
                    existingRecord: verification.existingRecord,
                    onDecision: { decision in
                        hostKeyVerification = nil
                        Task { await handleHostKeyDecision(decision, session: verification.session) }
                    }
                )
            }
            .task {
                await startConnection()
            }
            .onDisappear {
                guard !didHandOff else { return }
                Task { await cleanupSessionIfNeeded() }
            }
        }
    }

    // MARK: - Phase Display

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .connecting:
            Image(systemName: "network")
                .foregroundStyle(.tint)
        case .verifyingHostKey:
            Image(systemName: "lock.shield")
                .foregroundStyle(.tint)
        case .authenticating:
            Image(systemName: "person.badge.key")
                .foregroundStyle(.tint)
        case .openingSFTP:
            Image(systemName: "folder")
                .foregroundStyle(.tint)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.Roam.danger)
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .connecting: "Connecting"
        case .verifyingHostKey: "Verifying Host Key"
        case .authenticating: "Authenticating"
        case .openingSFTP: "Opening SFTP"
        case .failed: "Connection Failed"
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case .connecting: "\(host.hostname):\(host.port)"
        case .verifyingHostKey: "Checking known hosts"
        case .authenticating: host.username
        case .openingSFTP: "Almost there..."
        case .failed: errorMessage ?? "An unknown error occurred."
        }
    }

    private var stepsIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(SFTPConnectionPhase.orderedPhases, id: \.self) { step in
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 8, height: 8)
                    .scaleEffect(step == phase ? 1.3 : 1.0)
                    .animation(.spring(duration: 0.3), value: phase)
            }
        }
        .padding(.top, Spacing.sm)
    }

    private func stepColor(for step: SFTPConnectionPhase) -> Color {
        let ordered = SFTPConnectionPhase.orderedPhases
        guard let currentIndex = ordered.firstIndex(of: phase),
              let stepIndex = ordered.firstIndex(of: step) else {
            return .Roam.dormant
        }
        if stepIndex < currentIndex { return .Roam.alive }
        if stepIndex == currentIndex { return .accentColor }
        return .Roam.dormant
    }

    // MARK: - Connection Flow

    private func startConnection() async {
        let session = LibSSH2Session()
        activeSession = session
        didHandOff = false

        do {
            phase = .connecting
            try await session.connect(hostname: host.hostname, port: host.port)

            phase = .verifyingHostKey
            let hostKeyInfo = try session.hostKey()
            let knownHostsService = KnownHostsService(modelContext: modelContext)
            let sshHostKey = SSHHostKey(
                algorithm: hostKeyInfo.algorithm,
                fingerprint: hostKeyInfo.fingerprint,
                rawKey: hostKeyInfo.rawKey
            )

            let verification = knownHostsService.verify(
                hostname: host.hostname,
                port: host.port,
                hostKey: sshHostKey
            )

            switch verification {
            case .trusted:
                await proceedToAuth(session: session)
            case .newHost:
                hostKeyVerification = HostKeyVerificationState(
                    session: session, hostKey: sshHostKey, existingRecord: nil
                )
            case .mismatch(let old, _):
                hostKeyVerification = HostKeyVerificationState(
                    session: session, hostKey: sshHostKey, existingRecord: old
                )
            }
        } catch {
            await cleanupSessionIfNeeded()
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func handleHostKeyDecision(_ decision: HostKeyDecision, session: LibSSH2Session) async {
        switch decision {
        case .trustAlways(let hostKey):
            let knownHostsService = KnownHostsService(modelContext: modelContext)
            knownHostsService.trustHost(hostname: host.hostname, port: host.port, hostKey: hostKey)
            await proceedToAuth(session: session)
        case .trustOnce:
            await proceedToAuth(session: session)
        case .reject:
            await cleanupSessionIfNeeded()
            phase = .failed
            errorMessage = "Host key rejected"
        }
    }

    private func proceedToAuth(session: LibSSH2Session) async {
        phase = .authenticating

        do {
            if host.authMethod == .password {
                pendingPasswordSession = session
                passwordPrompt = true
                return
            }

            let vaultService = VaultService()
            let authGateService = AuthGateService()
            let authenticator = SSHAuthenticator(vaultService: vaultService, authGateService: authGateService)
            let credential = try await authenticator.resolveCredential(for: host, modelContext: modelContext)
            try await session.authenticate(credential: credential)
            await openSFTP(session: session)
        } catch {
            await cleanupSessionIfNeeded()
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func connectWithPassword() async {
        guard let session = pendingPasswordSession else {
            phase = .failed
            errorMessage = "Connection session expired. Please try again."
            return
        }
        passwordPrompt = false
        do {
            let credential = AuthCredential(username: host.username, method: .password(password))
            try await session.authenticate(credential: credential)
            pendingPasswordSession = nil
            await openSFTP(session: session)
        } catch {
            await cleanupSessionIfNeeded()
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func openSFTP(session: LibSSH2Session) async {
        phase = .openingSFTP
        do {
            let sftp = try await session.openSFTP()
            pendingPasswordSession = nil
            activeSession = nil
            didHandOff = true
            onConnected(session, sftp)
        } catch {
            await cleanupSessionIfNeeded()
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func cancelConnection() async {
        await cleanupSessionIfNeeded()
        dismiss()
    }

    private func cleanupSessionIfNeeded() async {
        pendingPasswordSession = nil
        guard !didHandOff, let session = activeSession else { return }
        activeSession = nil
        await session.disconnect()
    }
}

private enum SFTPConnectionPhase: Hashable {
    case connecting
    case verifyingHostKey
    case authenticating
    case openingSFTP
    case failed

    static let orderedPhases: [SFTPConnectionPhase] = [.connecting, .verifyingHostKey, .authenticating, .openingSFTP]
}

// MARK: - Reusable Password Prompt (shared with ConnectionSheet)

private struct PasswordPromptSheet: View {
    let username: String
    let hostname: String
    @Binding var password: String
    let onConnect: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Password Required") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button {
                        onConnect()
                    } label: {
                        Label("Connect", systemImage: "bolt.horizontal")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(password.isEmpty)
                } footer: {
                    Text("Enter the SSH password for \(username)@\(hostname).")
                }
            }
            .navigationTitle("Authenticate")
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
        .environment(URLSchemeHandler())
}
