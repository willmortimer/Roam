import Foundation
import RoamSSH

/// Concrete bridge connecting an RoamSSH ShellChannel to the terminal view.
/// Routes data bidirectionally between the TerminalView delegate and SSH.
nonisolated final class TerminalSessionBridge: TerminalSessionBridgeProtocol, @unchecked Sendable {
    let sessionID: String
    private let sshSession: LibSSH2Session
    private var shellChannel: ShellChannel?
    private let stateLock = NSLock()
    private var _connectionState: SSHSessionState = .disconnected

    /// Optional interceptor called when user sends a newline-terminated command.
    /// Used by the command timeline to record commands.
    var commandInterceptor: (@Sendable (String) -> Void)?

    /// Accumulates partial input to detect complete commands.
    private var inputBuffer = Data()
    private let inputBufferLock = NSLock()

    var connectionState: SSHSessionState {
        stateLock.withLock { _connectionState }
    }

    init(sessionID: String, sshSession: LibSSH2Session) {
        self.sessionID = sessionID
        self.sshSession = sshSession
    }

    /// Attach a shell channel after connection + auth succeed.
    func attachShell(_ channel: ShellChannel) {
        self.shellChannel = channel
        stateLock.withLock { _connectionState = .connected }
    }

    func sendToRemote(_ data: Data) async throws {
        guard let channel = shellChannel else {
            throw SSHError.notConnected
        }

        // Intercept potential commands for the timeline
        if let interceptor = commandInterceptor {
            interceptCommand(data: data, interceptor: interceptor)
        }

        try await channel.write(data)
    }

    /// Detects newline-terminated printable strings and reports them.
    private func interceptCommand(data: Data, interceptor: @Sendable (String) -> Void) {
        inputBufferLock.withLock {
            inputBuffer.append(data)

            // Check for newline (Enter key: \r or \n)
            if data.contains(0x0D) || data.contains(0x0A) {
                // Check if the accumulated buffer looks like a typed command
                // (printable ASCII, not just escape sequences)
                let commandData = inputBuffer.filter { $0 != 0x0D && $0 != 0x0A }
                if let command = String(data: commandData, encoding: .utf8),
                   !command.isEmpty,
                   command.allSatisfy({ $0.isPrintableASCII }) {
                    interceptor(command)
                }
                inputBuffer.removeAll()
            }

            // Clear buffer if it gets too large (likely binary/escape data)
            if inputBuffer.count > 4096 {
                inputBuffer.removeAll()
            }
        }
    }

    func remoteDataStream() -> AsyncThrowingStream<Data, Error> {
        guard let channel = shellChannel else {
            return AsyncThrowingStream { $0.finish() }
        }
        return channel.read()
    }

    func resizePTY(columns: Int, rows: Int) async throws {
        guard let channel = shellChannel else {
            throw SSHError.notConnected
        }
        try await channel.resize(columns: columns, rows: rows)
    }

    /// Reset the input buffer (e.g., on disconnect).
    func resetInputBuffer() {
        inputBufferLock.withLock { inputBuffer.removeAll() }
    }

    func disconnect() async {
        await shellChannel?.close()
        shellChannel = nil
        await sshSession.disconnect()
        stateLock.withLock { _connectionState = .disconnected }
    }
}

// MARK: - Character Extension

private extension Character {
    /// True for printable ASCII characters (space through tilde).
    nonisolated var isPrintableASCII: Bool {
        guard let ascii = asciiValue else { return false }
        return ascii >= 0x20 && ascii <= 0x7E
    }
}
