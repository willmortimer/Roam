import Foundation
import CSSH2

// MARK: - SFTP Types

public struct SFTPFileEntry: Sendable {
    public var name: String
    public var isDirectory: Bool
    public var size: UInt64
    public var modifiedDate: Date
    public var permissions: UInt32
}

public struct SFTPFileAttributes: Sendable {
    public var size: UInt64
    public var isDirectory: Bool
    public var permissions: UInt32
    public var modifiedDate: Date
    public var uid: UInt32
    public var gid: UInt32
}

// MARK: - SFTP Constants

// open_ex type parameter
private let kSFTPOpenFile: Int32 = 0  // LIBSSH2_SFTP_OPENFILE
private let kSFTPOpenDir: Int32 = 1   // LIBSSH2_SFTP_OPENDIR

// file transfer flags
private let kFXFRead: UInt = 0x00000001     // LIBSSH2_FXF_READ
private let kFXFWrite: UInt = 0x00000002    // LIBSSH2_FXF_WRITE
private let kFXFCreat: UInt = 0x00000008    // LIBSSH2_FXF_CREAT
private let kFXFTrunc: UInt = 0x00000010    // LIBSSH2_FXF_TRUNC

// stat type
private let kSFTPStat: Int32 = 0   // LIBSSH2_SFTP_STAT

// rename flags
private let kRenameOverwrite: Int = 0x00000001  // LIBSSH2_SFTP_RENAME_OVERWRITE
private let kRenameAtomic: Int = 0x00000002     // LIBSSH2_SFTP_RENAME_ATOMIC
private let kRenameNative: Int = 0x00000004     // LIBSSH2_SFTP_RENAME_NATIVE

// file type masks
private let kSFTPSIFMT: UInt = 0o170000   // LIBSSH2_SFTP_S_IFMT
private let kSFTPSIFDIR: UInt = 0o040000  // LIBSSH2_SFTP_S_IFDIR

// attribute flags
private let kAttrPermissions: UInt = 0x00000004  // LIBSSH2_SFTP_ATTR_PERMISSIONS
private let kAttrACModTime: UInt = 0x00000008    // LIBSSH2_SFTP_ATTR_ACMODTIME
private let kAttrSize: UInt = 0x00000001         // LIBSSH2_SFTP_ATTR_SIZE
private let kAttrUIDGID: UInt = 0x00000002       // LIBSSH2_SFTP_ATTR_UIDGID

// MARK: - SFTP Channel

/// SFTP subsystem channel for file transfer operations.
public final class SFTPChannel: @unchecked Sendable {

    private var sftp: OpaquePointer?     // LIBSSH2_SFTP*
    private let session: OpaquePointer   // LIBSSH2_SESSION*
    private let queue: DispatchQueue
    private let closedLock = NSLock()
    private var _closed = false
    private var isClosed: Bool {
        closedLock.withLock { _closed }
    }

    init(sftp: OpaquePointer, session: OpaquePointer, queue: DispatchQueue) {
        self.sftp = sftp
        self.session = session
        self.queue = queue
    }

    deinit {
        if let sftp {
            libssh2_sftp_shutdown(sftp)
        }
    }

    // MARK: - List Directory

