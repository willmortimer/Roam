import SwiftUI
import SwiftData

@main
struct iDevApp: App {
    @AppStorage("appearance") private var appearance: AppAppearance = .system

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
            if hasCompletedOnboarding {
                MainTabView()
                    .overlay { BiometricGateOverlay() }
                    .preferredColorScheme(appearance.colorScheme)
            } else {
                OnboardingView()
                    .preferredColorScheme(appearance.colorScheme)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
