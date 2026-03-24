import Foundation
import SwiftData
import RoamSSH

/// Orchestrates the full "Resume Workspace" flow with helper-enhanced features:
/// 1. Connect to host
/// 2. Verify host key
/// 3. Authenticate
/// 4. Open shell + attach bridge
/// 5. Detect helper (with install/upgrade option)
/// 6. Fetch resume plan (if helper available)
/// 7. Resume tmux session
/// 8. Auto-assign pane roles
/// 9. Open configured forwards
/// 10. Auto-forward preview candidates
/// 11. Auto-open previews
/// 12. Ready
@Observable
final class WorkspaceResumeOrchestrator {
    enum ResumePhase: Equatable {
        case idle
        case connecting
        case authenticating
        case detectingHelper
        case installingHelper
        case fetchingResumePlan
        case resumingTmux
        case assigningPaneRoles
        case openingForwards
        case detectingPreviews
        case ready
        case failed(String)
    }

    private(set) var phase: ResumePhase = .idle
    private(set) var resumePlan: ResumePlanDTO?
    private(set) var helperDetectionResult: HelperDetectionResult?
    private(set) var hostKeyVerificationRequest: WorkspaceResumeHostKeyVerificationRequest?
    private(set) var helperInstallRequest: WorkspaceHelperInstallRequest?
    private(set) var resumePlanRequest: WorkspaceResumePlanRequest?

    /// Set by the UI when the user decides on helper install.
    var helperInstallDecision: HelperInstallDecision?

    /// Set by the UI when the user decides on resume plan.
    var resumePlanDecision: ResumePlanDecision?

    private var hostKeyDecisionContinuation: CheckedContinuation<HostKeyDecision, Never>?
    private var helperInstallDecisionContinuation: CheckedContinuation<HelperInstallDecision, Never>?
    private var resumePlanDecisionContinuation: CheckedContinuation<ResumePlanDecision, Never>?

    private let sessionManager: SessionManager
    private let vaultService: VaultService
    private let authGateService: AuthGateService

    init(sessionManager: SessionManager, vaultService: VaultService, authGateService: AuthGateService) {
        self.sessionManager = sessionManager
        self.vaultService = vaultService
        self.authGateService = authGateService
    }

