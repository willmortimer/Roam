import Foundation
import RoamSSH

/// Decouples the SwiftTerm TerminalView from SSH transport.
/// The TerminalView delegate calls flow into this bridge, and the bridge
/// routes data to/from the SSH shell channel.
nonisolated protocol TerminalSessionBridgeProtocol: AnyObject {
    var sessionID: String { get }
    var connectionState: SSHSessionState { get }

    /// Called by TerminalViewDelegate.send() — user typed something.
    func sendToRemote(_ data: Data) async throws

    /// Stream of data arriving from remote — fed into terminal.feed().
    func remoteDataStream() -> AsyncThrowingStream<Data, Error>

    /// Resize the remote PTY.
    func resizePTY(columns: Int, rows: Int) async throws

    /// Disconnect the session.
    func disconnect() async

    /// Attach a shell channel after connection + auth succeed.
    /// Default no-op for transports that don't use ShellChannel (e.g. Mosh).
    func attachShell(_ channel: ShellChannel)
}

extension TerminalSessionBridgeProtocol {
    func attachShell(_ channel: ShellChannel) {}
}
