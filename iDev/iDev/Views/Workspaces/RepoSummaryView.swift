import SwiftUI

/// Compact git status display for workspace headers.
struct RepoSummaryView: View {
    let helperClient: (any HelperClientProtocol)?
    let repoPath: String

    @State private var status: GitStatusDTO?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let status {
                statusContent(status)
            } else if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading git status...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                EmptyView()
            }
        }
        .task { await refresh() }
    }

    private func statusContent(_ status: GitStatusDTO) -> some View {
        HStack(spacing: 10) {
            // Branch name
            Label(status.branch, systemImage: "arrow.triangle.branch")
                .font(.caption.bold())

            // Ahead/behind
            if status.ahead > 0 || status.behind > 0 {
                HStack(spacing: 4) {
                    if status.ahead > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                            Text("\(status.ahead)")
                        }
                        .foregroundStyle(.iDev.alive)
                    }
                    if status.behind > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                            Text("\(status.behind)")
                        }
                        .foregroundStyle(.iDev.caution)
                    }
                }
                .font(.caption2.monospacedDigit())
            }

            Spacer()

            // Clean/dirty indicator
            if status.clean {
                Label("Clean", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.iDev.alive)
            } else {
                HStack(spacing: 6) {
                    if status.staged > 0 {
                        Text("S:\(status.staged)")
                            .foregroundStyle(.iDev.alive)
                    }
                    if status.modified > 0 {
                        Text("M:\(status.modified)")
                            .foregroundStyle(.iDev.caution)
                    }
                    if status.untracked > 0 {
                        Text("?:\(status.untracked)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2.monospacedDigit())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    func refresh() async {
        guard let helper = helperClient, !repoPath.isEmpty else { return }
        isLoading = true
        do {
            status = try await helper.gitStatus(repoPath: repoPath)
        } catch {
            // Non-fatal
        }
        isLoading = false
    }
}
