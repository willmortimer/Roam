import Foundation
import CryptoKit
import CSSH2

// MARK: - Session State

public enum SessionState: Sendable, Equatable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(String)
}

// MARK: - PTY Config

public struct PTYConfig: Sendable {
    public var term: String
    public var columns: Int
    public var rows: Int

    public init(term: String = "xterm-256color", columns: Int = 80, rows: Int = 24) {
        self.term = term
        self.columns = columns
        self.rows = rows
    }
}

// MARK: - Host Key Info

public struct HostKeyInfo: Sendable {
    public var algorithm: String
    public var fingerprint: String
    public var rawKey: Data
}

// MARK: - Auth Credential

public struct AuthCredential: Sendable {
    public enum GeneratedKey: Sendable {
        case ed25519(publicKey: Data, privateKey: Data)
        case ecdsaP256(publicKey: Data, privateKey: Data)
    }

    public enum Method: Sendable {
        case privateKey(data: Data, passphrase: String?)
        case generatedKey(GeneratedKey)
        case password(String)
    }
    public var username: String
    public var method: Method

    public init(username: String, method: Method) {
        self.username = username
        self.method = method
    }
}

// MARK: - Forward Definition

public struct ForwardDef: Sendable {
    public var localPort: Int?
    public var remoteHost: String
    public var remotePort: Int

    public init(localPort: Int? = nil, remoteHost: String = "127.0.0.1", remotePort: Int) {
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
}

// MARK: - LibSSH2 Session

/// Thread-safe SSH session backed by libssh2.
/// All blocking I/O runs on a dedicated dispatch queue.
public final class LibSSH2Session: @unchecked Sendable {
    public let sessionID: String

    // libssh2 state — only accessed on `queue`
    private var rawSession: OpaquePointer? // LIBSSH2_SESSION*
    private var socketFD: Int32 = -1
    let queue = DispatchQueue(label: "dev.roam.ssh.session", qos: .userInitiated)

    // Observable state — atomic via lock
    private let stateLock = NSLock()
    private var _state: SessionState = .disconnected
    public var state: SessionState {
        stateLock.withLock { _state }
    }
    private func setState(_ newState: SessionState) {
        stateLock.withLock { _state = newState }
    }

    public init(sessionID: String = UUID().uuidString) {
        self.sessionID = sessionID
    }

    deinit {
        if let session = rawSession {
            libssh2_session_disconnect_ex(
                session,
                Int32(SSH_DISCONNECT_BY_APPLICATION),
                "Client disconnecting",
                ""
            )
            libssh2_session_free(session)
        }
        if socketFD >= 0 {
            Darwin.close(socketFD)
        }
    }

    // MARK: - Connect

    public func connect(hostname: String, port: Int) async throws {
        guard state == .disconnected else {
            throw SSHError.alreadyConnected
        }
        setState(.connecting)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    let initResult = libssh2_init(0)
                    guard initResult == 0 else {
                        throw SSHError.connectionFailed("libssh2_init failed: \(initResult)")
                    }

                    let fd = try Self.createSocket(hostname: hostname, port: port)
                    self.socketFD = fd

                    guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
                        throw SSHError.connectionFailed("libssh2_session_init returned nil")
                    }
                    self.rawSession = session

                    libssh2_session_set_blocking(session, 1)
                    libssh2_session_set_timeout(session, 30_000)

                    let hsResult = libssh2_session_handshake(session, fd)
                    guard hsResult == 0 else {
                        let msg = Self.sessionError(session) ?? "code \(hsResult)"
                        throw SSHError.handshakeFailed(msg)
                    }

