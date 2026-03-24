import SwiftUI
import Combine

/// Compact status bar displayed below the terminal, showing dimensions, uptime, CWD, and git branch.
struct TerminalStatusBar: View {
    let session: ManagedSession
    let sessionState: TerminalSessionState
    let onTap: () -> Void

    @State private var uptimeText = "--"
    private let uptimeTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                // Connection quality dot
                ConnectionDot(state: session.connectionLiveness)

                // Terminal size
                Text(sessionState.sizeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                divider

                // Uptime
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(uptimeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                // CWD
                if let cwd = sessionState.shortCWD {
                    divider

                    Image(systemName: "folder")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(cwd)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                // Git branch
                if let branch = sessionState.gitBranch {
                    divider

                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundStyle(sessionState.gitDirty ? .Roam.caution : .Roam.alive)
                    Text(branch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(sessionState.gitDirty ? .Roam.caution : .secondary)
                        .lineLimit(1)

                    if sessionState.gitDirty && sessionState.gitUncommittedCount > 0 {
                        Text("+\(sessionState.gitUncommittedCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.Roam.caution)
                    }
                }

                Spacer()

                // Transfer summary
                Text(sessionState.transferSummary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground))
        }
        .buttonStyle(.plain)
        .onReceive(uptimeTimer) { _ in
            uptimeText = sessionState.uptimeString
        }
        .onAppear {
            uptimeText = sessionState.uptimeString
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 12)
    }
}
