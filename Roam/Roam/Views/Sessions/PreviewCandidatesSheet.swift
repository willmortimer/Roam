import SwiftUI

/// Shows detected dev servers with one-tap forward + preview creation.
struct PreviewCandidatesSheet: View {
    let candidates: [PreviewCandidateDTO]
    let onForwardAndPreview: (PreviewCandidateDTO) async -> Void
    let onDismiss: () -> Void

    @State private var forwardingPort: Int?

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Dev Servers Detected",
                        systemImage: "network.slash",
                        description: Text("Start a dev server in your workspace and it will appear here.")
                    )
                } else {
                    List(candidates, id: \.port) { candidate in
                        CandidateRow(
                            candidate: candidate,
                            isForwarding: forwardingPort == candidate.port,
                            onForward: {
                                forwardingPort = candidate.port
                                Task {
                                    await onForwardAndPreview(candidate)
                                    forwardingPort = nil
                                }
                            }
                        )
                    }
                }
            }
            .navigationTitle("Preview Candidates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}

// MARK: - Candidate Row

private struct CandidateRow: View {
    let candidate: PreviewCandidateDTO
    let isForwarding: Bool
    let onForward: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(":\(candidate.port)")
                        .font(.headline.monospacedDigit())

                    if let hint = candidate.framework_hint, !hint.isEmpty {
                        Text(hint)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }

                HStack(spacing: 4) {
                    Text(candidate.process_label ?? candidate.process_name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let health = candidate.health_hint {
                        Text(health)
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(healthColor(health).opacity(0.15), in: Capsule())
                            .foregroundStyle(healthColor(health))
                    }

                    if let elapsed = candidate.startup_elapsed_secs {
                        Text(formatElapsed(elapsed))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if let cwd = candidate.cwd, !cwd.isEmpty {
                    Text(cwd)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            Button {
                onForward()
            } label: {
                if isForwarding {
                    ProgressView()
                } else {
                    Label("Preview", systemImage: "eye")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isForwarding)
        }
        .padding(.vertical, 4)
    }

    private func healthColor(_ hint: String) -> Color {
        switch hint {
        case "ready": .Roam.alive
        case "unhealthy": .Roam.danger
        default: .Roam.caution
        }
    }

    private func formatElapsed(_ secs: Int) -> String {
        if secs < 60 { return "\(secs)s" }
        if secs < 3600 { return "\(secs / 60)m" }
        return "\(secs / 3600)h"
    }
}
