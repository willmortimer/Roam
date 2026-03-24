import SwiftUI

struct SessionLifecycleObserver: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(WorkspaceResumeOrchestrator.self) private var resumeOrchestrator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasBootstrapped = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                guard !hasBootstrapped else { return }
                hasBootstrapped = true
                await sessionManager.restoreSessionsIfNeeded(
                    modelContext: modelContext,
                    resumeOrchestrator: resumeOrchestrator
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    sessionManager.prepareForSuspension()
                case .active:
                    Task {
                        await sessionManager.restoreSessionsIfNeeded(
                            modelContext: modelContext,
                            resumeOrchestrator: resumeOrchestrator
                        )
                    }
                default:
                    break
                }
            }
    }
}