    /// Execute the full resume flow.
    /// Returns the managed session on success.
    @discardableResult
    func resume(
        workspace: WorkspaceRecord,
        host: HostRecord,
        modelContext: ModelContext,
        interactionMode: ResumeInteractionMode = .interactive,
        existingSession: ManagedSession? = nil,
        restorationID: String? = nil
    ) async throws -> ManagedSession {
        phase = .idle
        resumePlan = nil
        helperDetectionResult = nil
        hostKeyVerificationRequest = nil
        helperInstallRequest = nil
        resumePlanRequest = nil
        helperInstallDecision = nil
        resumePlanDecision = nil
        hostKeyDecisionContinuation = nil
        helperInstallDecisionContinuation = nil
        resumePlanDecisionContinuation = nil

        let managed: ManagedSession
        let session: LibSSH2Session
        let reconnectBridge: TerminalSessionBridge?

        if let existingSession {
            managed = existingSession
            managed.isRestoring = true
            managed.restoreErrorMessage = nil
            session = LibSSH2Session()
            reconnectBridge = TerminalSessionBridge(sessionID: session.sessionID, sshSession: session)
        } else {
            let context = SessionRestorationContext.workspace(
                host: host,
                workspace: workspace,
                restorationID: restorationID ?? UUID().uuidString
            )
            managed = sessionManager.createSession(host: host, restorationContext: context)
            session = managed.sshSession
            reconnectBridge = nil
        }

        do {
            // 1. Connect
            phase = .connecting
            try await session.connect(hostname: host.hostname, port: host.port)

            // 2. Verify host key
            let hostKeyInfo = try session.hostKey()
            let sshHostKey = SSHHostKey(
                algorithm: hostKeyInfo.algorithm,
                fingerprint: hostKeyInfo.fingerprint,
                rawKey: hostKeyInfo.rawKey
            )
            let knownHostsService = KnownHostsService(modelContext: modelContext)
            let verification = knownHostsService.verify(
                hostname: host.hostname,
                port: host.port,
                hostKey: sshHostKey
            )

            switch verification {
            case .trusted:
                break
            case .newHost(let hostKey):
                switch interactionMode {
                case .interactive:
                    let decision = await requestHostKeyDecision(hostKey: hostKey, existingRecord: nil)
                    try handleHostKeyDecision(
                        decision,
                        host: host,
                        hostKey: hostKey,
                        knownHostsService: knownHostsService
                    )
                case .automaticRestore:
                    throw SSHError.handshakeFailed("Host-key trust must be reviewed manually before this workspace can be restored.")
                }
            case .mismatch(let old, let new):
                switch interactionMode {
                case .interactive:
                    let decision = await requestHostKeyDecision(hostKey: new, existingRecord: old)
                    try handleHostKeyDecision(
                        decision,
                        host: host,
                        hostKey: new,
                        knownHostsService: knownHostsService
                    )
                case .automaticRestore:
                    throw SSHError.handshakeFailed("Host-key trust must be reviewed manually before this workspace can be restored.")
                }
            }

            // 3. Authenticate
            phase = .authenticating
            let authenticator = SSHAuthenticator(vaultService: vaultService, authGateService: authGateService)
            let credential = try await authenticator.resolveCredential(for: host, modelContext: modelContext)
            try await session.authenticate(credential: credential)

            // 4. Open shell + attach to bridge
            let shell = try await session.openShell(pty: PTYConfig())
            if let reconnectBridge {
                reconnectBridge.attachShell(shell)
                managed.replaceConnection(
                    host: host,
                    sshSession: session,
                    bridge: reconnectBridge
                )
            } else {
                managed.bridge.attachShell(shell)
            }

            // 5. Detect helper (with install/upgrade support)
            phase = .detectingHelper
            let installService = HelperInstallService(sshSession: session)
            let detection = await installService.detectHelper()
            helperDetectionResult = detection
            managed.helperDetectionResult = detection

            switch detection {
            case .installed(let version):
                host.lastHelperVersion = version
                host.lastHelperCheck = Date()
                // Start helper RPC client
                let helperClient = HelperClient(sshSession: session)
                try await helperClient.start()
                managed.helperClient = helperClient
                managed.isHelperAvailable = await helperClient.isAvailable()

            case .outdated, .notInstalled:
                managed.isHelperAvailable = false
                if interactionMode == .interactive {
                    let decision = await requestHelperInstallDecision(detection)
                    if decision == .install {
                        phase = .installingHelper
                        let arch = try await installService.detectArchitecture()
                        let binaryData = try await HelperBinaryLocator.binaryData(for: arch)

                        switch detection {
                        case .outdated:
                            try await installService.upgradeHelper(binaryData: binaryData)
                        case .notInstalled:
                            try await installService.installHelper(binaryData: binaryData)
                        case .installed, .error:
                            break
                        }

                        let postInstallDetection = await installService.detectHelper()
                        helperDetectionResult = postInstallDetection
                        managed.helperDetectionResult = postInstallDetection

                        guard case .installed(let version) = postInstallDetection else {
                            throw HelperInstallError.verificationFailed
                        }

                        host.lastHelperVersion = version
                        host.lastHelperCheck = Date()

                        let helperClient = HelperClient(sshSession: session)
                        try await helperClient.start()
                        managed.helperClient = helperClient
                        managed.isHelperAvailable = await helperClient.isAvailable()
                    }
                }

            case .error:
                managed.isHelperAvailable = false
            }

            // 6. Fetch resume plan (if helper available)
            if managed.isHelperAvailable, let helper = managed.helperClient {
                phase = .fetchingResumePlan
                if let fetchedPlan = try? await helper.resumePlan(workspaceID: workspace.id) {
                    switch interactionMode {
                    case .interactive:
                        let decision = await requestResumePlanDecision(fetchedPlan)
                        switch decision {
                        case .proceed:
                            resumePlan = fetchedPlan
                        case .skipHelperFeatures:
                            resumePlan = nil
                        }
                    case .automaticRestore:
                        resumePlan = fetchedPlan
                    }
                }
            }
            managed.resumePlan = resumePlan

            // 7. Resume tmux session
            phase = .resumingTmux
            if let plan = resumePlan, managed.helperClient != nil {
                if plan.tmux_session_exists, let target = plan.recommended_attach_target {
                    let attachCmd = "tmux attach-session -t \(target)\n"
                    try await managed.bridge.sendToRemote(Data(attachCmd.utf8))
                } else {
                    // Create new session
                    let tmuxSession = workspace.tmuxSessionName
                    if !tmuxSession.isEmpty {
                        let cmd = "tmux new-session -A -s \(tmuxSession)\n"
                        try await managed.bridge.sendToRemote(Data(cmd.utf8))
                    }
                }
            } else {
                // Fallback: try attaching directly
                let tmuxSession = workspace.tmuxSessionName
                if !tmuxSession.isEmpty {
                    let cmd = "tmux new-session -A -s \(tmuxSession)\n"
                    try await managed.bridge.sendToRemote(Data(cmd.utf8))
                }
            }

            // 8. Auto-assign pane roles
            phase = .assigningPaneRoles
            if let helper = managed.helperClient, !workspace.tmuxSessionName.isEmpty {
                let panes = (try? await helper.listTmuxPanes(session: workspace.tmuxSessionName)) ?? []
                managed.tmuxPanes = panes

                // Auto-detect roles for panes without explicit definitions
                let definedWindows = Set(workspace.tmuxPanes.map(\.window))
                var newDefinitions: [PaneDefinition] = []

                for pane in panes {
                    guard !definedWindows.contains(pane.window) else { continue }
                    if let role = Self.inferPaneRole(from: pane) {
                        newDefinitions.append(PaneDefinition(role: role, window: pane.window))
                    }
                }

                if !newDefinitions.isEmpty {
                    workspace.tmuxPanes.append(contentsOf: newDefinitions)
                }
            } else {
                managed.tmuxPanes = []
            }

            // 9. Open configured forwards
            phase = .openingForwards
            let forwardService = LocalForwardService(sshSession: session)
            managed.forwardService = forwardService

            for fwd in workspace.savedForwards {
                do {
                    try forwardService.startForward(
                        name: fwd.name,
                        localPort: UInt16(fwd.localPort ?? 0),
                        remoteHost: fwd.remoteHost,
                        remotePort: fwd.remotePort
                    )
                } catch {
                    // Non-fatal: log but continue
                }
            }

            // 10. Auto-forward preview candidates
            phase = .detectingPreviews
            if let plan = resumePlan, managed.isHelperAvailable {
                let rules = workspace.previewRules
                if rules.autoDetect {
                    let candidatesToForward = forwardService.autoForwardCandidates(
                        plan.forward_candidates,
                        rules: rules,
                        existingForwards: workspace.savedForwards
                    )

                    for candidate in candidatesToForward {
                        do {
                            try forwardService.startForward(
                                name: previewDisplayName(for: candidate, workspace: workspace),
                                localPort: 0,
                                remoteHost: "127.0.0.1",
                                remotePort: candidate.port
                            )
                        } catch {
                            // Non-fatal
                        }
                    }
                }
            }

            // 11. Open SFTP channel + auto-preview readiness
            // SFTP enables file browsing and the lightweight editor for this session.
            // Preview auto-open is handled by WorkspaceSessionCockpitView based on forward state.
            if managed.sftpChannel == nil {
                managed.sftpChannel = try? await session.openSFTP()
            }

            // 12. Ready
            host.lastSeen = .now
            workspace.lastOpened = .now
            phase = .ready
            hostKeyVerificationRequest = nil
            helperInstallRequest = nil
            resumePlanRequest = nil
            return managed

        } catch {
            phase = .failed(error.localizedDescription)
            hostKeyVerificationRequest = nil
            helperInstallRequest = nil
            resumePlanRequest = nil
            hostKeyDecisionContinuation = nil
            helperInstallDecisionContinuation = nil
            resumePlanDecisionContinuation = nil

            if existingSession == nil {
                await managed.disconnect()
                sessionManager.removeSession(id: managed.id)
            } else {
                await session.disconnect()
            }
            throw error
        }
    }

