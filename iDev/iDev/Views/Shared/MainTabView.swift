import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showCommandPalette = false

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
                provider: DefaultPaletteActionProvider(navigateToTab: { tab in
                    selectedSection = AppSection(rawValue: tab)
                }),
                context: PaletteContext(hasActiveSession: false, hasHelper: false, repoPath: nil)
            )
        }
        .background {
            // Hidden buttons for hardware keyboard shortcuts
            Group {
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("") { selectedSection = .workspaces }
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
            Tab("Workspaces", systemImage: "square.stack.3d.up") {
                NavigationStack {
                    WorkspaceListView()
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

    @State private var selectedSection: AppSection? = .workspaces

    // MARK: - iPad (regular)

    @State private var detailPath = NavigationPath()

    private var sidebarNavigation: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
            }
            .navigationTitle("iDev")
        } detail: {
            if let section = selectedSection {
                NavigationStack(path: $detailPath) {
                    section.destination
                }
            } else {
                ContentUnavailableView("Select a section", systemImage: "sidebar.left")
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
    case workspaces
    case hosts
    case sessions
    case files
    case vault
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspaces: "Workspaces"
        case .hosts: "Hosts"
        case .sessions: "Sessions"
        case .files: "Files"
        case .vault: "Vault"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .workspaces: "square.stack.3d.up"
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
        case .workspaces: WorkspaceListView()
        case .hosts: HostListView()
        case .sessions: SessionListView()
        case .files: FileBrowserView(sftpChannel: nil)
        case .vault: VaultView()
        case .settings: SettingsView()
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [
            HostRecord.self,
            WorkspaceRecord.self,
            SnippetRecord.self,
        ], inMemory: true)
}
