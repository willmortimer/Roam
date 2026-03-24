import SwiftUI

/// Full-screen overlay that requires biometric auth when the app becomes active,
/// if the user has enabled "Require on App Launch" in biometric settings.
struct BiometricGateOverlay: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("biometric_requireOnLaunch") private var requireOnLaunch = false
    @AppStorage("biometric_autoLockTimeout") private var autoLockTimeout = 0

    @State private var isLocked = false
    @State private var isAuthenticating = false
    @State private var backgroundedAt: Date?

    var body: some View {
        Group {
            if isLocked {
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: Spacing.xl) {
                        Image(systemName: "lock.shield.fill")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)

                        Text("Roam is Locked")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)

                        Button("Unlock") {
                            Task { await authenticate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAuthenticating)
                        .accessibilityHint("Authenticate with Face ID or passcode to unlock the app.")
                    }
                }
                .transition(.opacity)
                .accessibilityElement(children: .contain)
            }
        }
        .animation(.snappy(duration: 0.25), value: isLocked)
        .onChange(of: scenePhase) { _, newPhase in
            guard requireOnLaunch else { return }
            switch newPhase {
            case .background, .inactive:
                backgroundedAt = backgroundedAt ?? .now
            case .active:
                if let departed = backgroundedAt {
                    let elapsed = Date.now.timeIntervalSince(departed)
                    backgroundedAt = nil
                    if elapsed >= Double(autoLockTimeout) {
                        isLocked = true
                        Task { await authenticate() }
                    }
                }
            @unknown default:
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
                reason: "Unlock Roam"
            )
            if success {
                withAnimation { isLocked = false }
            }
        } catch {
            // Auth failed or cancelled — stay locked
        }
    }
}
