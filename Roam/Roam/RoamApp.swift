import SwiftUI
import SwiftData

@main
struct RoamApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system
    private let sessionManager: SessionManager
    private let workspaceResumeOrchestrator: WorkspaceResumeOrchestrator

    init() {
        TerminalFontCatalog.registerBundledFontsIfNeeded()

        let sessionManager = SessionManager()
        self.sessionManager = sessionManager
        self.workspaceResumeOrchestrator = WorkspaceResumeOrchestrator(
            sessionManager: sessionManager,
            vaultService: VaultService.shared,
            authGateService: AuthGateService.shared
        )
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            HostRecord.self,
            SSHKeyRecord.self,
            WorkspaceRecord.self,
            SnippetRecord.self,
            KnownHostRecord.self,
            TunnelRecord.self,
            PreviewRecord.self,
            CommandRecord.self,
            FavoriteArtifactRecord.self,
            TeamVaultRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                        .overlay { BiometricGateOverlay() }
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(appearance.colorScheme)
            .background {
                SessionLifecycleObserver()
            }
        }
        .modelContainer(sharedModelContainer)
        .environment(sessionManager)
        .environment(workspaceResumeOrchestrator)
    }
}