                    self.setState(.authenticating)
                    continuation.resume()
                } catch {
                    self.setState(.error(error.localizedDescription))
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Authenticate

    public func authenticate(credential: AuthCredential) async throws {
        guard let session = rawSession else {
            throw SSHError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    let username = credential.username
                    switch credential.method {
                    case .password(let password):
                        let result = libssh2_userauth_password_ex(
                            session,
                            username,
                            UInt32(username.utf8.count),
                            password,
                            UInt32(password.utf8.count),
                            nil
                        )
                        guard result == 0 else {
                            let msg = Self.sessionError(session) ?? "code \(result)"
                            throw SSHError.authenticationFailed(msg)
                        }

                    case .privateKey(let keyData, let passphrase):
                        try self.authenticateWithKey(
                            session: session,
                            username: username,
                            keyData: keyData,
                            passphrase: passphrase
                        )

                    case .generatedKey(let key):
                        try self.authenticateWithGeneratedKey(
                            session: session,
                            username: username,
                            key: key
                        )
                    }

                    self.setState(.connected)
                    continuation.resume()
                } catch {
                    self.setState(.error(error.localizedDescription))
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func authenticateWithKey(
        session: OpaquePointer,
        username: String,
        keyData: Data,
        passphrase: String?
    ) throws {
        let result = keyData.withUnsafeBytes { keyBytes -> Int32 in
            let keyPtr = keyBytes.baseAddress?.assumingMemoryBound(to: CChar.self)
            let keyLen = keyBytes.count
            let pass = passphrase ?? ""
            return libssh2_userauth_publickey_frommemory(
                session,
                username,
                username.utf8.count,
                nil,
                0,
                keyPtr,
                keyLen,
                pass
            )
        }

        guard result == 0 else {
            let msg = Self.sessionError(session) ?? "code \(result)"
            throw SSHError.authenticationFailed(msg)
        }
    }

    private func authenticateWithGeneratedKey(
        session: OpaquePointer,
        username: String,
        key: AuthCredential.GeneratedKey
    ) throws {
        let context = GeneratedKeySignContext(key: key)
        let retainedContext = Unmanaged.passRetained(context)
        var abstract: UnsafeMutableRawPointer? = retainedContext.toOpaque()

        let result = key.publicKeyBlob.withUnsafeBytes { publicKeyBytes -> Int32 in
            guard let publicKeyPtr = publicKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED
            }

            return username.withCString { usernamePtr in
                libssh2_userauth_publickey(
                    session,
                    usernamePtr,
                    publicKeyPtr,
                    publicKeyBytes.count,
                    roamSSHPublickeySignCallback,
                    &abstract
                )
            }
        }

        retainedContext.release()

        guard result == 0 else {
            let msg = Self.sessionError(session) ?? "code \(result)"
            throw SSHError.authenticationFailed(msg)
        }
    }

    // MARK: - Host Key

    public func hostKey() throws -> HostKeyInfo {
        guard let session = rawSession else {
            throw SSHError.notConnected
        }

        var keyLen: Int = 0
        var keyType: Int32 = 0
        guard let keyPtr = libssh2_session_hostkey(session, &keyLen, &keyType) else {
            throw SSHError.hostKeyUnavailable
        }

        let rawKey = Data(bytes: keyPtr, count: keyLen)

        let hashPtr = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_SHA256)
        let fingerprint: String
        if let hashPtr {
            let hashData = Data(bytes: hashPtr, count: 32)
            fingerprint = "SHA256:" + hashData.base64EncodedString()
        } else {
            if let md5Ptr = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_MD5) {
                let md5Data = Data(bytes: md5Ptr, count: 16)
                fingerprint = md5Data.map { String(format: "%02x", $0) }.joined(separator: ":")
            } else {
                fingerprint = "unknown"
            }
        }

        let algorithm: String
        switch keyType {
        case LIBSSH2_HOSTKEY_TYPE_RSA: algorithm = "ssh-rsa"
        case LIBSSH2_HOSTKEY_TYPE_DSS: algorithm = "ssh-dss"
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_256: algorithm = "ecdsa-sha2-nistp256"
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_384: algorithm = "ecdsa-sha2-nistp384"
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_521: algorithm = "ecdsa-sha2-nistp521"
        case LIBSSH2_HOSTKEY_TYPE_ED25519: algorithm = "ssh-ed25519"
        default: algorithm = "unknown"
        }

        return HostKeyInfo(algorithm: algorithm, fingerprint: fingerprint, rawKey: rawKey)
    }

    // MARK: - Shell Channel

