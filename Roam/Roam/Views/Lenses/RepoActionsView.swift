import SwiftUI

/// Git operations UI: branch management, commit, push/pull, stash.
struct RepoActionsView: View {
    let helperClient: (any HelperClientProtocol)?
    let repoPath: String

    @State private var status: GitStatusDTO?
    @State private var branches: [GitBranchInfoDTO] = []
    @State private var stashEntries: [GitStashEntryDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCommitSheet = false
    @State private var branchSearch = ""
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?

    private var filteredBranches: [GitBranchInfoDTO] {
        if branchSearch.isEmpty { return branches }
        return branches.filter { $0.name.localizedCaseInsensitiveContains(branchSearch) }
    }

    var body: some View {
        Group {
            if helperClient == nil {
                ContentUnavailableView("Helper Required", systemImage: "shippingbox")
            } else if isLoading && status == nil {
                ProgressView("Loading repo...")
            } else {
                repoContent
            }
        }
        .navigationTitle("Repo")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Live", isOn: $autoRefresh)
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
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showCommitSheet) {
            CommitSheet(helperClient: helperClient, repoPath: repoPath) {
                await refresh()
            }
        }
    }

    // MARK: - Content

    private var repoContent: some View {
        List {
            // Status summary
            if let status {
                Section("Status") {
                    LabeledContent("Branch", value: status.branch)
                    if status.ahead > 0 || status.behind > 0 {
                        HStack {
                            if status.ahead > 0 {
                                Label("\(status.ahead) ahead", systemImage: "arrow.up")
                                    .foregroundStyle(.Roam.alive)
                            }
                            if status.behind > 0 {
                                Label("\(status.behind) behind", systemImage: "arrow.down")
                                    .foregroundStyle(.Roam.caution)
                            }
                        }
                        .font(.caption)
                    }
                    HStack(spacing: 12) {
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
                        if status.staged == 0 && status.modified == 0 && status.untracked == 0 {
                            Label("Clean", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.Roam.alive)
                        }
                    }
                    .font(.caption.monospacedDigit())
                }
            }

            // Quick actions
            Section("Actions") {
                if let s = status, s.staged > 0 {
                    Button {
                        showCommitSheet = true
                    } label: {
                        Label("Commit (\(s.staged) staged)", systemImage: "checkmark.square")
                    }
                }

                Button {
                    Task { await doPush() }
                } label: {
                    Label("Push", systemImage: "arrow.up.circle")
                }

                Button {
                    Task { await doPull() }
                } label: {
                    Label("Pull", systemImage: "arrow.down.circle")
                }
            }

            // Branches
            Section("Branches") {
                TextField("Search branches", text: $branchSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                ForEach(filteredBranches, id: \.name) { branch in
                    HStack {
                        if branch.is_current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.Roam.alive)
                                .font(.caption)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(branch.name)
                                .font(.subheadline)
                                .bold(branch.is_current)
                            if let upstream = branch.upstream, !upstream.isEmpty {
                                Text(upstream)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if branch.is_remote {
                            Text("remote")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !branch.is_current {
                            Task { await switchBranch(branch.name) }
                        }
                    }
                }
            }

            // Stash
            Section("Stash") {
                Button {
                    Task { await doStash() }
                } label: {
                    Label("Stash Changes", systemImage: "tray.and.arrow.down")
                }

                if stashEntries.isEmpty {
                    Text("No stashed changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stashEntries, id: \.index) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("stash@{\(entry.index)}")
                                    .font(.caption.monospaced().bold())
                                Text(entry.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Pop") {
                                Task { await doStashPop(entry.index) }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
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

        do {
            async let s = helper.gitStatus(repoPath: repoPath)
            async let b = helper.gitBranchList(repoPath: repoPath)
            async let st = helper.gitStashList(repoPath: repoPath)
            let (statusResult, branchResult, stashResult) = try await (s, b, st)
            status = statusResult
            branches = branchResult
            stashEntries = stashResult
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func switchBranch(_ name: String) async {
        guard let helper = helperClient else { return }
        do {
            try await helper.gitCheckout(repoPath: repoPath, ref: name, create: false)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func doPush() async {
        guard let helper = helperClient else { return }
        do {
            let result = try await helper.gitPush(repoPath: repoPath, setUpstream: false)
            if !result.ok {
                errorMessage = result.message
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func doPull() async {
        guard let helper = helperClient else { return }
        do {
            let result = try await helper.gitPull(repoPath: repoPath, rebase: false)
            if !result.ok {
                errorMessage = "Pull failed: \(result.message)"
                if !result.conflicts.isEmpty {
                    errorMessage! += "\nConflicts: \(result.conflicts.joined(separator: ", "))"
                }
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func doStash() async {
        guard let helper = helperClient else { return }
        do {
            try await helper.gitStash(repoPath: repoPath, message: nil)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func doStashPop(_ index: Int) async {
        guard let helper = helperClient else { return }
        do {
            try await helper.gitStashPop(repoPath: repoPath, index: index)
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

// MARK: - Commit Sheet

struct CommitSheet: View {
    let helperClient: (any HelperClientProtocol)?
    let repoPath: String
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var amend = false
    @State private var isCommitting = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Commit Message") {
                    TextField("Describe your changes...", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("Amend previous commit", isOn: $amend)
                }
                if let resultMessage {
                    Section {
                        Label(resultMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.Roam.alive)
                    }
                }
            }
            .navigationTitle("Commit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") {
                        Task { await doCommit() }
                    }
                    .disabled(message.isEmpty && !amend || isCommitting)
                }
            }
        }
    }

    private func doCommit() async {
        guard let helper = helperClient else { return }
        isCommitting = true
        do {
            let result = try await helper.gitCommit(repoPath: repoPath, message: message, amend: amend)
            resultMessage = "Committed \(result.hash)"
            await onComplete()
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            resultMessage = nil
            // Show error inline
        }
        isCommitting = false
    }
}
