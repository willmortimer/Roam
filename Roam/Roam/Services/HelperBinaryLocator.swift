import CryptoKit
import Foundation

enum HelperBinaryLocator {
    static func binaryData(for arch: RemoteArch) async throws -> Data {
        let candidates = candidateURLs(for: arch)

        for url in candidates where FileManager.default.isReadableFile(atPath: url.path) {
            let data = try Data(contentsOf: url)
            if try validateCachedReleaseAssetIfNeeded(data: data, url: url, arch: arch) {
                return data
            }
        }

        if let releaseURL = releaseDownloadURL(for: arch) {
            do {
                return try await downloadReleaseAsset(
                    from: releaseURL,
                    checksumURL: releaseChecksumURL(for: arch),
                    cacheURL: cachedReleaseAssetURL(for: arch),
                    checksumCacheURL: cachedReleaseChecksumURL(for: arch)
                )
            } catch {
                throw HelperInstallError.binaryDownloadFailed(
                    arch: arch.rawValue,
                    searchedPaths: candidates.map(\.path),
                    releaseURL: releaseURL.absoluteString,
                    message: error.localizedDescription
                )
            }
        }

        throw HelperInstallError.binaryNotFound(
            arch: arch.rawValue,
            searchedPaths: candidates.map(\.path),
            releaseURL: nil
        )
    }

    private static func candidateURLs(for arch: RemoteArch) -> [URL] {
        var urls: [URL] = []
        let fileName = "roam-helper-\(arch.rawValue)"
        let releaseAssetFileName = releaseAssetFileName(for: arch)

        if let directBundleURL = Bundle.main.url(forResource: fileName, withExtension: nil) {
            urls.append(directBundleURL)
        }

        if let helperResourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("Helpers")
            .appendingPathComponent(fileName) {
            urls.append(helperResourceURL)
        }

        if let releaseAssetURL = Bundle.main.resourceURL?
            .appendingPathComponent("Helpers")
            .appendingPathComponent(releaseAssetFileName) {
            urls.append(releaseAssetURL)
        }

        if let cachedReleaseAssetURL = cachedReleaseAssetURL(for: arch) {
            urls.append(cachedReleaseAssetURL)
        }

#if DEBUG
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let appResourcesHelpers = repoRoot
            .appendingPathComponent("Roam")
            .appendingPathComponent("Roam")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Helpers")

        urls.append(
            appResourcesHelpers
                .appendingPathComponent(fileName)
        )

        urls.append(
            appResourcesHelpers
                .appendingPathComponent(releaseAssetFileName)
        )

        urls.append(
            repoRoot
                .appendingPathComponent("roam-rs")
                .appendingPathComponent("target")
                .appendingPathComponent(arch.rawValue)
                .appendingPathComponent("release")
                .appendingPathComponent("roam-helper")
        )

        urls.append(
            repoRoot
                .appendingPathComponent("roam-rs")
                .appendingPathComponent("target")
                .appendingPathComponent(arch.rawValue)
                .appendingPathComponent("debug")
                .appendingPathComponent("roam-helper")
        )

        urls.append(
            repoRoot
                .appendingPathComponent("roam-rs")
                .appendingPathComponent("scripts")
                .appendingPathComponent(releaseAssetFileName)
        )
#endif

        return urls
    }

    private static func releaseAssetFileName(for arch: RemoteArch) -> String {
        "roam-helper-linux-\(assetArchitectureName(for: arch))"
    }

    private static func assetArchitectureName(for arch: RemoteArch) -> String {
        switch arch {
        case .x86_64:
            return "x86_64"
        case .aarch64:
            return "aarch64"
        }
    }

    private static func helperReleaseRepository() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RoamHelperReleaseRepository") as? String else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func releaseTag() -> String {
        "helper-v\(HelperInstallService.requiredVersion)"
    }

    private static func releaseDownloadURL(for arch: RemoteArch) -> URL? {
        guard let repository = helperReleaseRepository() else {
            return nil
        }

        return URL(string: "https://github.com/\(repository)/releases/download/\(releaseTag())/\(releaseAssetFileName(for: arch))")
    }

    private static func releaseChecksumURL(for arch: RemoteArch) -> URL? {
        guard let releaseURL = releaseDownloadURL(for: arch) else {
            return nil
        }

        return releaseURL.appendingPathExtension("sha256")
    }

    private static func cachedReleaseAssetURL(for arch: RemoteArch) -> URL? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        return cachesDirectory
            .appendingPathComponent("RoamHelperCache", isDirectory: true)
            .appendingPathComponent(releaseAssetFileName(for: arch))
    }

    private static func cachedReleaseChecksumURL(for arch: RemoteArch) -> URL? {
        cachedReleaseAssetURL(for: arch)?
            .appendingPathExtension("sha256")
    }

    private static func downloadReleaseAsset(
        from releaseURL: URL,
        checksumURL: URL?,
        cacheURL: URL?,
        checksumCacheURL: URL?
    ) async throws -> Data {
        guard let checksumURL else {
            throw HelperBinaryDownloadError.missingChecksumURL
        }

        let checksumData = try await fetchURL(checksumURL)
        let data = try await fetchURL(releaseURL)

        let expectedChecksum = try parseChecksumFile(checksumData)
        let actualChecksum = sha256Hex(for: data)

        guard expectedChecksum.caseInsensitiveCompare(actualChecksum) == .orderedSame else {
            throw HelperBinaryDownloadError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
        }

        if let cacheURL {
            do {
                try FileManager.default.createDirectory(
                    at: cacheURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                try data.write(to: cacheURL, options: .atomic)
                try checksumData.write(to: checksumCacheURL ?? cacheURL.appendingPathExtension("sha256"), options: .atomic)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: cacheURL.path
                )
            } catch {
                // Ignore cache write failures; the in-memory data is still usable for install.
            }
        }

        return data
    }

    private static func fetchURL(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Roam Helper Installer", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HelperBinaryDownloadError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HelperBinaryDownloadError.httpStatus(httpResponse.statusCode)
        }

        return data
    }

    private static func validateCachedReleaseAssetIfNeeded(data: Data, url: URL, arch: RemoteArch) throws -> Bool {
        guard let cachedAssetURL = cachedReleaseAssetURL(for: arch),
              url.path == cachedAssetURL.path else {
            return true
        }

        guard let checksumURL = cachedReleaseChecksumURL(for: arch),
              FileManager.default.isReadableFile(atPath: checksumURL.path) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }

        let checksumData = try Data(contentsOf: checksumURL)
        let expectedChecksum = try parseChecksumFile(checksumData)
        let actualChecksum = sha256Hex(for: data)

        guard expectedChecksum.caseInsensitiveCompare(actualChecksum) == .orderedSame else {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: checksumURL)
            return false
        }

        return true
    }

    private static func parseChecksumFile(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let checksum = text.split(whereSeparator: \.isWhitespace).first.map(String.init),
              checksum.range(of: "^[A-Fa-f0-9]{64}$", options: .regularExpression) != nil else {
            throw HelperBinaryDownloadError.invalidChecksumFile
        }

        return checksum.lowercased()
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum HelperBinaryDownloadError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case missingChecksumURL
    case invalidChecksumFile
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The helper release server returned an invalid response."
        case .httpStatus(let statusCode):
            return "The helper release server returned HTTP \(statusCode)."
        case .missingChecksumURL:
            return "The helper release did not provide a checksum URL."
        case .invalidChecksumFile:
            return "The helper release checksum file was invalid."
        case .checksumMismatch(let expected, let actual):
            return "The helper checksum did not match. Expected \(expected), got \(actual)."
        }
    }
}