    public func openShell(pty: PTYConfig = PTYConfig()) async throws -> ShellChannel {
        guard let session = rawSession else {
            throw SSHError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let channel = libssh2_channel_open_ex(
                        session,
                        "session",
                        7, // strlen("session")
                        UInt32(2_097_152 /* LIBSSH2_CHANNEL_WINDOW_DEFAULT */),
                        UInt32(32_768 /* LIBSSH2_CHANNEL_PACKET_DEFAULT */),
                        nil, 0
                    ) else {
                        let msg = Self.sessionError(session) ?? "unknown"
                        throw SSHError.channelOpenFailed(msg)
                    }

                    let ptyResult = libssh2_channel_request_pty_ex(
                        channel,
                        pty.term,
                        UInt32(pty.term.utf8.count),
                        nil, 0,
                        Int32(pty.columns),
                        Int32(pty.rows),
                        0, 0
                    )
                    guard ptyResult == 0 else {
                        libssh2_channel_free(channel)
                        let msg = Self.sessionError(session) ?? "code \(ptyResult)"
                        throw SSHError.channelOpenFailed("PTY request failed: \(msg)")
                    }

                    // shell = process_startup("shell", nil)
                    let shellResult = libssh2_channel_process_startup(
                        channel,
                        "shell",
                        5, // strlen("shell")
                        nil,
                        0
                    )
                    guard shellResult == 0 else {
                        libssh2_channel_free(channel)
                        let msg = Self.sessionError(session) ?? "code \(shellResult)"
                        throw SSHError.channelOpenFailed("Shell request failed: \(msg)")
                    }

                    libssh2_channel_set_blocking(channel, 0)

                    let shellChannel = ShellChannel(
                        channel: channel,
                        session: session,
                        queue: self.queue
                    )
                    continuation.resume(returning: shellChannel)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Exec Channel

    public func openExec(command: String) async throws -> ExecChannel {
        guard let session = rawSession else {
            throw SSHError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let channel = libssh2_channel_open_ex(
                        session,
                        "session",
                        7,
                        UInt32(2_097_152 /* LIBSSH2_CHANNEL_WINDOW_DEFAULT */),
                        UInt32(32_768 /* LIBSSH2_CHANNEL_PACKET_DEFAULT */),
                        nil, 0
                    ) else {
                        let msg = Self.sessionError(session) ?? "unknown"
                        throw SSHError.channelOpenFailed(msg)
                    }

                    // exec = process_startup("exec", command)
                    let execResult = libssh2_channel_process_startup(
                        channel,
                        "exec",
                        4, // strlen("exec")
                        command,
                        UInt32(command.utf8.count)
                    )
                    guard execResult == 0 else {
                        libssh2_channel_free(channel)
                        let msg = Self.sessionError(session) ?? "code \(execResult)"
                        throw SSHError.channelOpenFailed("Exec failed: \(msg)")
                    }

                    libssh2_channel_set_blocking(channel, 0)

                    let execChannel = ExecChannel(
                        channel: channel,
                        session: session,
                        queue: self.queue
                    )
                    continuation.resume(returning: execChannel)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Direct TCP/IP

    public func openDirectTCPIP(remoteHost: String, remotePort: Int) async throws -> DirectTCPIPChannel {
        guard let session = rawSession else {
            throw SSHError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    libssh2_session_set_blocking(session, 1)

                    guard let channel = libssh2_channel_direct_tcpip_ex(
                        session,
                        remoteHost,
                        Int32(remotePort),
                        "127.0.0.1",
                        22
                    ) else {
                        let msg = Self.sessionError(session) ?? "unknown"
                        throw SSHError.forwardFailed(msg)
                    }

                    libssh2_channel_set_blocking(channel, 0)

                    let directChannel = DirectTCPIPChannel(
                        channel: channel,
                        session: session,
                        queue: self.queue,
                        remoteHost: remoteHost,
                        remotePort: remotePort
                    )
                    continuation.resume(returning: directChannel)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - SFTP

    public func openSFTP() async throws -> SFTPChannel {
        guard let session = rawSession else {
            throw SSHError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    libssh2_session_set_blocking(session, 1)

                    guard let sftp = libssh2_sftp_init(session) else {
                        libssh2_session_set_blocking(session, 0)
                        let msg = Self.sessionError(session) ?? "unknown"
                        throw SSHError.sftpError("SFTP init failed: \(msg)")
                    }

                    libssh2_session_set_blocking(session, 0)

                    let sftpChannel = SFTPChannel(
                        sftp: sftp,
                        session: session,
                        queue: self.queue
                    )
                    continuation.resume(returning: sftpChannel)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Disconnect

    public func disconnect() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if let session = self.rawSession {
                    libssh2_session_disconnect_ex(
                        session,
                        Int32(SSH_DISCONNECT_BY_APPLICATION),
                        "Client disconnecting",
                        ""
                    )
                    libssh2_session_free(session)
                    self.rawSession = nil
                }
                if self.socketFD >= 0 {
                    Darwin.close(self.socketFD)
                    self.socketFD = -1
                }
                libssh2_exit()
                self.setState(.disconnected)
                continuation.resume()
            }
        }
    }

    // MARK: - Keepalive

    public func sendKeepalive() async -> Int {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let session = self.rawSession else {
                    continuation.resume(returning: 0)
                    return
                }
                var secondsToNext: Int32 = 0
                libssh2_keepalive_send(session, &secondsToNext)
                continuation.resume(returning: Int(secondsToNext))
            }
        }
    }

    public func configureKeepalive(wantReply: Bool = true, interval: Int = 15) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                guard let session = self.rawSession else {
                    continuation.resume()
                    return
                }
                libssh2_keepalive_config(session, wantReply ? 1 : 0, UInt32(interval))
                continuation.resume()
            }
        }
    }

    // MARK: - Socket Helpers