    public func listDirectory(path: String) async throws -> [SFTPFileEntry] {
        guard !isClosed else {
            throw SSHError.sftpError("SFTP channel closed")
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let sftp = self.sftp else {
                    continuation.resume(throwing: SSHError.sftpError("SFTP channel closed"))
                    return
                }

                libssh2_session_set_blocking(self.session, 1)
                defer { libssh2_session_set_blocking(self.session, 0) }

                guard let handle = libssh2_sftp_open_ex(
                    sftp,
                    path,
                    UInt32(path.utf8.count),
                    0,  // flags (unused for opendir)
                    0,  // mode (unused for opendir)
                    kSFTPOpenDir
                ) else {
                    let err = libssh2_sftp_last_error(sftp)
                    continuation.resume(throwing: SSHError.sftpError(
                        "Failed to open directory: \(Self.sftpErrorMessage(err))"
                    ))
                    return
                }
                defer { libssh2_sftp_close_handle(handle) }

                var entries: [SFTPFileEntry] = []
                let nameBufferSize = 512
                let longEntrySize = 512
                let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: nameBufferSize)
                let longEntry = UnsafeMutablePointer<CChar>.allocate(capacity: longEntrySize)
                defer {
                    nameBuffer.deallocate()
                    longEntry.deallocate()
                }

                while true {
                    var attrs = _LIBSSH2_SFTP_ATTRIBUTES()
                    let rc = libssh2_sftp_readdir_ex(
                        handle,
                        nameBuffer,
                        nameBufferSize,
                        longEntry,
                        longEntrySize,
                        &attrs
                    )

                    if rc <= 0 {
                        break  // 0 = end of dir, negative = error
                    }

                    let name = String(cString: nameBuffer)
                    if name == "." || name == ".." {
                        continue
                    }

                    let isDir: Bool
                    if attrs.flags & kAttrPermissions != 0 {
                        isDir = (attrs.permissions & kSFTPSIFMT) == kSFTPSIFDIR
                    } else {
                        isDir = false
                    }

                    let size: UInt64
                    if attrs.flags & kAttrSize != 0 {
                        size = attrs.filesize
                    } else {
                        size = 0
                    }

                    let modDate: Date
                    if attrs.flags & kAttrACModTime != 0 {
                        modDate = Date(timeIntervalSince1970: TimeInterval(attrs.mtime))
                    } else {
                        modDate = Date.distantPast
                    }

                    let permissions: UInt32
                    if attrs.flags & kAttrPermissions != 0 {
                        permissions = UInt32(attrs.permissions)
                    } else {
                        permissions = 0
                    }

                    entries.append(SFTPFileEntry(
                        name: name,
                        isDirectory: isDir,
                        size: size,
                        modifiedDate: modDate,
                        permissions: permissions
                    ))
                }

                continuation.resume(returning: entries)
            }
        }
    }

    // MARK: - Download

    public func download(remotePath: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            queue.async { [weak self] in
                guard let self, let sftp = self.sftp else {
                    continuation.finish(throwing: SSHError.sftpError("SFTP channel closed"))
                    return
                }

                libssh2_session_set_blocking(self.session, 1)
                defer { libssh2_session_set_blocking(self.session, 0) }

                guard let handle = libssh2_sftp_open_ex(
                    sftp,
                    remotePath,
                    UInt32(remotePath.utf8.count),
                    UInt(kFXFRead),
                    0,
                    kSFTPOpenFile
                ) else {
                    let err = libssh2_sftp_last_error(sftp)
                    continuation.finish(throwing: SSHError.sftpError(
                        "Failed to open file: \(Self.sftpErrorMessage(err))"
                    ))
                    return
                }
                defer { libssh2_sftp_close_handle(handle) }

                let bufferSize = 32_768
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }

                while !self.isClosed {
                    let bytesRead = libssh2_sftp_read(handle, buffer, bufferSize)

                    if bytesRead > 0 {
                        let data = Data(bytes: buffer, count: Int(bytesRead))
                        continuation.yield(data)
                    } else if bytesRead == 0 {
                        // EOF
                        continuation.finish()
                        return
                    } else if bytesRead == Int(LIBSSH2_ERROR_EAGAIN) {
                        Thread.sleep(forTimeInterval: 0.01)
                    } else {
                        let err = libssh2_sftp_last_error(sftp)
                        continuation.finish(throwing: SSHError.sftpError(
                            "Read failed: \(Self.sftpErrorMessage(err))"
                        ))
                        return
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Upload

    public func upload(remotePath: String, data: AsyncStream<Data>) async throws {
        guard !isClosed else {
            throw SSHError.sftpError("SFTP channel closed")
        }

        // Collect all data chunks first since we need to write synchronously on the queue
        var allData = Data()
        for await chunk in data {
            allData.append(chunk)
        }

        let dataToWrite = allData  // Local copy for Sendable closure
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let sftp = self.sftp else {
                    continuation.resume(throwing: SSHError.sftpError("SFTP channel closed"))
                    return
                }

                libssh2_session_set_blocking(self.session, 1)
                defer { libssh2_session_set_blocking(self.session, 0) }

                let flags = kFXFWrite | kFXFCreat | kFXFTrunc
                guard let handle = libssh2_sftp_open_ex(
                    sftp,
                    remotePath,
                    UInt32(remotePath.utf8.count),
                    flags,
                    Int(0o644),
                    kSFTPOpenFile
                ) else {
                    let err = libssh2_sftp_last_error(sftp)
                    continuation.resume(throwing: SSHError.sftpError(
                        "Failed to open file for writing: \(Self.sftpErrorMessage(err))"
                    ))
                    return
                }
                defer { libssh2_sftp_close_handle(handle) }

                dataToWrite.withUnsafeBytes { buffer in
                    guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                        continuation.resume()
                        return
                    }

                    var totalWritten = 0
                    let count = buffer.count

                    while totalWritten < count {
                        let written = libssh2_sftp_write(
                            handle,
                            ptr.advanced(by: totalWritten),
                            count - totalWritten
                        )
                        if written < 0 {
                            let err = libssh2_sftp_last_error(sftp)
                            continuation.resume(throwing: SSHError.sftpError(
                                "Write failed: \(Self.sftpErrorMessage(err))"
                            ))
                            return
                        }
                        totalWritten += Int(written)
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Upload from Data (convenience)

    public func upload(remotePath: String, content: Data) async throws {
        let stream = AsyncStream<Data> { continuation in
            continuation.yield(content)
            continuation.finish()
        }
        try await upload(remotePath: remotePath, data: stream)
    }

    // MARK: - Stat

    public func stat(path: String) async throws -> SFTPFileAttributes {
        guard !isClosed else {
            throw SSHError.sftpError("SFTP channel closed")
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let sftp = self.sftp else {
                    continuation.resume(throwing: SSHError.sftpError("SFTP channel closed"))
                    return
                }

                libssh2_session_set_blocking(self.session, 1)
                defer { libssh2_session_set_blocking(self.session, 0) }

                var attrs = _LIBSSH2_SFTP_ATTRIBUTES()
                let rc = libssh2_sftp_stat_ex(
                    sftp,
                    path,
                    UInt32(path.utf8.count),
                    kSFTPStat,
                    &attrs
                )

                if rc != 0 {
                    let err = libssh2_sftp_last_error(sftp)
                    continuation.resume(throwing: SSHError.sftpError(
                        "Stat failed: \(Self.sftpErrorMessage(err))"
                    ))
                    return
                }

                let isDir = (attrs.flags & kAttrPermissions != 0)
                    && ((attrs.permissions & kSFTPSIFMT) == kSFTPSIFDIR)

                let fileAttrs = SFTPFileAttributes(
                    size: (attrs.flags & kAttrSize != 0) ? attrs.filesize : 0,
                    isDirectory: isDir,
                    permissions: (attrs.flags & kAttrPermissions != 0) ? UInt32(attrs.permissions) : 0,
                    modifiedDate: (attrs.flags & kAttrACModTime != 0)
                        ? Date(timeIntervalSince1970: TimeInterval(attrs.mtime)) : Date.distantPast,
                    uid: (attrs.flags & kAttrUIDGID != 0) ? UInt32(attrs.uid) : 0,
                    gid: (attrs.flags & kAttrUIDGID != 0) ? UInt32(attrs.gid) : 0
                )
                continuation.resume(returning: fileAttrs)
            }
        }
    }

    // MARK: - Mkdir

    public func mkdir(path: String, mode: Int = 0o755) async throws {
        guard !isClosed else {
            throw SSHError.sftpError("SFTP channel closed")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let sftp = self.sftp else {
                    continuation.resume(throwing: SSHError.sftpError("SFTP channel closed"))
                    return
                }

                libssh2_session_set_blocking(self.session, 1)
                defer { libssh2_session_set_blocking(self.session, 0) }

                let rc = libssh2_sftp_mkdir_ex(
                    sftp,
                    path,
                    UInt32(path.utf8.count),
                    Int(mode)
                )

                if rc != 0 {
                    let err = libssh2_sftp_last_error(sftp)
                    continuation.resume(throwing: SSHError.sftpError(
                        "Mkdir failed: \(Self.sftpErrorMessage(err))"
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Rename

    public func rename(from source: String, to dest: String) async throws {
        guard !isClosed else {
            throw SSHError.sftpError("SFTP channel closed")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let sftp = self.sftp else {
                    continuation.resume(throwing: SSHError.sftpError("SFTP channel closed"))
                    return
                }

                libssh2_session_set_blocking(self.session, 1)
                defer { libssh2_session_set_blocking(self.session, 0) }

                let flags = kRenameOverwrite | kRenameAtomic | kRenameNative
                let rc = libssh2_sftp_rename_ex(
                    sftp,
                    source,
                    UInt32(source.utf8.count),
                    dest,
                    UInt32(dest.utf8.count),
                    Int(flags)
                )

                if rc != 0 {
                    let err = libssh2_sftp_last_error(sftp)
                    continuation.resume(throwing: SSHError.sftpError(
                        "Rename failed: \(Self.sftpErrorMessage(err))"
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Remove

    public func remove(path: String) async throws {
        guard !isClosed else {
            throw SSHError.sftpError("SFTP channel closed")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let sftp = self.sftp else {
                    continuation.resume(throwing: SSHError.sftpError("SFTP channel closed"))
                    return
                }

                libssh2_session_set_blocking(self.session, 1)
                defer { libssh2_session_set_blocking(self.session, 0) }

                // Try unlink (file) first
                let rc = libssh2_sftp_unlink_ex(
                    sftp,
                    path,
                    UInt32(path.utf8.count)
                )

                if rc == 0 {
                    continuation.resume()
                    return
                }

                // If unlink failed, try rmdir (directory)
                let rc2 = libssh2_sftp_rmdir_ex(
                    sftp,
                    path,
                    UInt32(path.utf8.count)
                )

                if rc2 != 0 {
                    let err = libssh2_sftp_last_error(sftp)
                    continuation.resume(throwing: SSHError.sftpError(
                        "Remove failed: \(Self.sftpErrorMessage(err))"
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Close

    public func close() async {
        closedLock.withLock { _closed = true }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if let sftp = self.sftp {
                    libssh2_session_set_blocking(self.session, 1)
                    libssh2_sftp_shutdown(sftp)
                    libssh2_session_set_blocking(self.session, 0)
                    self.sftp = nil
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Error Helpers

    private static func sftpErrorMessage(_ code: UInt) -> String {
        switch code {
        case 0:  return "OK"
        case 1:  return "EOF"
        case 2:  return "No such file"
        case 3:  return "Permission denied"
        case 4:  return "Failure"
        case 5:  return "Bad message"
        case 6:  return "No connection"
        case 7:  return "Connection lost"
        case 8:  return "Operation unsupported"
        case 9:  return "Invalid handle"
        case 10: return "No such path"
        case 11: return "File already exists"
        case 12: return "Write protect"
        case 14: return "No space on filesystem"
        case 15: return "Quota exceeded"
        case 18: return "Directory not empty"
        case 19: return "Not a directory"
        case 20: return "Invalid filename"
        default: return "SFTP error \(code)"
        }
    }
}
