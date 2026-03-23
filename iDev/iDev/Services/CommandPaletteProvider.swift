import Foundation

/// Provides actions for the command palette.
protocol CommandPaletteActionProvider {
    func actions(context: PaletteContext) -> [PaletteAction]
}

/// Context describing the current app state for action filtering.
struct PaletteContext {
    var hasActiveSession: Bool
    var hasHelper: Bool
    var repoPath: String?
    var hasSFTP: Bool = false
    var hasActivePreview: Bool = false
    var hasTeamVault: Bool = false
}

/// A single action in the command palette.
struct PaletteAction: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var icon: String
    var shortcut: String?
    var action: @MainActor () -> Void
}

/// Performs fuzzy matching against a query string.
nonisolated enum FuzzyMatcher {
    /// Returns a score >= 0 if the query fuzzy-matches the target.
    /// Higher score = better match. Returns nil if no match.
    static func score(query: String, target: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        let queryChars = Array(query.lowercased())
        let targetChars = Array(target.lowercased())

        var queryIndex = 0
        var score = 0
        var prevMatchIndex = -2

        for (targetIndex, char) in targetChars.enumerated() {
            guard queryIndex < queryChars.count else { break }

            if char == queryChars[queryIndex] {
                score += 1
                // Bonus for consecutive matches
                if targetIndex == prevMatchIndex + 1 {
                    score += 2
                }
                // Bonus for matching at word boundaries
                if targetIndex == 0 || targetChars[targetIndex - 1] == " " || targetChars[targetIndex - 1] == "." {
                    score += 3
                }
                prevMatchIndex = targetIndex
                queryIndex += 1
            }
        }

        // All query chars must match
        return queryIndex == queryChars.count ? score : nil
    }
}

/// Default provider that supplies navigation and common actions.
struct DefaultPaletteActionProvider: CommandPaletteActionProvider {
    var navigateToTab: (@MainActor (String) -> Void)?
    var onSharePreview: (@MainActor () -> Void)?
    var onParseTestReport: (@MainActor () -> Void)?

    func actions(context: PaletteContext) -> [PaletteAction] {
        var result: [PaletteAction] = []

        // Navigation
        let tabs = [
            ("workspaces", "Workspaces", "square.stack.3d.up", "⌘1"),
            ("hosts", "Hosts", "server.rack", "⌘2"),
            ("sessions", "Sessions", "terminal", "⌘3"),
            ("files", "Files", "folder", "⌘4"),
            ("vault", "Vault", "lock.shield", "⌘5"),
            ("settings", "Settings", "gear", "⌘6"),
        ]

        for (id, title, icon, shortcut) in tabs {
            let tabID = id
            result.append(PaletteAction(
                id: "nav.\(id)",
                title: "Go to \(title)",
                subtitle: nil,
                icon: icon,
                shortcut: shortcut,
                action: { [navigateToTab] in navigateToTab?(tabID) }
            ))
        }

        // Session actions
        if context.hasActiveSession {
            if context.hasHelper {
                result.append(PaletteAction(
                    id: "lens.diffs", title: "Show Diffs", subtitle: "Git diff view",
                    icon: "plus.forwardslash.minus", shortcut: "⇧⌘D", action: {}
                ))
                result.append(PaletteAction(
                    id: "lens.tests", title: "Show Tests", subtitle: "Test results",
                    icon: "checkmark.circle", shortcut: "⇧⌘T", action: {}
                ))
                result.append(PaletteAction(
                    id: "lens.logs", title: "Show Logs", subtitle: "Server logs",
                    icon: "doc.text", shortcut: "⇧⌘L", action: {}
                ))
            }

            if context.repoPath != nil && context.hasHelper {
                result.append(PaletteAction(
                    id: "git.commit", title: "Commit Changes", subtitle: "Stage and commit",
                    icon: "checkmark.square", shortcut: nil, action: {}
                ))
                result.append(PaletteAction(
                    id: "git.push", title: "Push", subtitle: "Push to remote",
                    icon: "arrow.up.circle", shortcut: nil, action: {}
                ))
                result.append(PaletteAction(
                    id: "git.pull", title: "Pull", subtitle: "Pull from remote",
                    icon: "arrow.down.circle", shortcut: nil, action: {}
                ))
            }

            // Phase 4: Preview sharing
            if context.hasActivePreview && context.hasHelper {
                result.append(PaletteAction(
                    id: "preview.share", title: "Share Preview Publicly",
                    subtitle: "Create a public tunnel",
                    icon: "square.and.arrow.up", shortcut: nil,
                    action: { [onSharePreview] in onSharePreview?() }
                ))
            }

            // Phase 4: Test report parsing
            if context.hasHelper {
                result.append(PaletteAction(
                    id: "testing.parse", title: "Parse Test Report",
                    subtitle: "JUnit, Jest, pytest, Go test",
                    icon: "checkmark.circle.badge.questionmark", shortcut: nil,
                    action: { [onParseTestReport] in onParseTestReport?() }
                ))
            }
        }

        // Phase 4: File editor (available when SFTP is connected)
        if context.hasSFTP {
            result.append(PaletteAction(
                id: "editor.open", title: "Open File in Editor",
                subtitle: "Lightweight text editor",
                icon: "doc.text", shortcut: nil,
                action: { [navigateToTab] in navigateToTab?("files") }
            ))
        }

        // Phase 4: Team vault sync
        if context.hasTeamVault {
            result.append(PaletteAction(
                id: "vault.sync", title: "Sync Team Vault",
                subtitle: "Push or pull team data",
                icon: "person.3", shortcut: nil,
                action: { [navigateToTab] in navigateToTab?("settings") }
            ))
        }

        return result
    }
}
