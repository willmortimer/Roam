import SwiftUI

/// Full-screen overlay that requires biometric auth when the app becomes active,
/// if the user has enabled "Require on App Launch" in biometric settings.
struct BiometricGateOverlay: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("biometric_requireOnLaunch") private var requireOnLaunch = false

    @State private var isLocked = false
    @State private var isAuthenticating = false

    var body: some View {
        Group {
            if isLocked {
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)

                        Text("iDev is Locked")
                            .font(.title2.bold())

                        Button("Unlock") {
                            Task { await authenticate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAuthenticating)
                        .accessibilityHint("Authenticate with Face ID or passcode to unlock the app.")
                    }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard requireOnLaunch else { return }
            switch newPhase {
            case .background:
                isLocked = true
            case .active:
                if isLocked && !isAuthenticating {
                    Task { await authenticate() }
                }
            default:
                break
            }
        }
        .onAppear {
            if requireOnLaunch {
                isLocked = true
                Task { await authenticate() }
            }
        }
    }

    private func authenticate() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let success = try await AuthGateService.shared.authenticate(
                reason: "Unlock iDev"
            )
            if success {
                withAnimation { isLocked = false }
            }
        } catch {
            // Auth failed or cancelled — stay locked
        }
    }
}