    func submitHostKeyDecision(_ decision: HostKeyDecision) {
        hostKeyVerificationRequest = nil
        hostKeyDecisionContinuation?.resume(returning: decision)
        hostKeyDecisionContinuation = nil
    }

    func submitHelperInstallDecision(_ decision: HelperInstallDecision) {
        helperInstallRequest = nil
        helperInstallDecisionContinuation?.resume(returning: decision)
        helperInstallDecisionContinuation = nil
    }

    func submitResumePlanDecision(_ decision: ResumePlanDecision) {
        resumePlanRequest = nil
        resumePlanDecisionContinuation?.resume(returning: decision)
        resumePlanDecisionContinuation = nil
    }

    private func requestHostKeyDecision(
        hostKey: SSHHostKey,
        existingRecord: KnownHostRecord?
    ) async -> HostKeyDecision {
        hostKeyVerificationRequest = WorkspaceResumeHostKeyVerificationRequest(
            hostKey: hostKey,
            existingRecord: existingRecord
        )

        return await withCheckedContinuation { continuation in
            hostKeyDecisionContinuation = continuation
        }
    }

    private func requestHelperInstallDecision(
        _ detectionResult: HelperDetectionResult
    ) async -> HelperInstallDecision {
        helperInstallRequest = WorkspaceHelperInstallRequest(detectionResult: detectionResult)

        return await withCheckedContinuation { continuation in
            helperInstallDecisionContinuation = continuation
        }
    }

