import Foundation
import Observation

/// Observable state tracked from terminal delegate callbacks and session metadata.
/// Shared between TerminalViewRepresentable coordinator and status bar views.
@Observable @MainActor
final class TerminalSessionState {
    // Terminal dimensions
    var columns: Int = 80
    var rows: Int = 24

    // CWD from OSC 7 / hostCurrentDirectoryUpdate
    var currentWorkingDirectory: String?

    // Terminal title from OSC 0/2
    var terminalTitle: String?

    // Git info (populated from helper)
    var gitBranch: String?
    var gitDirty: Bool = false
    var gitUncommittedCount: Int = 0

    // Data transfer tracking
    var bytesSent: UInt64 = 0
    var bytesReceived: UInt64 = 0

    // Connection timing
    var connectedAt: Date?

    // Latency (from periodic helper ping)
    var latencyMS: Int?

    /// Formatted uptime string.
    var uptimeString: String {
        guard let connectedAt else { return "--" }
        let elapsed = Date().timeIntervalSince(connectedAt)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        if elapsed < 3600 {
            let m = Int(elapsed) / 60
            let s = Int(elapsed) % 60
            return "\(m)m \(s)s"
        }
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        return "\(h)h \(m)m"
    }

    /// Short CWD — last path component or tilde-abbreviated.
    var shortCWD: String? {
        guard let cwd = currentWorkingDirectory, !cwd.isEmpty else { return nil }
        // Replace /home/<user> with ~
        let components = cwd.split(separator: "/")
        if components.count <= 2 { return cwd }
        return "~/" + components.suffix(2).joined(separator: "/")
    }

    /// Formatted terminal size.
    var sizeString: String {
        "\(columns)×\(rows)"
    }

    /// Formatted bytes transferred.
    var transferSummary: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        let sent = formatter.string(fromByteCount: Int64(bytesSent))
        let recv = formatter.string(fromByteCount: Int64(bytesReceived))
        return "↑\(sent) ↓\(recv)"
    }

    func recordSent(bytes: Int) {
        bytesSent += UInt64(bytes)
    }

    func recordReceived(bytes: Int) {
        bytesReceived += UInt64(bytes)
    }
}
