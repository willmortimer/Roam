import Foundation
import SwiftData
import RoamSSH

/// Manages all active SSH sessions across the app.
@Observable
final class SessionManager {
    private let restorationStore: SessionRestorationStore
    private(set) var sessions: [ManagedSession] = []
    private(set) var restorableSessions: [PersistedSessionSnapshot]
    private(set) var isRestoringPersistedSessions = false
    private var shouldReconnectActiveSessionsOnNextForeground = false

    init(restorationStore: SessionRestorationStore = SessionRestorationStore()) {
        self.restorationStore = restorationStore
        self.restorableSessions = restorationStore.load()
    }

    /// Create a tracked SSH session for a host.
    /// Workspace resume and direct connect are SSH-native for now.
    func createSession(host: HostRecord, restorationContext: SessionRestorationContext) -> ManagedSession {
        let sshSession = LibSSH2Session()
        let bridge = TerminalSessionBridge(sessionID: sshSession.sessionID, sshSession: sshSession)
        let managed = ManagedSession(
            restorationContext: restorationContext,
            hostAlias: host.alias,
            username: host.username,
            hostname: host.hostname,
            port: host.port,
            transportType: .ssh,
            sshSession: sshSession,
            bridge: bridge
        )
        return storeSession(managed)
    }

    /// Track a session that was connected outside the manager (for example via the connection sheet).
    func registerConnectedSession(
        host: HostRecord,
        restorationContext: SessionRestorationContext,
        sshSession: LibSSH2Session,
        shellChannel: ShellChannel
    ) -> ManagedSession {
        let bridge = TerminalSessionBridge(sessionID: sshSession.sessionID, sshSession: sshSession)
        bridge.attachShell(shellChannel)

        host.lastSeen = .now

        let managed = ManagedSession(
            restorationContext: restorationContext,
            hostAlias: host.alias,
            username: host.username,
            hostname: host.hostname,
            port: host.port,
            transportType: .ssh,
            sshSession: sshSession,
            bridge: bridge
        )
        return storeSession(managed)
    }

    /// Remove a session after disconnect.
    func removeSession(id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let restorationID = sessions[index].restorationContext.id
        sessions.remove(at: index)
        restorableSessions.removeAll { $0.id == restorationID }
        persistSessionState()
    }

    /// Find a session by ID.
    func session(id: String) -> ManagedSession? {
        sessions.first { $0.id == id }
    }

    func disconnectSession(id: String) async {
        guard let managed = session(id: id) else { return }
        await managed.disconnect()
        removeSession(id: id)
    }

    /// Disconnect all sessions.
    func disconnectAll() async {
        for session in sessions {
            await session.disconnect()
        }
        sessions.removeAll()
        restorableSessions.removeAll()
        persistSessionState()
    }

    func prepareForSuspension() {
        shouldReconnectActiveSessionsOnNextForeground = !sessions.isEmpty
        persistSessionState()
    }

    func restoreSessionsIfNeeded(
        modelContext: ModelContext,
        resumeOrchestrator: WorkspaceResumeOrchestrator
    ) async {
        guard !isRestoringPersistedSessions else { return }
        isRestoringPersistedSessions = true
        defer {
            isRestoringPersistedSessions = false
            persistSessionState()
        }

        if shouldReconnectActiveSessionsOnNextForeground, !sessions.isEmpty {
            shouldReconnectActiveSessionsOnNextForeground = false
            for session in sessions {
                await reconnectSession(
                    id: session.id,
                    modelContext: modelContext,
                    resumeOrchestrator: resumeOrchestrator
                )
            }
        }

        if sessions.isEmpty {
            let pendingSnapshotIDs = restorableSessions
                .filter { $0.restoreStatus == .pending }
                .map(\.id)

            for snapshotID in pendingSnapshotIDs {
                await restoreRestorableSession(
                    id: snapshotID,
                    modelContext: modelContext,
                    resumeOrchestrator: resumeOrchestrator
                )
            }
        }
    }

    func reconnectSession(
        id: String,
        modelContext: ModelContext,
        resumeOrchestrator: WorkspaceResumeOrchestrator
    ) async {
        guard let managed = session(id: id) else { return }

        managed.restoreErrorMessage = nil
        managed.isRestoring = true
        await managed.disconnect()

        do {
            switch managed.restorationContext.source {
            case .directHost:
                let host = try fetchHost(id: managed.restorationContext.hostID, modelContext: modelContext)
                _ = try await reconnectDirectSession(
                    managed,
                    host: host,
                    modelContext: modelContext
                )
            case .workspace:
                guard let workspaceID = managed.restorationContext.workspaceID else {
                    throw SessionRestoreError.workspaceMissing("Missing workspace reference for restored session.")
                }
                let host = try fetchHost(id: managed.restorationContext.hostID, modelContext: modelContext)
                let workspace = try fetchWorkspace(id: workspaceID, modelContext: modelContext)
                _ = try await resumeOrchestrator.resume(
                    workspace: workspace,
                    host: host,
                    modelContext: modelContext,
                    interactionMode: .automaticRestore,
                    existingSession: managed
                )
            }
        } catch {
            managed.markRestoreFailed(error.localizedDescription)
        }
    }

