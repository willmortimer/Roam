import SwiftUI

struct WorkspaceSessionCockpitView: View {
    let session: ManagedSession
    let workspace: WorkspaceRecord

    @State private var panes: [TmuxPaneDTO] = []
    @State private var activeForwards: [ActiveForward] = []
    @State private var previewCandidateService = PreviewCandidateService()
    @State private var selectedLens: Lens = .diffs
    @State private var selectedPreview: WorkspacePreviewDestination?
    @State private var showingLensSheet = false
    @State private var showingPaneSheet = false
    @State private var showingPreviewCandidates = false
    @State private var paneRefreshTask: Task<Void, Never>?
    @State private var didBootstrap = false
    @State private var didAutoPresentPreviewDiscovery = false
    @State private var autoSurfacedPreviewRemotePort: Int?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header

            if session.isHelperAvailable {
                if !workspace.repoPath.isEmpty {
                    RepoSummaryView(helperClient: session.helperClient, repoPath: workspace.repoPath)
                }

                quickActions

                if !roleSummaries.isEmpty {
                    roleStrip
                }

                if !activePreviewForwards.isEmpty || !mergedPreviewCandidates.isEmpty {
                    previewStrip
                }
            } else {
                Text("Install the helper to unlock live repo state, pane roles, and previews for this workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
        .background(.bar)
        .task {
            await bootstrapIfNeeded()
        }
        .onChange(of: activeForwardSignature) { _, _ in
            syncForwardedPorts()
            attemptAutoSurfacePreview()
        }
        .onChange(of: previewCandidateSignature) { _, _ in
            attemptAutoSurfacePreview()
        }
        .onDisappear {
            previewCandidateService.stopPolling()
            paneRefreshTask?.cancel()
            paneRefreshTask = nil
            didBootstrap = false
        }
        .alert("Workspace Cockpit", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingLensSheet) {
            NavigationStack {
                LensSwitcherView(
                    helperClient: session.helperClient,
                    repoPath: workspace.repoPath,
                    tmuxSession: workspace.tmuxSessionName,
                    paneIDs: panes.map(\.pane_id),
                    testPaneID: testPaneID,
                    logPaneIDs: logPaneIDs,
                    activeForwards: activeForwards,
                    onForwardAndPreview: { candidate in
                        Task { await forwardAndPreview(candidate) }
                    },
                    initialLens: selectedLens
                )
            }
        }
        .sheet(isPresented: $showingPaneSheet) {
            NavigationStack {
                PaneListView(
                    panes: panes,
                    paneDefinitions: workspace.tmuxPanes,
                    onRoleChanged: { paneID, role in
                        updateRole(for: paneID, to: role)
                    },
                    onSendKeys: { paneID, command in
                        await sendCommand(command, to: paneID)
                    },
                    onCapturePane: { paneID in
                        await capturePane(paneID: paneID)
                    },
                    onOpenLens: { lens in
                        showingPaneSheet = false
                        openLens(lens)
                    }
                )
            }
        }
        .sheet(isPresented: $showingPreviewCandidates) {
            PreviewCandidatesSheet(
                candidates: mergedPreviewCandidates,
                onForwardAndPreview: { candidate in
                    await forwardAndPreview(candidate)
                },
                onDismiss: {
                    showingPreviewCandidates = false
                }
            )
        }
        .fullScreenCover(item: $selectedPreview) { preview in
            NavigationStack {
                PreviewView(
                    localPort: preview.localPort,
                    displayName: preview.displayName,
                    scheme: preview.scheme,
                    helperClient: session.helperClient
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(workspace.name)
                    .font(.subheadline.bold())

                if !workspace.repoPath.isEmpty {
                    Text(workspace.repoPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            if session.isHelperAvailable {
                Text("Live")
                    .codeBadge(color: .Roam.alive)
            }

            if !panes.isEmpty {
                Text("\(panes.count) panes")
                    .codeBadge(color: .Roam.dormant)
            }
        }
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                cockpitAction("Repo", systemImage: "arrow.triangle.branch") {
                    openLens(.repo)
                }

                cockpitAction("Diffs", systemImage: "plus.forwardslash.minus") {
                    openLens(.diffs)
                }

                if testPaneID != nil {
                    cockpitAction("Tests", systemImage: "checkmark.circle") {
                        openLens(.tests)
                    }
                }

                if !logPaneIDs.isEmpty {
                    cockpitAction("Logs", systemImage: "doc.text") {
                        openLens(.logs)
                    }
                }

                if !activePreviewForwards.isEmpty || !mergedPreviewCandidates.isEmpty {
                    cockpitAction("Ports", systemImage: "network") {
                        openLens(.ports)
                    }
                }

                cockpitAction("Panes", systemImage: "rectangle.split.3x1") {
                    showingPaneSheet = true
                }
            }
        }
    }

    private var roleStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(roleSummaries, id: \.role) { summary in
                    HStack(spacing: Spacing.xs) {
                        RoleBadge(role: summary.role)
                        Text("\(summary.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var previewStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Label("Previews", systemImage: "eye")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if !mergedPreviewCandidates.isEmpty {
                    Button {
                        showingPreviewCandidates = true
                    } label: {
                        Text("\(mergedPreviewCandidates.count) detected")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(activePreviewForwards) { forward in
                        previewCard(for: forward)
                    }

                    if activePreviewForwards.isEmpty, !mergedPreviewCandidates.isEmpty {
                        Button {
                            showingPreviewCandidates = true
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Open a detected server")
                                    .font(.caption.bold())
                                Text("Forward and preview the current workspace without leaving the session.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(width: 220, alignment: .leading)
                            .padding(Spacing.md)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func previewCard(for forward: ActiveForward) -> some View {
        Button {
            Task {
                await openPreview(for: forward)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(previewDisplayName(for: forward))
                    .font(.caption.bold())
                    .lineLimit(1)

                Text("127.0.0.1:\(forward.resolvedLocalPort)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text("remote :\(forward.remotePort)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 180, alignment: .leading)
            .padding(Spacing.md)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func cockpitAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.fill.tertiary, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var roleSummaries: [(role: PaneRole, count: Int)] {
        let grouped = Dictionary(grouping: panes.compactMap { pane -> PaneRole? in
            roleForPane(pane)
        }, by: { $0 })

        return grouped
            .map { (role: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                lensSortOrder(for: lhs.role) < lensSortOrder(for: rhs.role)
            }
    }

    private var testPaneID: String? {
        panes.first { roleForPane($0) == .tests }?.pane_id
    }

    private var logPaneIDs: [String] {
        panes.compactMap { pane in
            guard let role = roleForPane(pane), role == .logs || role == .server else {
                return nil
            }

            return pane.pane_id
        }
    }

    private var mergedPreviewCandidates: [PreviewCandidateDTO] {
        var byPort: [Int: PreviewCandidateDTO] = [:]

        for candidate in session.resumePlan?.forward_candidates ?? [] {
            byPort[candidate.port] = candidate
        }

        for candidate in previewCandidateService.newCandidates {
            byPort[candidate.port] = candidate
        }

        let forwardedPorts = Set(activeForwards.map(\.remotePort))
        return byPort.values
            .filter { !forwardedPorts.contains($0.port) }
            .sorted { $0.port < $1.port }
    }

    private var activePreviewForwards: [ActiveForward] {
        activeForwards.filter(isLikelyPreviewForward)
    }

    private var activeForwardSignature: String {
        activeForwards
            .sorted { lhs, rhs in lhs.remotePort < rhs.remotePort }
            .map { "\($0.remotePort):\($0.resolvedLocalPort)" }
            .joined(separator: ",")
    }

    private var previewCandidateSignature: String {
        mergedPreviewCandidates
            .map(\.port)
            .sorted()
            .map(String.init)
            .joined(separator: ",")
    }

    private func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        panes = session.tmuxPanes
        refreshActiveForwards()
        syncForwardedPorts()

        if let helper = session.helperClient, session.isHelperAvailable {
            previewCandidateService.startPolling(
                helperClient: helper,
                workspacePath: workspace.repoPath.isEmpty ? nil : workspace.repoPath,
                interval: LowBandwidthService.shared.isEnabled ? 45 : 12
            )
            await refreshPanes()
            startPaneRefreshLoop()
        }

        attemptAutoSurfacePreview()
    }

    private func startPaneRefreshLoop() {
        paneRefreshTask?.cancel()
        paneRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LowBandwidthService.shared.isEnabled ? 30 : 10))
                guard !Task.isCancelled else { break }
                await refreshPanes()
            }
        }
    }

    private func refreshPanes() async {
        refreshActiveForwards()

        guard let helper = session.helperClient,
              session.isHelperAvailable,
              !workspace.tmuxSessionName.isEmpty else {
            return
        }

        do {
            let fetchedPanes = try await helper.listTmuxPanes(session: workspace.tmuxSessionName)
            panes = fetchedPanes
            session.tmuxPanes = fetchedPanes
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshActiveForwards() {
        activeForwards = session.forwardService?.activeForwards ?? []
    }

    private func syncForwardedPorts() {
        for forward in activeForwards {
            previewCandidateService.markForwarded(port: forward.remotePort)
        }
    }

    private func openLens(_ lens: Lens) {
        selectedLens = lens
        showingLensSheet = true
    }

    private func roleForPane(_ pane: TmuxPaneDTO) -> PaneRole? {
        workspace.tmuxPanes.first { $0.window == pane.window }?.role
    }

    private func updateRole(for paneID: String, to role: PaneRole?) {
        guard let pane = panes.first(where: { $0.pane_id == paneID }) else { return }

        var updatedDefinitions = workspace.tmuxPanes.filter { $0.window != pane.window }
        if let role {
            updatedDefinitions.append(PaneDefinition(role: role, window: pane.window))
        }

        workspace.tmuxPanes = updatedDefinitions
    }

    private func sendCommand(_ command: String, to paneID: String) async {
        guard let helper = session.helperClient else { return }

        do {
            try await helper.sendKeys(session: workspace.tmuxSessionName, paneID: paneID, keys: command + " Enter")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func capturePane(paneID: String) async -> String? {
        guard let helper = session.helperClient else { return nil }

        do {
            return try await helper.capturePaneContent(session: workspace.tmuxSessionName, paneID: paneID, lines: 200)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func forwardAndPreview(_ candidate: PreviewCandidateDTO) async {
        guard let forwardService = session.forwardService else {
            errorMessage = "Port forwarding is not available for this session."
            return
        }

        do {
            let forward = try forwardService.startForward(
                name: previewDisplayName(for: candidate),
                localPort: 0,
                remoteHost: "127.0.0.1",
                remotePort: candidate.port
            )
            refreshActiveForwards()
            previewCandidateService.markForwarded(port: candidate.port)
            showingPreviewCandidates = false
            await openPreview(for: forward, candidate: candidate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attemptAutoSurfacePreview() {
        guard workspace.previewRules.openInApp else { return }

        if let forward = preferredAutoPreviewForward(),
           autoSurfacedPreviewRemotePort != forward.remotePort {
            autoSurfacedPreviewRemotePort = forward.remotePort
            Task {
                await openPreview(for: forward)
            }
            return
        }

        guard workspace.previewRules.autoDetect,
              !didAutoPresentPreviewDiscovery,
              !mergedPreviewCandidates.isEmpty else {
            return
        }

        didAutoPresentPreviewDiscovery = true
        showingPreviewCandidates = true
    }

    private func preferredAutoPreviewForward() -> ActiveForward? {
        let explicitAutoPreviewPorts = Set(workspace.savedForwards.filter(\.autoPreview).map(\.remotePort))
        if let forward = activePreviewForwards.first(where: { explicitAutoPreviewPorts.contains($0.remotePort) }) {
            return forward
        }

        let detectedPorts = Set((session.resumePlan?.forward_candidates ?? []).map(\.port))
        if let forward = activePreviewForwards.first(where: { detectedPorts.contains($0.remotePort) }) {
            return forward
        }

        return activePreviewForwards.first
    }

    private func isLikelyPreviewForward(_ forward: ActiveForward) -> Bool {
        let previewPorts = Set((session.resumePlan?.forward_candidates ?? []).map(\.port))
        let explicitAutoPreviewPorts = Set(workspace.savedForwards.filter(\.autoPreview).map(\.remotePort))
        let knownPreviewPorts: Set<Int> = [3000, 3001, 4173, 4200, 5173, 8000, 8080, 8081, 8787]
        let loweredName = forward.name.lowercased()

        return previewPorts.contains(forward.remotePort)
            || explicitAutoPreviewPorts.contains(forward.remotePort)
            || knownPreviewPorts.contains(forward.remotePort)
            || loweredName.contains("preview")
            || loweredName.contains("web")
            || loweredName.contains("app")
            || loweredName.contains("dev")
    }

    private func previewDestination(
        for forward: ActiveForward,
        localPort: Int,
        candidate: PreviewCandidateDTO? = nil
    ) -> WorkspacePreviewDestination {
        WorkspacePreviewDestination(
            id: forward.id,
            localPort: localPort,
            displayName: candidate.map { previewDisplayName(for: $0) } ?? previewDisplayName(for: forward),
            scheme: "http"
        )
    }

    private func openPreview(for forward: ActiveForward, candidate: PreviewCandidateDTO? = nil) async {
        let resolvedLocalPort = await waitForResolvedLocalPort(forward)
        guard resolvedLocalPort > 0 else {
            errorMessage = "The local preview forward did not become ready."
            return
        }

        selectedPreview = previewDestination(for: forward, localPort: resolvedLocalPort, candidate: candidate)
    }

    private func waitForResolvedLocalPort(_ forward: ActiveForward) async -> Int {
        if forward.resolvedLocalPort > 0 {
            return forward.resolvedLocalPort
        }

        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if forward.resolvedLocalPort > 0 {
                return forward.resolvedLocalPort
            }
        }

        return forward.resolvedLocalPort
    }

    private func previewDisplayName(for candidate: PreviewCandidateDTO) -> String {
        if let savedForward = workspace.savedForwards.first(where: { $0.remotePort == candidate.port }) {
            return savedForward.name
        }

        if let processLabel = candidate.process_label, !processLabel.isEmpty {
            return processLabel
        }

        return candidate.process_name
    }

    private func previewDisplayName(for forward: ActiveForward) -> String {
        if let savedForward = workspace.savedForwards.first(where: { $0.remotePort == forward.remotePort }) {
            return savedForward.name
        }

        if let candidate = mergedPreviewCandidates.first(where: { $0.port == forward.remotePort }) {
            return previewDisplayName(for: candidate)
        }

        if let candidate = session.resumePlan?.forward_candidates.first(where: { $0.port == forward.remotePort }) {
            return previewDisplayName(for: candidate)
        }

        return forward.name
    }

    private func lensSortOrder(for role: PaneRole) -> Int {
        switch role {
        case .agent: 0
        case .tests: 1
        case .server: 2
        case .logs: 3
        case .shell: 4
        case .db: 5
        case .scratch: 6
        }
    }
}

private struct WorkspacePreviewDestination: Identifiable {
    let id: String
    let localPort: Int
    let displayName: String
    let scheme: String
}
