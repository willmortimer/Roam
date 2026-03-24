import SwiftUI

/// Sheet presented when the helper is missing or outdated on a remote host.
struct HelperInstallSheet: View {
    let detectionResult: HelperDetectionResult
    let onInstall: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Image(systemName: "shippingbox")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.bold())

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                benefitsList

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onInstall) {
                        Text(installButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip", action: onSkip)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Roam Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onSkip)
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
            "The Roam helper enables workspace-aware features like tmux pane roles, preview detection, and artifact browsing."
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
}