    func retryRestorableSession(
        id: String,
        modelContext: ModelContext,
        resumeOrchestrator: WorkspaceResumeOrchestrator
    ) async {
        updateRestorableSession(id: id) { snapshot in
            snapshot.restoreStatus = .pending
            snapshot.lastErrorMessage = nil
            snapshot.updatedAt = .now
        }

        await restoreRestorableSession(
            id: id,
            modelContext: modelContext,
            resumeOrchestrator: resumeOrchestrator
        )
    }

    func removeRestorableSession(id: String) {
        restorableSessions.removeAll { $0.id == id }
        persistSessionState()
    }

    @discardableResult
    private func storeSession(_ managed: ManagedSession) -> ManagedSession {
        sessions.removeAll { $0.id == managed.id }
        restorableSessions.removeAll { $0.id == managed.restorationContext.id }
        sessions.append(managed)
        persistSessionState()
        return managed
    }

    private func restoreRestorableSession(
        id: String,
        modelContext: ModelContext,
        resumeOrchestrator: WorkspaceResumeOrchestrator
    ) async {
        guard let snapshot = restorableSessions.first(where: { $0.id == id }) else { return }

        updateRestorableSession(id: id) { restorable in
            restorable.restoreStatus = .restoring
            restorable.lastErrorMessage = nil
            restorable.updatedAt = .now
        }

        do {
            switch snapshot.source {
            case .directHost:
                let host = try fetchHost(id: snapshot.hostID, modelContext: modelContext)
                _ = try await reconnectDirectSession(
                    nil,
                    host: host,
                    modelContext: modelContext,
                    restorationContext: snapshot.restorationContext
                )
            case .workspace:
                guard let workspaceID = snapshot.workspaceID else {
                    throw SessionRestoreError.workspaceMissing("Missing workspace reference for restored session.")
                }
                let host = try fetchHost(id: snapshot.hostID, modelContext: modelContext)
                let workspace = try fetchWorkspace(id: workspaceID, modelContext: modelContext)
                _ = try await resumeOrchestrator.resume(
                    workspace: workspace,
                    host: host,
                    modelContext: modelContext,
                    interactionMode: .automaticRestore,
                    restorationID: snapshot.id
                )
            }

            restorableSessions.removeAll { $0.id == id }
        } catch {
            updateRestorableSession(id: id) { restorable in
                restorable.restoreStatus = .failed
                restorable.lastErrorMessage = error.localizedDescription
                restorable.updatedAt = .now
            }
        }
    }

    private func reconnectDirectSession(
        _ existingSession: ManagedSession?,
        host: HostRecord,
        modelContext: ModelContext,
        restorationContext: SessionRestorationContext? = nil
    ) async throws -> ManagedSession {
        switch host.authMethod {
        case .password:
            throw SessionRestoreError.passwordAuthRequiresManualReconnect
        case .agent:
            throw SessionRestoreError.agentAuthRequiresManualReconnect
        case .key:
            break
        }

        let sshSession = LibSSH2Session()

        do {
            try await sshSession.connect(hostname: host.hostname, port: host.port)

            let hostKeyInfo = try sshSession.hostKey()
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
            case .newHost, .mismatch:
                throw SessionRestoreError.hostTrustRequiresManualReconnect
            }

            let authenticator = SSHAuthenticator(
                vaultService: VaultService.shared,
                authGateService: AuthGateService.shared
            )
            let credential = try await authenticator.resolveCredential(for: host, modelContext: modelContext)
            try await sshSession.authenticate(credential: credential)

            let shell = try await sshSession.openShell()
            let bridge = TerminalSessionBridge(sessionID: sshSession.sessionID, sshSession: sshSession)
            bridge.attachShell(shell)

            if let existingSession {
                existingSession.replaceConnection(
                    host: host,
                    sshSession: sshSession,
                    bridge: bridge
                )
                return existingSession
            }

            let context = restorationContext ?? SessionRestorationContext.directHost(host: host)
            return registerConnectedSession(
                host: host,
                restorationContext: context,
                sshSession: sshSession,
                shellChannel: shell
            )
        } catch {
            await sshSession.disconnect()
            throw error
        }
    }

    private func fetchHost(id: String, modelContext: ModelContext) throws -> HostRecord {
        let predicate = #Predicate<HostRecord> { host in
            host.id == id
        }
        let descriptor = FetchDescriptor<HostRecord>(predicate: predicate)

        guard let host = try modelContext.fetch(descriptor).first else {
            throw SessionRestoreError.hostMissing("Host \(id) no longer exists.")
        }

        return host
    }

    private func fetchWorkspace(id: String, modelContext: ModelContext) throws -> WorkspaceRecord {
        let predicate = #Predicate<WorkspaceRecord> { workspace in
            workspace.id == id
        }
        let descriptor = FetchDescriptor<WorkspaceRecord>(predicate: predicate)

        guard let workspace = try modelContext.fetch(descriptor).first else {
            throw SessionRestoreError.workspaceMissing("Workspace \(id) no longer exists.")
        }

        return workspace
    }

    private func updateRestorableSession(
        id: String,
        mutate: (inout PersistedSessionSnapshot) -> Void
    ) {
        guard let index = restorableSessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&restorableSessions[index])
        persistSessionState()
    }

    private func persistSessionState() {
        let activeSnapshots = sessions.map { session in
            PersistedSessionSnapshot(
                id: session.restorationContext.id,
                source: session.restorationContext.source,
                hostID: session.restorationContext.hostID,
                hostAlias: session.hostAlias,
                username: session.username,
                hostname: session.hostname,
                port: session.port,
                workspaceID: session.restorationContext.workspaceID,
                workspaceName: session.restorationContext.workspaceName,
                restoreStatus: .pending,
                lastErrorMessage: session.restoreErrorMessage,
                createdAt: session.createdAt,
                updatedAt: .now
            )
        }

        var snapshotsByID = Dictionary(uniqueKeysWithValues: restorableSessions.map { ($0.id, $0) })
        for snapshot in activeSnapshots {
            snapshotsByID[snapshot.id] = snapshot
        }

        let persistedSnapshots = snapshotsByID.values.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }

        restorationStore.save(persistedSnapshots)
    }
}

