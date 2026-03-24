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
    @State private var showSplash = true
    private let urlSchemeHandler = URLSchemeHandler()

    var body: some Scene {
        WindowGroup {
            ZStack {
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

                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .preferredColorScheme(appearance.colorScheme)
                    .zIndex(1)
                }
            }
            .onOpenURL { url in
                urlSchemeHandler.handle(url: url)
            }
        }
        .modelContainer(sharedModelContainer)
        .environment(sessionManager)
        .environment(workspaceResumeOrchestrator)
        .environment(urlSchemeHandler)
    }
}
