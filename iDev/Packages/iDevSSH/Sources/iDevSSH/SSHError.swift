import Foundation

/// Errors from the SSH transport layer.
public enum SSHError: Error, LocalizedError, Sendable {
    case notConnected
    case alreadyConnected
    case connectionFailed(String)
    case handshakeFailed(String)
    case authenticationFailed(String)
    case channelOpenFailed(String)
    case channelError(String)
    case forwardFailed(String)
    case sftpError(String)
    case hostKeyUnavailable
    case socketError(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to SSH server"
        case .alreadyConnected: "Already connected"
        case .connectionFailed(let msg): "Connection failed: \(msg)"
        case .handshakeFailed(let msg): "SSH handshake failed: \(msg)"
        case .authenticationFailed(let msg): "Authentication failed: \(msg)"
        case .channelOpenFailed(let msg): "Channel open failed: \(msg)"
        case .channelError(let msg): "Channel error: \(msg)"
        case .forwardFailed(let msg): "Forward failed: \(msg)"
        case .sftpError(let msg): "SFTP error: \(msg)"
        case .hostKeyUnavailable: "Host key not available"
        case .socketError(let msg): "Socket error: \(msg)"
        case .timeout: "Operation timed out"
        }
    }
}
