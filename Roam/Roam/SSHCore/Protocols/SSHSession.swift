import Foundation

// MARK: - SSH Session Protocol

/// Represents a single SSH connection with multiplexed channels.
nonisolated protocol SSHSessionProtocol: AnyObject, Sendable {
    var sessionID: String { get }
    var hostRecord: HostRecord { get }
    var state: SSHSessionState { get }

    func connect() async throws
    func disconnect() async
    func authenticate(with credential: SSHCredential) async throws

    // Channel creation
    func openShellChannel(pty: PTYRequest) async throws -> any SSHShellChannel
    func openExecChannel(command: String) async throws -> any SSHExecChannel
    func openSFTPChannel() async throws -> any SSHSFTPChannel

    // Port forwarding
    func openLocalForward(_ forward: ForwardDefinition) async throws -> any SSHForward
    func closeForward(_ forward: any SSHForward) async throws

    // Known hosts
    func serverHostKey() throws -> SSHHostKey
}

// MARK: - Session State

enum SSHSessionState: Sendable, Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(String)
}

// MARK: - PTY Request

struct PTYRequest: Sendable {
    var term: String
    var columns: Int
    var rows: Int

    init(term: String = "xterm-256color", columns: Int = 80, rows: Int = 24) {
        self.term = term
        self.columns = columns
        self.rows = rows
    }
}

// MARK: - Host Key

struct SSHHostKey: Sendable {
    var algorithm: String
    var fingerprint: String
    var rawKey: Data
}

// MARK: - Credential

struct SSHCredential: Sendable {
    enum Method: Sendable {
        case privateKey(data: Data, passphrase: String?)
        case password(String)
    }

    var method: Method
}
