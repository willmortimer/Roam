import Foundation
import RoamSSH

// MARK: - Detection Result

nonisolated enum HelperDetectionResult: Sendable, Equatable {
    case installed(String)          // version string
    case outdated(String, String)   // installed version, required version
    case notInstalled
    case error(String)
}

// MARK: - Remote Architecture

nonisolated enum RemoteArch: String, Sendable {
    case x86_64 = "x86_64-unknown-linux-musl"
    case aarch64 = "aarch64-unknown-linux-musl"
}

// MARK: - Helper Install Service

/// Detects, installs, and upgrades roam-helper on remote hosts via SSH exec.
nonisolated final class HelperInstallService: @unchecked Sendable {
    private let sshSession: LibSSH2Session
    private let helperPath: String

    /// Minimum protocol version the app requires.
    static let requiredVersion = "0.1.0"

    init(sshSession: LibSSH2Session, helperPath: String = "~/.local/bin/roam-helper") {
        self.sshSession = sshSession
        self.helperPath = helperPath
    }

    // MARK: - Detect

    /// Check if the helper is installed and what version.
    func detectHelper() async -> HelperDetectionResult {
        do {
            let command = shellWrapped("\(helperPath) version 2>&1")
            let channel = try await sshSession.openExec(command: command)
            var output = Data()
            for try await chunk in channel.readStdout() {
                output.append(chunk)
            }
            let exitCode = try await channel.waitForExit()
            await channel.close()

            let versionString = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if exitCode == 127 || isMissingHelperOutput(versionString) {
                return .notInstalled
            }

            guard exitCode == 0 else {
                let message = versionString.isEmpty ? "Helper check failed with exit code \(exitCode)." : versionString
                return .error(message)
            }

            guard !versionString.isEmpty else {
                return .error("Helper returned no version output.")
            }

            // Parse version from output like "roam-helper 0.1.0"
            let version = parseVersion(from: versionString)

            if compareVersions(version, Self.requiredVersion) < 0 {
                return .outdated(version, Self.requiredVersion)
            }

            return .installed(version)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Detect Architecture

    /// Detect the remote host's CPU architecture.
    func detectArchitecture() async throws -> RemoteArch {
        let channel = try await sshSession.openExec(command: "uname -m")
        var output = Data()
        for try await chunk in channel.readStdout() {
            output.append(chunk)
        }
        await channel.close()

        guard let arch = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw HelperInstallError.unsupportedArchitecture("unknown")
        }

        switch arch {
        case "x86_64", "amd64":
            return .x86_64
        case "aarch64", "arm64":
            return .aarch64
        default:
            throw HelperInstallError.unsupportedArchitecture(arch)
        }
    }

    // MARK: - Install

    /// Install the helper binary on the remote host via exec channel.
    /// Uses `cat > file` approach which works on any SSH connection.
    func installHelper(binaryData: Data) async throws {
        // Create directory and write binary in one command
        let command = "mkdir -p ~/.local/bin && cat > \(helperPath) && chmod +x \(helperPath)"
        let channel = try await sshSession.openExec(command: command)

        // Write binary data to stdin
        try await channel.write(binaryData)
        try await channel.sendEOF()

        let exitCode = try await channel.waitForExit()
        await channel.close()

        guard exitCode == 0 else {
            throw HelperInstallError.installFailed("Command exited with code \(exitCode)")
        }

        // Verify installation
        let verifyChannel = try await sshSession.openExec(command: "\(helperPath) version")
        var output = Data()
        for try await chunk in verifyChannel.readStdout() {
            output.append(chunk)
        }
        await verifyChannel.close()

        guard let versionStr = String(data: output, encoding: .utf8),
              !versionStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HelperInstallError.verificationFailed
        }
    }

    /// Upgrade is the same as install — overwrites the existing binary.
    func upgradeHelper(binaryData: Data) async throws {
        try await installHelper(binaryData: binaryData)
    }

    // MARK: - Version Parsing

    private func parseVersion(from output: String) -> String {
        // Handle formats: "roam-helper 0.1.0", "0.1.0", "v0.1.0"
        let components = output.split(separator: " ")
        let raw = components.last.map(String.init) ?? output
        return raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
    }

    private func isMissingHelperOutput(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("not found")
            || normalized.contains("no such file")
    }

    private func shellWrapped(_ command: String) -> String {
        "sh -lc \(shellQuoted(command))"
    }

    private func shellQuoted(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// Compare semver strings. Returns negative if a < b, 0 if equal, positive if a > b.
    private func compareVersions(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(aParts.count, bParts.count) {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av != bv { return av - bv }
        }
        return 0
    }
}

// MARK: - Errors

nonisolated enum HelperInstallError: Error, LocalizedError, Sendable {
    case unsupportedArchitecture(String)
    case installFailed(String)
    case verificationFailed
    case binaryNotFound(arch: String, searchedPaths: [String], releaseURL: String?)
    case binaryDownloadFailed(arch: String, searchedPaths: [String], releaseURL: String, message: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture(let arch):
            return "Unsupported architecture: \(arch)"
        case .installFailed(let msg):
            return "Helper install failed: \(msg)"
        case .verificationFailed:
            return "Helper installed but failed verification"
        case .binaryNotFound(let arch, let searchedPaths, let releaseURL):
            let paths = searchedPaths.map { "  - \($0)" }.joined(separator: "\n")
            let releaseHint = if let releaseURL {
                """

                Roam also looked for a published helper release at:
                  \(releaseURL)
                """
            } else {
                ""
            }
            return """
            No helper binary is available for \(arch).

            This is not a simulator limitation. The app needs a prebuilt Linux helper to upload to the remote host.

            Build it first with:
              cd roam-rs
              just cross-install
              just cross-host-toolchain
              cross build --release --target \(arch)

            Then either:
              - copy the binary into Roam/Roam/Resources/Helpers/ as roam-helper-\(arch), then rebuild the app
              - or leave it at roam-rs/target/\(arch)/release/roam-helper for debug builds
              - or publish a GitHub release asset for tag helper-v\(HelperInstallService.requiredVersion)

            Searched paths:
            \(paths)
            \(releaseHint)
            """
        case .binaryDownloadFailed(let arch, let searchedPaths, let releaseURL, let message):
            let paths = searchedPaths.map { "  - \($0)" }.joined(separator: "\n")
            return """
            Roam could not fetch the helper binary for \(arch).

            Release URL:
              \(releaseURL)

            Download error:
              \(message)

            Local paths checked first:
            \(paths)
            """
        }
    }
}
