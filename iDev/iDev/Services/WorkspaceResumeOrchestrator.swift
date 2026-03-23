import Foundation
import SwiftData
import iDevSSH

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

    /// Set by the UI when the user decides on helper install.
    var helperInstallDecision: HelperInstallDecision?

    /// Set by the UI when the user decides on resume plan.
    var resumePlanDecision: ResumePlanDecision?

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
        modelContext: ModelContext
    ) async throws -> ManagedSession {
        phase = .idle
        resumePlan = nil
        helperDetectionResult = nil
        helperInstallDecision = nil
        resumePlanDecision = nil

        let managed = sessionManager.createSession(host: host)
        let session = managed.sshSession

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
            case .newHost:
                knownHostsService.trustHost(hostname: host.hostname, port: host.port, hostKey: sshHostKey)
            case .mismatch:
                throw SSHError.handshakeFailed("Host key mismatch — possible security issue")
            }

            // 3. Authenticate
            phase = .authenticating
            let authenticator = SSHAuthenticator(vaultService: vaultService, authGateService: authGateService)
            let credential = try await authenticator.resolveCredential(for: host)
            try await session.authenticate(credential: credential)

            // 4. Open shell + attach to bridge
            let shell = try await session.openShell(pty: PTYConfig())
            managed.bridge.attachShell(shell)

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
                // UI will show HelperInstallSheet — the decision is set asynchronously
                // For now, continue without helper. The UI layer can trigger install separately.
                managed.isHelperAvailable = false

            case .error:
                managed.isHelperAvailable = false
            }

            // 6. Fetch resume plan (if helper available)
            if managed.isHelperAvailable, let helper = managed.helperClient {
                phase = .fetchingResumePlan
                resumePlan = try? await helper.resumePlan(workspaceID: workspace.id)
            }

            // 7. Resume tmux session
            phase = .resumingTmux
            if let plan = resumePlan, let helper = managed.helperClient {
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

                // 8. Auto-assign pane roles
                phase = .assigningPaneRoles
                let paneDefinitions = workspace.tmuxPanes
                if !paneDefinitions.isEmpty {
                    let panes = try? await helper.listTmuxPanes(session: workspace.tmuxSessionName)
                    // Role assignments are stored in workspace pane definitions and used by the UI.
                    // No active action needed here — the pane list view reads from workspace.tmuxPanes.
                    _ = panes
                }
            } else {
                // Fallback: try attaching directly
                let tmuxSession = workspace.tmuxSessionName
                if !tmuxSession.isEmpty {
                    let cmd = "tmux new-session -A -s \(tmuxSession)\n"
                    try await managed.bridge.sendToRemote(Data(cmd.utf8))
                }
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
                    for candidate in plan.forward_candidates {
                        // Auto-forward candidates that match saved forwards
                        let matchesSaved = workspace.savedForwards.contains { $0.remotePort == candidate.port }
                        if matchesSaved {
                            do {
                                try forwardService.startForward(
                                    name: candidate.process_name,
                                    localPort: 0,  // Auto-assign
                                    remoteHost: "127.0.0.1",
                                    remotePort: candidate.port
                                )
                            } catch {
                                // Non-fatal
                            }
                        }
                    }
                }
            }

            // 11. Auto-open previews (handled by UI layer based on forward state)

            // 12. Ready
            phase = .ready
            return managed

        } catch {
            phase = .failed(error.localizedDescription)
            sessionManager.removeSession(id: managed.id)
            throw error
        }
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
