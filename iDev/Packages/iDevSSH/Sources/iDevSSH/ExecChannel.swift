import Foundation
import CSSH2

/// One-shot exec channel for running a single command.
public final class ExecChannel: @unchecked Sendable {
    public let channelID: String

    private var channel: OpaquePointer? // LIBSSH2_CHANNEL*
    private let session: OpaquePointer  // LIBSSH2_SESSION*
    private let queue: DispatchQueue
    private let closedLock = NSLock()
    private var _closed = false
    private var isClosed: Bool {
        closedLock.withLock { _closed }
    }

    init(channel: OpaquePointer, session: OpaquePointer, queue: DispatchQueue) {
        self.channelID = UUID().uuidString
        self.channel = channel
        self.session = session
        self.queue = queue
    }

    deinit {
        if let ch = channel {
            libssh2_channel_close(ch)
            libssh2_channel_free(ch)
        }
    }

    /// Write data to the command's stdin.
    public func write(_ data: Data) async throws {
        guard !isClosed else {
            throw SSHError.channelError("Channel closed")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let ch = self.channel else {
                    continuation.resume(throwing: SSHError.channelError("Channel closed"))
                    return
                }
                data.withUnsafeBytes { buffer in
                    guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                        continuation.resume()
                        return
                    }
                    var totalWritten = 0
                    let count = buffer.count

                    libssh2_channel_set_blocking(ch, 1)
                    defer { libssh2_channel_set_blocking(ch, 0) }

                    while totalWritten < count {
                        let written = libssh2_channel_write_ex(
                            ch,
                            0,
                            ptr.advanced(by: totalWritten),
                            count - totalWritten
                        )
                        if written < 0 {
                            continuation.resume(throwing: SSHError.channelError(
                                "Write failed: \(LibSSH2Session.sessionError(self.session) ?? "code \(written)")"
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

    /// Signal EOF on stdin.
    public func sendEOF() async throws {
        guard !isClosed else {
            throw SSHError.channelError("Channel closed")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let ch = self.channel else {
                    continuation.resume(throwing: SSHError.channelError("Channel closed"))
                    return
                }
                libssh2_channel_set_blocking(ch, 1)
                let result = libssh2_channel_send_eof(ch)
                libssh2_channel_set_blocking(ch, 0)
                if result == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SSHError.channelError("send_eof failed: \(result)"))
                }
            }
        }
    }

    /// Read stdout from the command.
    public func readStdout() -> AsyncThrowingStream<Data, Error> {
        readStream(streamID: 0)
    }

    /// Read stderr from the command.
    public func readStderr() -> AsyncThrowingStream<Data, Error> {
        readStream(streamID: Int32(SSH_EXTENDED_DATA_STDERR))
    }

    private func readStream(streamID: Int32) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            queue.async { [weak self] in
                guard let self, let ch = self.channel else {
                    continuation.finish()
                    return
                }

                let bufferSize = 32_768
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }

                while !self.isClosed {
                    let bytesRead = Int(libssh2_channel_read_ex(ch, streamID, buffer, bufferSize))

                    if bytesRead > 0 {
                        let data = Data(bytes: buffer, count: bytesRead)
                        continuation.yield(data)
                    } else if bytesRead == Int(LIBSSH2_ERROR_EAGAIN) {
                        Thread.sleep(forTimeInterval: 0.01)
                    } else if bytesRead == 0 {
                        if libssh2_channel_eof(ch) != 0 {
                            continuation.finish()
                            return
                        }
                        Thread.sleep(forTimeInterval: 0.01)
                    } else {
                        let msg = LibSSH2Session.sessionError(self.session) ?? "code \(bytesRead)"
                        continuation.finish(throwing: SSHError.channelError("Read failed: \(msg)"))
                        return
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Wait for the remote process to exit. Returns exit code.
    public func waitForExit() async throws -> Int32 {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let ch = self.channel else {
                    continuation.resume(throwing: SSHError.channelError("Channel closed"))
                    return
                }
                libssh2_channel_set_blocking(ch, 1)
                libssh2_channel_wait_eof(ch)
                libssh2_channel_wait_closed(ch)
                let exitCode = libssh2_channel_get_exit_status(ch)
                libssh2_channel_set_blocking(ch, 0)
                continuation.resume(returning: exitCode)
            }
        }
    }

    /// Close the channel.
    public func close() async {
        closedLock.withLock { _closed = true }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if let ch = self.channel {
                    libssh2_channel_set_blocking(ch, 1)
                    libssh2_channel_send_eof(ch)
                    libssh2_channel_close(ch)
                    libssh2_channel_free(ch)
                    self.channel = nil
                }
                continuation.resume()
            }
        }
    }
}