    private func requestResumePlanDecision(_ plan: ResumePlanDTO) async -> ResumePlanDecision {
        resumePlanRequest = WorkspaceResumePlanRequest(plan: plan)

        return await withCheckedContinuation { continuation in
            resumePlanDecisionContinuation = continuation
        }
    }

    private func handleHostKeyDecision(
        _ decision: HostKeyDecision,
        host: HostRecord,
        hostKey: SSHHostKey,
        knownHostsService: KnownHostsService
    ) throws {
        switch decision {
        case .trustAlways:
            knownHostsService.trustHost(hostname: host.hostname, port: host.port, hostKey: hostKey)
        case .trustOnce:
            break
        case .reject:
            throw SSHError.handshakeFailed("Host key rejected")
        }
    }

    /// Infer a pane's role from its running command and metadata.
    static func inferPaneRole(from pane: TmuxPaneDTO) -> PaneRole? {
        let cmd = pane.current_command.lowercased()
        let title = pane.title.lowercased()
        let window = pane.window.lowercased()

        // Test runners
        if cmd.contains("pytest") || cmd.contains("jest") || cmd.contains("vitest")
            || cmd.contains("cargo test") || cmd.contains("go test") || cmd.contains("swift test")
            || cmd.contains("xcodebuild test") || cmd.contains("rspec") || cmd.contains("phpunit")
            || title.contains("test") || window.contains("test") {
            return .tests
        }

        // Database shells
        if cmd.contains("psql") || cmd.contains("mysql") || cmd.contains("redis-cli")
            || cmd.contains("mongosh") || cmd.contains("sqlite3")
            || title.contains("db") || window.contains("db") {
            return .db
        }

        // Log viewers
        if cmd.hasPrefix("tail") || cmd.contains("journalctl") || cmd.contains("docker logs")
            || cmd.contains("kubectl logs") || title.contains("log") || window.contains("log") {
            return .logs
        }

        // Dev servers
        if cmd.contains("npm run") || cmd.contains("pnpm") || cmd.contains("yarn dev")
            || cmd.contains("next dev") || cmd.contains("vite") || cmd.contains("flask run")
            || cmd.contains("uvicorn") || cmd.contains("cargo run") || cmd.contains("go run")
            || cmd.contains("rails s") || cmd.contains("php artisan serve")
            || title.contains("server") || window.contains("server") {
            return .server
        }

        // AI agents
        if cmd.contains("copilot") || cmd.contains("aider") || cmd.contains("claude")
            || cmd.contains("cursor") || title.contains("agent") || window.contains("agent") {
            return .agent
        }

        // Don't guess shell — leave unmatched panes without a role
        return nil
    }

    private func previewDisplayName(for candidate: PreviewCandidateDTO, workspace: WorkspaceRecord) -> String {
        if let savedForward = workspace.savedForwards.first(where: { $0.remotePort == candidate.port }) {
            return savedForward.name
        }

        if let processLabel = candidate.process_label, !processLabel.isEmpty {
            return processLabel
        }

        return candidate.process_name
    }
}

// MARK: - Decision Types

enum HelperInstallDecision {
    case install
    case skip
}

enum ResumePlanDecision {
    case proceed
    case skipHelperFeatures
}

struct WorkspaceResumeHostKeyVerificationRequest: Identifiable {
    let id = UUID()
    let hostKey: SSHHostKey
    let existingRecord: KnownHostRecord?
}

struct WorkspaceHelperInstallRequest: Identifiable {
    let id = UUID()
    let detectionResult: HelperDetectionResult
}

struct WorkspaceResumePlanRequest: Identifiable {
    let id = UUID()
    let plan: ResumePlanDTO
}

enum ResumeInteractionMode: Sendable {
    case interactive
    case automaticRestore
}
