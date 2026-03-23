import SwiftUI

/// Sheet presented when the helper is missing or outdated on a remote host.
struct HelperInstallSheet: View {
    let detectionResult: HelperDetectionResult
    let onInstall: () async -> Void
    let onSkip: () -> Void

    @State private var isInstalling = false
    @State private var detectedArch: String?
    @State private var installError: String?
    @State private var installSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text(title)
                    .font(.title2.bold())

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                benefitsList

                if let detectedArch {
                    HStack {
                        Image(systemName: "cpu")
                        Text("Architecture: \(detectedArch)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let installError {
                    Label(installError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.iDev.danger)
                }

                if installSuccess {
                    Label("Helper installed successfully", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.iDev.alive)
                }

                Spacer()

                if !installSuccess {
                    VStack(spacing: 12) {
                        Button {
                            Task { await performInstall() }
                        } label: {
                            if isInstalling {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Installing...")
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text(installButtonTitle)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isInstalling)

                        Button("Skip", action: onSkip)
                            .foregroundStyle(.secondary)
                            .disabled(isInstalling)
                    }
                }
            }
            .padding()
            .navigationTitle("iDev Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onSkip)
                        .disabled(isInstalling)
                }
            }
        }
    }

    // MARK: - Computed

    private var title: String {
        switch detectionResult {
        case .notInstalled: "Install Helper?"
        case .outdated: "Update Helper?"
        case .error: "Helper Issue"
        case .installed: "Helper Installed"
        }
    }

    private var subtitle: String {
        switch detectionResult {
        case .notInstalled:
            "The iDev helper enables workspace-aware features like tmux pane roles, preview detection, and artifact browsing."
        case .outdated(let current, let required):
            "Version \(current) is installed but \(required) or later is required for full functionality."
        case .error(let msg):
            "Could not verify helper: \(msg)"
        case .installed(let version):
            "Version \(version) is installed and ready."
        }
    }

    private var installButtonTitle: String {
        switch detectionResult {
        case .outdated: "Update Helper"
        default: "Install Helper"
        }
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            benefitRow(icon: "rectangle.split.3x1", text: "Tmux pane roles and semantics")
            benefitRow(icon: "eye", text: "Auto-detect dev server previews")
            benefitRow(icon: "doc.richtext", text: "Recent build artifact browsing")
            benefitRow(icon: "clock.arrow.circlepath", text: "Command timeline tracking")
            benefitRow(icon: "arrow.triangle.branch", text: "Git status at a glance")
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Actions

    private func performInstall() async {
        isInstalling = true
        installError = nil

        await onInstall()

        isInstalling = false
        installSuccess = true
    }
}
