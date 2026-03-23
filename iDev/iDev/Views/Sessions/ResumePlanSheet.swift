import SwiftUI

/// Shows the helper's resume plan before executing workspace resume.
struct ResumePlanSheet: View {
    let plan: ResumePlanDTO
    let workspaceName: String
    let onProceed: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Tmux state
                Section("Tmux Session") {
                    HStack {
                        Image(systemName: plan.tmux_session_exists ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(plan.tmux_session_exists ? .green : .secondary)
                        Text(plan.tmux_session_exists ? "Session exists" : "No existing session")
                    }

                    if let target = plan.recommended_attach_target {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                            Text("Attach to: \(target)")
                                .font(.subheadline.monospaced())
                        }
                    }
                }

                // Detected servers
                if !plan.forward_candidates.isEmpty {
                    Section("Detected Servers (\(plan.forward_candidates.count))") {
                        ForEach(plan.forward_candidates, id: \.port) { candidate in
                            HStack {
                                Text(":\(candidate.port)")
                                    .font(.subheadline.monospacedDigit())
                                Text(candidate.process_name)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if let hint = candidate.framework_hint, !hint.isEmpty {
                                    Text(hint)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                // Recent artifacts
                if !plan.recent_artifacts.isEmpty {
                    Section("Recent Artifacts (\(plan.recent_artifacts.count))") {
                        ForEach(plan.recent_artifacts.prefix(5), id: \.self) { artifact in
                            Text(artifact)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if plan.recent_artifacts.count > 5 {
                            Text("and \(plan.recent_artifacts.count - 5) more...")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Resume Plan")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        onProceed()
                    } label: {
                        Text("Resume Workspace")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Skip Helper Features", action: onSkip)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.bar)
            }
        }
    }
}
