import SwiftUI

/// Structured view of git diff with staged/unstaged sections and stage/unstage actions.
struct DiffLensView: View {
    let helperClient: (any HelperClientProtocol)?
    let repoPath: String

    @State private var gitStatus: GitStatusDTO?
    @State private var diffSummary: GitDiffSummaryDTO?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?

    private var stagedFiles: [GitStatusFileDTO] {
        gitStatus?.files?.filter(\.isStaged) ?? []
    }

    private var unstagedFiles: [GitStatusFileDTO] {
        gitStatus?.files?.filter { $0.isModified || $0.isUntracked } ?? []
    }

    var body: some View {
        Group {
            if helperClient == nil {
                ContentUnavailableView("Helper Required", systemImage: "shippingbox")
            } else if isLoading && gitStatus == nil {
                ProgressView("Loading diff...")
            } else if let status = gitStatus, !(status.files ?? []).isEmpty {
                diffContent
            } else if let errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("Working tree is clean."))
            }
        }
        .navigationTitle("Diff")
        .toolbar {
            if helperClient != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !unstagedFiles.isEmpty {
                        Button("Stage All") {
                            Task { await stageAll() }
                        }
                    }
                    if !stagedFiles.isEmpty {
                        Button("Unstage All") {
                            Task { await unstageAll() }
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Toggle("Live", isOn: $autoRefresh)
                }
            }
        }
        .task {
            await refresh()
            updateRefreshLoop()
        }
        .refreshable { await refresh() }
        .onChange(of: autoRefresh) { _, _ in
            updateRefreshLoop()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    // MARK: - Content

    private var diffContent: some View {
        List {
            // Summary stats
            if let diff = diffSummary, diff.files_changed > 0 {
                Section {
                    HStack {
                        StatBadge(label: "Files", value: "\(diff.files_changed)", color: .primary)
                        Spacer()
                        StatBadge(label: "Insertions", value: "+\(diff.insertions)", color: .Roam.alive)
                        Spacer()
                        StatBadge(label: "Deletions", value: "-\(diff.deletions)", color: .Roam.danger)
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(diff.files_changed) files changed, \(diff.insertions) insertions, \(diff.deletions) deletions")
                }
            }

            // Staged section
            if !stagedFiles.isEmpty {
                Section("Staged (\(stagedFiles.count))") {
                    ForEach(stagedFiles, id: \.path) { file in
                        FileStatusRow(file: file, section: .staged)
                            .swipeActions(edge: .trailing) {
                                Button("Unstage") {
                                    Task { await unstageFile(file.path) }
                                }
                                .tint(.Roam.caution)
                            }
                    }
                }
            }

            // Unstaged section
            if !unstagedFiles.isEmpty {
                Section("Unstaged (\(unstagedFiles.count))") {
                    ForEach(unstagedFiles, id: \.path) { file in
                        FileStatusRow(file: file, section: .unstaged)
                            .swipeActions(edge: .trailing) {
                                Button("Stage") {
                                    Task { await stageFile(file.path) }
                                }
                                .tint(.Roam.alive)
                            }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() async {
        guard let helper = helperClient, !repoPath.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        do {
            async let statusResult = helper.gitStatus(repoPath: repoPath)
            async let diffResult = helper.gitDiffSummary(repoPath: repoPath)
            let (status, diff) = try await (statusResult, diffResult)
            gitStatus = status
            diffSummary = diff.files_changed > 0 ? diff : nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func stageFile(_ path: String) async {
        guard let helper = helperClient else { return }
        do {
            try await helper.gitStage(repoPath: repoPath, paths: [path])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unstageFile(_ path: String) async {
        guard let helper = helperClient else { return }
        do {
            try await helper.gitUnstage(repoPath: repoPath, paths: [path])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stageAll() async {
        guard let helper = helperClient else { return }
        let paths = unstagedFiles.map(\.path)
        guard !paths.isEmpty else { return }
        do {
            try await helper.gitStage(repoPath: repoPath, paths: paths)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unstageAll() async {
        guard let helper = helperClient else { return }
        let paths = stagedFiles.map(\.path)
        guard !paths.isEmpty else { return }
        do {
            try await helper.gitUnstage(repoPath: repoPath, paths: paths)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil

        guard autoRefresh, helperClient != nil, !repoPath.isEmpty else { return }

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LowBandwidthService.shared.isEnabled ? 30 : 8))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }
}

// MARK: - File Section

private enum FileSection {
    case staged, unstaged
}

// MARK: - File Status Row

private struct FileStatusRow: View {
    let file: GitStatusFileDTO
    let section: FileSection

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(file.path)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)

            Spacer()

            Text(statusLabel)
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(statusLabel): \(file.path)")
    }

    private var statusLabel: String {
        let code = section == .staged ? file.index_status : file.worktree_status
        switch code {
        case "M": return "Modified"
        case "A": return "Added"
        case "D": return "Deleted"
        case "R": return "Renamed"
        case "C": return "Copied"
        case "?": return "Untracked"
        case "U": return "Conflict"
        default: return code
        }
    }

    private var icon: String {
        let code = section == .staged ? file.index_status : file.worktree_status
        switch code {
        case "M": return "pencil.circle"
        case "A": return "plus.circle"
        case "D": return "minus.circle"
        case "R": return "arrow.right.circle"
        case "?": return "questionmark.circle"
        case "U": return "exclamationmark.triangle"
        default: return "circle"
        }
    }

    private var color: Color {
        let code = section == .staged ? file.index_status : file.worktree_status
        switch code {
        case "M": return .Roam.caution
        case "A": return .Roam.alive
        case "D": return .Roam.danger
        case "?": return .secondary
        case "U": return .purple
        default: return .secondary
        }
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
