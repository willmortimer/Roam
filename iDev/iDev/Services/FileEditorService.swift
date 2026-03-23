import Foundation
import Observation
import iDevSSH

/// Loads and saves text files via SFTP for the lightweight editor.
/// Size-limited to 2 MB to keep memory use reasonable on iOS.
@Observable
final class FileEditorService {
    static let maxFileSize: UInt64 = 2 * 1024 * 1024  // 2 MB

    var isLoading = false
    var isSaving = false
    var content = ""
    var isDirty = false
    var errorMessage: String?

    var filePath: String?
    var fileSize: UInt64 = 0
    var isReadOnly = false

    /// Load a file from the remote host via SFTP.
    func loadFile(path: String, sftpChannel: SFTPChannel) async {
        isLoading = true
        errorMessage = nil
        filePath = path

        do {
            let attrs = try await sftpChannel.stat(path: path)
            fileSize = attrs.size

            if attrs.size > Self.maxFileSize {
                isReadOnly = true
                errorMessage = "File is \(formatBytes(attrs.size)) — opened read-only (limit: 2 MB)"
            }

            var data = Data()
            for try await chunk in sftpChannel.download(remotePath: path) {
                data.append(chunk)
                if data.count > Int(Self.maxFileSize) + 1024 {
                    // Stop reading beyond limit + small buffer
                    break
                }
            }

            if let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                content = ""
                isReadOnly = true
                errorMessage = "File does not appear to be UTF-8 text"
            }

            isDirty = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Save the current content back to the remote file.
    func saveFile(sftpChannel: SFTPChannel) async {
        guard let path = filePath, !isReadOnly else { return }
        guard let data = content.data(using: .utf8) else {
            errorMessage = "Failed to encode content as UTF-8"
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            try await sftpChannel.upload(remotePath: path, content: data)
            isDirty = false
            fileSize = UInt64(data.count)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
