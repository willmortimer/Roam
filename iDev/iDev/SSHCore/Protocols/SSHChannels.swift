import Foundation

// MARK: - Shell Channel

/// Interactive shell channel connected to a PTY.
nonisolated protocol SSHShellChannel: AnyObject, Sendable {
    var channelID: String { get }
    func write(_ data: Data) async throws
    func read() -> AsyncThrowingStream<Data, Error>
    func resize(columns: Int, rows: Int) async throws
    func close() async
}

// MARK: - Exec Channel

/// One-shot exec channel for helper RPC or single commands.
nonisolated protocol SSHExecChannel: AnyObject, Sendable {
    var channelID: String { get }
    func write(_ data: Data) async throws
    func readStdout() -> AsyncThrowingStream<Data, Error>
    func readStderr() -> AsyncThrowingStream<Data, Error>
    func close() async
    func waitForExit() async throws -> Int32
}

// MARK: - SFTP Channel

/// SFTP subsystem channel.
nonisolated protocol SSHSFTPChannel: AnyObject, Sendable {
    func listDirectory(path: String) async throws -> [SFTPEntry]
    func download(remotePath: String) -> AsyncThrowingStream<Data, Error>
    func upload(remotePath: String, data: AsyncStream<Data>) async throws
    func stat(path: String) async throws -> SFTPAttributes
    func mkdir(path: String) async throws
    func rename(from: String, to: String) async throws
    func remove(path: String) async throws
    func close() async
}

// MARK: - SFTP Types

struct SFTPEntry: Sendable {
    var name: String
    var isDirectory: Bool
    var size: UInt64
    var modifiedDate: Date
    var permissions: UInt32
}

struct SFTPAttributes: Sendable {
    var size: UInt64
    var isDirectory: Bool
    var permissions: UInt32
    var modifiedDate: Date
    var owner: String?
}

// MARK: - Forward Handle

/// Active port forward handle.
nonisolated protocol SSHForward: AnyObject, Sendable {
    var forwardID: String { get }
    var localPort: Int { get }
    var remoteHost: String { get }
    var remotePort: Int { get }
    var isActive: Bool { get }
    func close() async
}
