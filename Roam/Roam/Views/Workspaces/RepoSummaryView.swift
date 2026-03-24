import SwiftUI

/// Compact git status display for workspace headers.
struct RepoSummaryView: View {
    let helperClient: (any HelperClientProtocol)?
    let repoPath: String

    @State private var status: GitStatusDTO?
    @State private var isLoading = false
    @State private var refreshTask: Task<Void, Never>?

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
        .task {
            await refresh()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
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
                        .foregroundStyle(.Roam.alive)
                    }
                    if status.behind > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                            Text("\(status.behind)")
                        }
                        .foregroundStyle(.Roam.caution)
                    }
                }
                .font(.caption2.monospacedDigit())
            }

            Spacer()

            // Clean/dirty indicator
            if status.clean {
                Label("Clean", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.Roam.alive)
            } else {
                HStack(spacing: 6) {
                    if status.staged > 0 {
                        Text("S:\(status.staged)")
                            .foregroundStyle(.Roam.alive)
                    }
                    if status.modified > 0 {
                        Text("M:\(status.modified)")
                            .foregroundStyle(.Roam.caution)
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

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LowBandwidthService.shared.isEnabled ? 30 : 10))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }
}
