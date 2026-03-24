import Foundation

/// Protocol for zero-knowledge sync backends.
/// Providers only see opaque encrypted blobs — no plaintext data.
nonisolated protocol SyncProvider: Sendable {
    var name: String { get }
    func upload(blob: Data, key: String) async throws
    func download(key: String) async throws -> Data
    func listKeys() async throws -> [String]
    func delete(key: String) async throws
}

/// Configuration needed for each sync provider type.
enum SyncProviderType: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case iCloudDrive
    case git
    case webDAV
    case s3
    case selfHosted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .iCloudDrive: "iCloud Drive"
        case .git: "Git Repository"
        case .webDAV: "WebDAV"
        case .s3: "S3-Compatible"
        case .selfHosted: "Self-Hosted"
        }
    }

    var icon: String {
        switch self {
        case .none: "xmark.circle"
        case .iCloudDrive: "icloud"
        case .git: "arrow.triangle.branch"
        case .webDAV: "externaldrive.connected.to.line.below"
        case .s3: "cloud"
        case .selfHosted: "server.rack"
        }
    }
}
