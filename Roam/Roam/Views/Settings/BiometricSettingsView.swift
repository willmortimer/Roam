import SwiftUI
import LocalAuthentication

/// Settings for Face ID / Touch ID / PIN protection.
struct BiometricSettingsView: View {
    private let authGate = AuthGateService.shared

    @AppStorage("biometric_requireOnLaunch") private var requireOnLaunch = false
    @AppStorage("biometric_requireForKeys") private var requireForKeys = true
    @AppStorage("biometric_autoLockTimeout") private var autoLockTimeout = 0 // 0 = immediate

    @State private var biometryType: LABiometryType = .none
    @State private var biometricsAvailable = false
    @State private var testResult: TestResult?
    @State private var isSimulator = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: biometryIcon)
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .frame(width: 50)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(biometryName)
                            .font(.headline)
                        Text(biometricsAvailable ? "Available on this device" : "Not available — device passcode will be used")
                            .font(.caption)
                            .foregroundStyle(biometricsAvailable ? .Roam.alive : .secondary)
                        if isSimulator {
                            Text("Simulator mode uses a bypass when device authentication is unavailable.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Section {
                Toggle("Require on App Launch", isOn: $requireOnLaunch)

                if requireOnLaunch {
                    Picker("Auto-Lock After", selection: $autoLockTimeout) {
                        Text("Immediately").tag(0)
                        Text("1 minute").tag(60)
                        Text("5 minutes").tag(300)
                        Text("15 minutes").tag(900)
                    }

                    Text("The app will lock when backgrounded for longer than this duration. Authentication uses \(biometricsAvailable ? biometryName : "device passcode").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("App Protection")
            } footer: {
                if !requireOnLaunch {
                    Text("When enabled, the entire app is gated behind \(biometricsAvailable ? biometryName : "your device passcode") each time you open it.")
                        .font(.caption)
                }
            }

            Section {
                Toggle("Require for SSH Key Access", isOn: $requireForKeys)
                    .disabled(isSimulator)

                Text(isSimulator
                     ? "Simulator does not reliably support Secure Enclave-backed key prompts, so SSH key access protection is bypassed here."
                     : "SSH private keys in the vault require authentication before use. Keys are protected at the Keychain level with Secure Enclave backing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Key Access")
            }

            Section {
                Button {
                    Task { await testAuth() }
                } label: {
                    HStack {
                        Label("Test Authentication", systemImage: "checkmark.shield")
                        Spacer()
                        if let result = testResult {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.success ? .Roam.alive : .Roam.danger)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .navigationTitle("Security")
        .animation(.snappy(duration: 0.25), value: requireOnLaunch)
        .animation(.snappy(duration: 0.25), value: testResult?.success)
        .onAppear {
            isSimulator = authGate.isRunningInSimulator
            biometryType = authGate.biometricType
            biometricsAvailable = authGate.isBiometricsAvailable()
            if isSimulator {
                requireForKeys = false
            }
        }
    }

    // MARK: - Helpers

    private var biometryIcon: String {
        switch biometryType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "lock.shield"
        }
    }

    private var biometryName: String {
        switch biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Device Passcode"
        }
    }

    private func testAuth() async {
        do {
            let success = try await authGate.authenticate(reason: "Test authentication")
            testResult = TestResult(success: success)
        } catch {
            testResult = TestResult(success: false)
        }
    }

    private struct TestResult {
        let success: Bool
    }
}
