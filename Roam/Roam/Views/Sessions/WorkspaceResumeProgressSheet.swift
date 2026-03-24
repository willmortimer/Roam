import SwiftUI

struct WorkspaceResumeProgressSheet: View {
    @Environment(WorkspaceResumeOrchestrator.self) private var resumeOrchestrator
    @Environment(\.dismiss) private var dismiss

    let workspaceName: String
    var onRetry: (() async -> Void)?

    private var phase: WorkspaceResumeOrchestrator.ResumePhase {
        resumeOrchestrator.phase
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Spacer()

                stepsIndicator

                Image(systemName: phaseIcon)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isFailed ? .Roam.danger : Color.accentColor)
                    .accessibilityHidden(true)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: Spacing.sm) {
                    Text(phaseTitle)
                        .font(.title3.bold())

                    Text(phaseSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xxl)
                }

                if isFailed {
                    VStack(spacing: Spacing.md) {
                        if onRetry != nil {
                            Button("Try Again") {
                                Task { await onRetry?() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Dismiss") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                } else if isReady {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.Roam.alive)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Resuming")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Step Dots

    /// Group the 12 orchestrator phases into 5 user-visible steps.
    private enum ResumeStep: Int, CaseIterable {
        case connect = 0
        case helper = 1
        case tmux = 2
        case forwards = 3
        case ready = 4

        var label: String {
            switch self {
            case .connect: "Connect"
            case .helper: "Helper"
            case .tmux: "Terminal"
            case .forwards: "Ports"
            case .ready: "Ready"
            }
        }
    }

    private var currentStepIndex: Int {
        switch phase {
        case .idle, .connecting: 0
        case .authenticating: 0
        case .detectingHelper, .installingHelper: 1
        case .fetchingResumePlan: 1
        case .resumingTmux, .assigningPaneRoles: 2
        case .openingForwards, .detectingPreviews: 3
        case .ready: 4
        case .failed: max(0, failedStepIndex)
        }
    }

    /// Track which step was active when failure occurred.
    private var failedStepIndex: Int {
        // Use current step index; failed doesn't advance past where it was
        4 // Show all dots as failed context
    }

    private var stepsIndicator: some View {
        HStack(spacing: Spacing.md) {
            ForEach(ResumeStep.allCases, id: \.rawValue) { step in
                VStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(stepColor(for: step))
                        .frame(width: 8, height: 8)
                        .scaleEffect(step.rawValue == currentStepIndex ? 1.3 : 1.0)
                        .animation(.spring(duration: 0.3), value: currentStepIndex)

                    Text(step.label)
                        .font(.system(size: 9))
                        .foregroundStyle(step.rawValue == currentStepIndex ? .primary : .secondary)
                }
            }
        }
        .padding(.bottom, Spacing.md)
    }

    private func stepColor(for step: ResumeStep) -> Color {
        if isFailed { return step.rawValue <= currentStepIndex ? .Roam.danger : .Roam.dormant }
        if step.rawValue < currentStepIndex { return .Roam.alive }
        if step.rawValue == currentStepIndex { return .accentColor }
        return .Roam.dormant
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private var isReady: Bool { phase == .ready }

    // MARK: - Phase Display

    private var phaseTitle: String {
        switch phase {
        case .idle: "Preparing"
        case .connecting: "Connecting"
        case .authenticating: "Authenticating"
        case .detectingHelper: "Checking Helper"
        case .installingHelper: "Installing Helper"
        case .fetchingResumePlan: "Planning Resume"
        case .resumingTmux: "Starting Terminal"
        case .assigningPaneRoles: "Detecting Panes"
        case .openingForwards: "Opening Ports"
        case .detectingPreviews: "Finding Previews"
        case .ready: "Ready"
        case .failed: "Resume Failed"
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case .idle:
            "Preparing to resume \(workspaceName)."
        case .connecting:
            "Reaching the remote host."
        case .authenticating:
            "Verifying your credentials."
        case .detectingHelper:
            "Checking if the helper is installed for workspace features."
        case .installingHelper:
            "Installing the helper. This only happens once per host."
        case .fetchingResumePlan:
            "Checking your tmux session and running processes."
        case .resumingTmux:
            "Attaching to your tmux session."
        case .assigningPaneRoles:
            "Matching panes to roles like tests, server, and logs."
        case .openingForwards:
            "Forwarding ports so you can access remote services locally."
        case .detectingPreviews:
            "Looking for dev servers to preview."
        case .ready:
            "\(workspaceName) is ready to use."
        case .failed(let message):
            friendlyError(message)
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .idle, .connecting: "network"
        case .authenticating: "person.badge.key"
        case .detectingHelper, .installingHelper: "shippingbox"
        case .fetchingResumePlan: "list.bullet.clipboard"
        case .resumingTmux: "rectangle.split.3x1"
        case .assigningPaneRoles: "square.grid.2x2"
        case .openingForwards: "arrow.left.arrow.right.circle"
        case .detectingPreviews: "eye"
        case .ready: "checkmark.circle"
        case .failed: "xmark.circle"
        }
    }

    // MARK: - Friendly Errors

    private func friendlyError(_ raw: String) -> String {
        let lower = raw.lowercased()

        if lower.contains("connection refused") || lower.contains("could not connect") || lower.contains("timed out") {
            return "Couldn't reach the host. Check that it's online and your network connection is working."
        }
        if lower.contains("host key") || lower.contains("handshake") {
            return "The host's identity couldn't be verified. This can happen if the host was reinstalled or its keys changed."
        }
        if lower.contains("auth") || lower.contains("password") || lower.contains("permission denied") {
            return "Authentication failed. Check your credentials or SSH key in the Vault."
        }
        if lower.contains("helper") || lower.contains("install") {
            return "The helper couldn't be installed. You can skip it and use basic SSH features."
        }
        if lower.contains("no longer exists") || lower.contains("host that no longer") {
            return "The host for this workspace was deleted. Edit the workspace to select a new host."
        }

        // Fallback: show raw but with context
        return "Something went wrong: \(raw)"
    }
}
