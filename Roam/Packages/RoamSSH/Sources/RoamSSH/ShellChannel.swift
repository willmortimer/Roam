import Foundation
import CSSH2

/// Interactive shell channel connected to a PTY.
public final class ShellChannel: @unchecked Sendable {
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

    /// Write data to the remote shell's stdin.
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

    /// Returns an async stream of data received from the shell.
    public func read() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            self.scheduleRead(continuation: continuation)
        }
    }

    /// Resize the PTY.
    public func resize(columns: Int, rows: Int) async throws {
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
                let result = libssh2_channel_request_pty_size_ex(ch, Int32(columns), Int32(rows), 0, 0)
                libssh2_channel_set_blocking(ch, 0)

                if result == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SSHError.channelError(
                        "PTY resize failed: \(LibSSH2Session.sessionError(self.session) ?? "code \(result)")"
                    ))
                }
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

    private func scheduleRead(
        continuation: AsyncThrowingStream<Data, Error>.Continuation,
        delay: TimeInterval = 0
    ) {
        if delay > 0 {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pumpRead(continuation: continuation)
            }
        } else {
            queue.async { [weak self] in
                self?.pumpRead(continuation: continuation)
            }
        }
    }

    private func pumpRead(continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        guard !isClosed, let ch = channel else {
            continuation.finish()
            return
        }

        let bufferSize = 32_768
        let maxBurstReads = 16
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var burstReads = 0
        while burstReads < maxBurstReads, !isClosed {
            let bytesRead = libssh2_channel_read_ex(ch, 0, buffer, bufferSize)

            if bytesRead > 0 {
                let data = Data(bytes: buffer, count: Int(bytesRead))
                continuation.yield(data)
                burstReads += 1
                continue
            }

            if bytesRead == Int(LIBSSH2_ERROR_EAGAIN) {
                scheduleRead(continuation: continuation, delay: 0.01)
                return
            }

            if bytesRead == 0 {
                if libssh2_channel_eof(ch) != 0 {
                    continuation.finish()
                } else {
                    scheduleRead(continuation: continuation, delay: 0.01)
                }
                return
            }

            let msg = LibSSH2Session.sessionError(session) ?? "code \(bytesRead)"
            continuation.finish(throwing: SSHError.channelError("Read failed: \(msg)"))
            return
        }

        scheduleRead(continuation: continuation)
    }
}
