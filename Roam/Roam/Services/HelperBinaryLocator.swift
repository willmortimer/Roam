import Foundation

enum HelperBinaryLocator {
    static func binaryData(for arch: RemoteArch) throws -> Data {
        let candidates = candidateURLs(for: arch)

        for url in candidates where FileManager.default.isReadableFile(atPath: url.path) {
            return try Data(contentsOf: url)
        }

        throw HelperInstallError.binaryNotFound(
            arch: arch.rawValue,
            searchedPaths: candidates.map(\.path)
        )
    }

    private static func candidateURLs(for arch: RemoteArch) -> [URL] {
        var urls: [URL] = []
        let fileName = "roam-helper-\(arch.rawValue)"
        let releaseAssetFileName = "roam-helper-linux-\(assetArchitectureName(for: arch))"

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

    private static func assetArchitectureName(for arch: RemoteArch) -> String {
        switch arch {
        case .x86_64:
            return "x86_64"
        case .aarch64:
            return "aarch64"
        }
    }
}