    private static func createSocket(hostname: String, port: Int) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        let status = getaddrinfo(hostname, portStr, &hints, &result)
        guard status == 0, let addrList = result else {
            let msg = String(cString: gai_strerror(status))
            throw SSHError.socketError("DNS resolution failed: \(msg)")
        }
        defer { freeaddrinfo(addrList) }

        var current: UnsafeMutablePointer<addrinfo>? = addrList
        while let addr = current {
            let fd = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
            if fd >= 0 {
                if Darwin.connect(fd, addr.pointee.ai_addr, addr.pointee.ai_addrlen) == 0 {
                    return fd
                }
                Darwin.close(fd)
            }
            current = addr.pointee.ai_next
        }

        throw SSHError.socketError("Could not connect to \(hostname):\(port)")
    }

    static func sessionError(_ session: OpaquePointer) -> String? {
        var msgPtr: UnsafeMutablePointer<CChar>?
        var msgLen: Int32 = 0
        libssh2_session_last_error(session, &msgPtr, &msgLen, 0)
        if let msgPtr, msgLen > 0 {
            return String(cString: msgPtr)
        }
        return nil
    }
}

private final class GeneratedKeySignContext {
    let key: AuthCredential.GeneratedKey

    init(key: AuthCredential.GeneratedKey) {
        self.key = key
    }
}

@_cdecl("roamSSHPublickeySignCallback")
private func roamSSHPublickeySignCallback(
    session: OpaquePointer?,
    signature: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
    signatureLength: UnsafeMutablePointer<Int>?,
    data: UnsafePointer<UInt8>?,
    dataLength: Int,
    abstract: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> Int32 {
    guard session != nil,
          let signature,
          let signatureLength,
          let data,
          let abstract,
          let contextPointer = abstract.pointee else {
        return LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED
    }

    let context = Unmanaged<GeneratedKeySignContext>.fromOpaque(contextPointer).takeUnretainedValue()

    do {
        let payload = Data(bytes: data, count: dataLength)
        let signedPayload = try context.key.signature(for: payload)
        guard let allocatedSignature = malloc(signedPayload.count)?.assumingMemoryBound(to: UInt8.self) else {
            return LIBSSH2_ERROR_ALLOC
        }

        signedPayload.copyBytes(to: allocatedSignature, count: signedPayload.count)
        signature.pointee = allocatedSignature
        signatureLength.pointee = signedPayload.count
        return 0
    } catch {
        return LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED
    }
}

private extension AuthCredential.GeneratedKey {
    var publicKeyBlob: Data {
        switch self {
        case .ed25519(let publicKey, _):
            var blob = Data()
            blob.appendSSHString(Data("ssh-ed25519".utf8))
            blob.appendSSHString(publicKey)
            return blob

        case .ecdsaP256(let publicKey, _):
            var blob = Data()
            blob.appendSSHString(Data("ecdsa-sha2-nistp256".utf8))
            blob.appendSSHString(Data("nistp256".utf8))
            blob.appendSSHString(publicKey)
            return blob
        }
    }

    func signature(for payload: Data) throws -> Data {
        switch self {
        case .ed25519(_, let privateKey):
            do {
                let signer = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
                return try signer.signature(for: payload)
            } catch {
                throw SSHError.authenticationFailed(
                    "The stored Ed25519 key is invalid. Regenerate or re-import it."
                )
            }

        case .ecdsaP256(_, let privateKey):
            do {
                let signer = try P256.Signing.PrivateKey(rawRepresentation: privateKey)
                let signature = try signer.signature(for: payload)
                return Self.ecdsaSignatureBlob(from: signature.rawRepresentation)
            } catch {
                throw SSHError.authenticationFailed(
                    "The stored P-256 key is invalid. Regenerate or re-import it."
                )
            }
        }
    }

    private static func ecdsaSignatureBlob(from rawSignature: Data) -> Data {
        let componentLength = rawSignature.count / 2
        let r = Data(rawSignature.prefix(componentLength))
        let s = Data(rawSignature.suffix(componentLength))

        var blob = Data()
        blob.appendSSHString(sshMPInt(from: r))
        blob.appendSSHString(sshMPInt(from: s))
        return blob
    }

    private static func sshMPInt(from unsigned: Data) -> Data {
        let trimmed = unsigned.drop(while: { $0 == 0 })
        guard !trimmed.isEmpty else {
            return Data()
        }

        var value = Data(trimmed)
        if value[0] & 0x80 != 0 {
            value.insert(0, at: 0)
        }
        return value
    }
}

private extension Data {
    mutating func appendSSHString(_ data: Data) {
        var length = UInt32(data.count).bigEndian
        append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
        append(data)
    }
}
