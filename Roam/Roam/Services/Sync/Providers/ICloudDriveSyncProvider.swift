import Foundation
import CryptoKit

/// Syncs encrypted blobs via iCloud Drive using FileManager's ubiquity container.
nonisolated final class ICloudDriveSyncProvider: SyncProvider {
    let name = "iCloud Drive"

    private let containerID: String?

    init(containerID: String? = nil) {
        self.containerID = containerID
    }

    private func syncDirectory() throws -> URL {
        guard let baseURL = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            throw SyncError.iCloudUnavailable
        }
        let syncDir = baseURL.appendingPathComponent("Documents/sync", isDirectory: true)
        if !FileManager.default.fileExists(atPath: syncDir.path) {
            try FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
        }
        return syncDir
    }

    private func fileURL(for key: String) throws -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
        let hex = hash.compactMap { String(format: "%02x", $0) }.joined()
        return try syncDirectory().appendingPathComponent("\(hex).roamblob")
    }

    func upload(blob: Data, key: String) async throws {
        let url = try fileURL(for: key)
        try blob.write(to: url, options: .atomic)
    }

    func download(key: String) async throws -> Data {
        let url = try fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyncError.notFound(key)
        }
        return try Data(contentsOf: url)
    }

    func listKeys() async throws -> [String] {
        let dir = try syncDirectory()
        let contents = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        return contents
            .filter { $0.pathExtension == "roamblob" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    func delete(key: String) async throws {
        let url = try fileURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case iCloudUnavailable
    case notFound(String)
    case invalidResponse(Int)
    case missingCredentials
    case gitError(String)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            "iCloud Drive is not available. Make sure you're signed into iCloud."
        case .notFound(let key):
            "Sync data not found: \(key)"
        case .invalidResponse(let code):
            "Server returned status \(code)"
        case .missingCredentials:
            "Missing credentials for sync provider"
        case .gitError(let msg):
            "Git sync error: \(msg)"
        }
    }
}
