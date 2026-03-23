import Foundation
import SwiftData
import iDevSSH

/// Manages all active SSH sessions across the app.
@Observable
final class SessionManager {
    private(set) var sessions: [ManagedSession] = []

    /// Create a new session for a host. Always opens SSH (needed for SFTP/helper/forwards).
    /// When host.preferredTransport is .mosh, the MoshSessionBridge will be created
    /// after SSH bootstrap completes and mosh-server is started.
    func createSession(host: HostRecord) -> ManagedSession {
        let sshSession = LibSSH2Session()
        let bridge = TerminalSessionBridge(sessionID: sshSession.sessionID, sshSession: sshSession)
        let managed = ManagedSession(
            hostAlias: host.alias,
            hostname: host.hostname,
            port: host.port,
            transportType: host.preferredTransport,
            sshSession: sshSession,
            bridge: bridge
        )
        sessions.append(managed)
        return managed
    }

    /// Remove a session after disconnect.
    func removeSession(id: String) {
        sessions.removeAll { $0.id == id }
    }

    /// Find a session by ID.
    func session(id: String) -> ManagedSession? {
        sessions.first { $0.id == id }
    }

    /// Disconnect all sessions.
    func disconnectAll() async {
        for session in sessions {
            await session.bridge.disconnect()
        }
        sessions.removeAll()
    }
}

/// A tracked SSH session with its bridge and helper client.
@Observable
final class ManagedSession: Identifiable {
    let id: String
    let hostAlias: String
    let hostname: String
    let port: Int
    let transportType: TransportType
    let sshSession: LibSSH2Session
    let bridge: any TerminalSessionBridgeProtocol
    var helperClient: (any HelperClientProtocol)?
    var forwardService: LocalForwardService?
    var sftpChannel: SFTPChannel?
    var isHelperAvailable = false
    var helperDetectionResult: HelperDetectionResult?

    init(hostAlias: String, hostname: String, port: Int, transportType: TransportType = .ssh, sshSession: LibSSH2Session, bridge: any TerminalSessionBridgeProtocol) {
        self.id = sshSession.sessionID
        self.hostAlias = hostAlias
        self.hostname = hostname
        self.port = port
        self.transportType = transportType
        self.sshSession = sshSession
        self.bridge = bridge
    }
}