/// A tracked SSH session with its bridge and helper client.
@Observable
final class ManagedSession: Identifiable {
    let id: String
    let restorationContext: SessionRestorationContext
    let createdAt: Date
    var hostAlias: String
    var username: String
    var hostname: String
    var port: Int
    var transportType: TransportType
    var sshSession: LibSSH2Session
    var bridge: any TerminalSessionBridgeProtocol
    var helperClient: (any HelperClientProtocol)?
    var forwardService: LocalForwardService?
    var sftpChannel: SFTPChannel?
    var isHelperAvailable = false
    var helperDetectionResult: HelperDetectionResult?
    var resumePlan: ResumePlanDTO?
    var tmuxPanes: [TmuxPaneDTO] = []
    var isRestoring = false
    var restoreErrorMessage: String?

    init(
        restorationContext: SessionRestorationContext,
        hostAlias: String,
        username: String,
        hostname: String,
        port: Int,
        transportType: TransportType = .ssh,
        sshSession: LibSSH2Session,
        bridge: any TerminalSessionBridgeProtocol
    ) {
        self.id = restorationContext.id
        self.restorationContext = restorationContext
        self.createdAt = .now
        self.hostAlias = hostAlias
        self.username = username
        self.hostname = hostname
        self.port = port
        self.transportType = transportType
        self.sshSession = sshSession
        self.bridge = bridge
    }

    var connectionLiveness: ConnectionDot.ConnectionLiveness {
        if isRestoring {
            return ConnectionDot.ConnectionLiveness.connecting
        }

        switch bridge.connectionState {
        case .connected:
            return ConnectionDot.ConnectionLiveness.connected
        case .connecting, .authenticating:
            return ConnectionDot.ConnectionLiveness.connecting
        case .disconnected:
            return ConnectionDot.ConnectionLiveness.disconnected
        case .error:
            return ConnectionDot.ConnectionLiveness.disconnected
        }
    }

    func replaceConnection(
        host: HostRecord,
        sshSession: LibSSH2Session,
        bridge: any TerminalSessionBridgeProtocol
    ) {
        self.hostAlias = host.alias
        self.username = host.username
        self.hostname = host.hostname
        self.port = host.port
        self.transportType = .ssh
        self.sshSession = sshSession
        self.bridge = bridge
        self.restoreErrorMessage = nil
        self.isRestoring = false
    }

    func markRestoreFailed(_ message: String) {
        isRestoring = false
        restoreErrorMessage = message
    }

    func disconnect() async {
        forwardService?.stopAll()
        forwardService = nil
        helperClient = nil
        sftpChannel = nil
        isHelperAvailable = false
        await bridge.disconnect()
    }
}

private enum SessionRestoreError: LocalizedError {
    case hostMissing(String)
    case workspaceMissing(String)
    case passwordAuthRequiresManualReconnect
    case agentAuthRequiresManualReconnect
    case hostTrustRequiresManualReconnect

    var errorDescription: String? {
        switch self {
        case .hostMissing(let message), .workspaceMissing(let message):
            message
        case .passwordAuthRequiresManualReconnect:
            "Password-auth sessions need a manual reconnect."
        case .agentAuthRequiresManualReconnect:
            "SSH agent sessions need a manual reconnect."
        case .hostTrustRequiresManualReconnect:
            "Host-key trust must be reviewed manually before this session can be restored."
        }
    }
}
