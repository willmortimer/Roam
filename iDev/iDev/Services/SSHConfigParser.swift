import Foundation

/// A parsed entry from an SSH config file.
struct SSHConfigEntry: Sendable {
    var alias: String
    var hostname: String
    var user: String?
    var port: Int = 22
    var identityFile: String?
    var proxyJump: String?
}

/// Parses OpenSSH `~/.ssh/config` format into structured entries.
nonisolated enum SSHConfigParser {

    /// Parse an SSH config string into entries.
    /// Skips wildcard hosts (`*`, `*.example.com`) and hosts with no usable hostname.
    static func parse(_ content: String) -> [SSHConfigEntry] {
        var entries: [SSHConfigEntry] = []
        var current: SSHConfigEntry?

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Skip comments and blank lines
            if line.isEmpty || line.hasPrefix("#") { continue }

            let (keyword, value) = parseKeyValue(line)
            guard !value.isEmpty else { continue }

            switch keyword.lowercased() {
            case "host":
                // Finalize previous entry
                if let entry = current {
                    entries.append(entry)
                }
                current = nil

                // Skip wildcards and patterns
                if value.contains("*") || value.contains("?") || value.contains("!") {
                    continue
                }

                current = SSHConfigEntry(alias: value, hostname: value)

            case "hostname":
                current?.hostname = value

            case "user":
                current?.user = value

            case "port":
                if let port = Int(value) {
                    current?.port = port
                }

            case "identityfile":
                current?.identityFile = value

            case "proxyjump":
                current?.proxyJump = value

            default:
                break
            }
        }

        // Finalize last entry
        if let entry = current {
            entries.append(entry)
        }

        return entries
    }

    /// Parse SSH config file at the given path.
    static func parseFile(at path: String) -> [SSHConfigEntry] {
        let expandedPath = (path as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: expandedPath, encoding: .utf8) else {
            return []
        }
        return parse(content)
    }

    /// Parse the default SSH config at ~/.ssh/config.
    static func parseDefaultConfig() -> [SSHConfigEntry] {
        parseFile(at: "~/.ssh/config")
    }

    // MARK: - Private

    /// Parse a line into (keyword, value), supporting both space and `=` delimiters.
    private static func parseKeyValue(_ line: String) -> (String, String) {
        // Handle "Keyword=Value" syntax
        if let equalsIndex = line.firstIndex(of: "=") {
            let key = String(line[line.startIndex..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            return (key, val)
        }

        // Handle "Keyword Value" syntax (split on first whitespace)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let spaceIndex = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return (trimmed, "")
        }

        let key = String(trimmed[trimmed.startIndex..<spaceIndex])
        let val = String(trimmed[trimmed.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
        return (key, val)
    }
}
