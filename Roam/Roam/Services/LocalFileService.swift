import Foundation
import Observation

/// Manages the local Roam home directory in the app's documents folder,
/// with optional iCloud Drive sync via ubiquity container.
@Observable
final class LocalFileService {
    static let shared = LocalFileService()

    /// Whether iCloud Drive sync is enabled.
    var isICloudEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "localFiles_iCloudEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "localFiles_iCloudEnabled")
            _cachedHomeURL = nil
        }
    }

    /// The root URL for the Roam home directory.
    var homeDirectory: URL {
        if let cached = _cachedHomeURL { return cached }
        let url = resolveHomeDirectory()
        _cachedHomeURL = url
        return url
    }

    private var _cachedHomeURL: URL?

    private init() {
        ensureDefaultFolders()
    }

    // MARK: - Home Directory Resolution

    private func resolveHomeDirectory() -> URL {
        if isICloudEnabled, let ubiquityURL = iCloudContainerURL {
            let roamDir = ubiquityURL.appendingPathComponent("Documents/Roam", isDirectory: true)
            ensureDirectory(at: roamDir)
            return roamDir
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let roamDir = docs.appendingPathComponent("Roam", isDirectory: true)
        ensureDirectory(at: roamDir)
        return roamDir
    }

    /// The iCloud ubiquity container URL, if available.
    var iCloudContainerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    /// Whether iCloud is available on this device.
    var isICloudAvailable: Bool {
        iCloudContainerURL != nil
    }

    // MARK: - Default Folders

    private func ensureDefaultFolders() {
        let home = homeDirectory
        ensureDirectory(at: home.appendingPathComponent("Notes", isDirectory: true))
        ensureDirectory(at: home.appendingPathComponent("Downloads", isDirectory: true))
        ensureDirectory(at: home.appendingPathComponent("Scripts", isDirectory: true))
    }

    // MARK: - Directory Operations

    struct LocalFileEntry: Identifiable, Hashable {
        let id: String
        let name: String
        let url: URL
        let isDirectory: Bool
        let size: UInt64
        let modifiedDate: Date

        static func == (lhs: LocalFileEntry, rhs: LocalFileEntry) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    func listDirectory(at url: URL) throws -> [LocalFileEntry] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { itemURL in
            guard let values = try? itemURL.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            ) else { return nil }

            return LocalFileEntry(
                id: itemURL.absoluteString,
                name: itemURL.lastPathComponent,
                url: itemURL,
                isDirectory: values.isDirectory ?? false,
                size: UInt64(values.fileSize ?? 0),
                modifiedDate: values.contentModificationDate ?? Date()
            )
        }
    }

    func createDirectory(at parent: URL, name: String) throws {
        let newDir = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: false)
    }

    func deleteItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func renameItem(at url: URL, newName: String) throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: newURL)
        return newURL
    }

    func moveItem(from: URL, to: URL) throws {
        try FileManager.default.moveItem(at: from, to: to)
    }

    // MARK: - File Read/Write

    func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func writeFile(at url: URL, data: Data) throws {
        try data.write(to: url)
    }

    /// Save data to the Downloads folder, returning the destination URL.
    func saveToDownloads(data: Data, filename: String) throws -> URL {
        let downloadsDir = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        ensureDirectory(at: downloadsDir)
        let dest = downloadsDir.appendingPathComponent(filename)
        try data.write(to: dest)
        return dest
    }

    /// Create a new file in a directory and return its URL.
    func createFile(in directory: URL, name: String, content: Data = Data()) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL)
        return fileURL
    }

    // MARK: - Storage Info

    /// Approximate total size of the home directory.
    func homeDirectorySize() -> UInt64 {
        directorySize(at: homeDirectory)
    }

    private func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    // MARK: - Helpers

    private func ensureDirectory(at url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Relative path from home directory.
    func relativePath(for url: URL) -> String {
        let homePath = homeDirectory.path
        let itemPath = url.path
        if itemPath.hasPrefix(homePath) {
            let relative = String(itemPath.dropFirst(homePath.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return url.lastPathComponent
    }
}
