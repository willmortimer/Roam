import Foundation

/// Heuristic parser for terminal output — detects errors, URLs, and ports.
/// Used as a fallback when the helper isn't available and as a supplement to
/// helper-provided data.
nonisolated enum TerminalOutputParser {

    /// Detect error-like lines in terminal output.
    static func detectErrors(in text: String) -> [DetectedError] {
        var results: [DetectedError] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let str = String(line)
            if let severity = classifyErrorLine(str) {
                results.append(DetectedError(line: str, lineNumber: index + 1, severity: severity))
            }
        }
        return results
    }

    /// Detect URLs in terminal output.
    static func detectURLs(in text: String) -> [DetectedURL] {
        var results: [DetectedURL] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        detector?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let url = match.url else { return }
            // Extract surrounding context (the line containing the URL)
            let matchRange = Range(match.range, in: text) ?? text.startIndex..<text.endIndex
            let lineStart = text[..<matchRange.lowerBound].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
            let lineEnd = text[matchRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
            let context = String(text[lineStart..<lineEnd])
            results.append(DetectedURL(url: url, context: context))
        }
        return results
    }

    /// Detect port numbers from common server startup patterns.
    static func detectPorts(in text: String) -> [DetectedPort] {
        var results: [DetectedPort] = []
        var seen = Set<Int>()

        // Common patterns: "listening on port 3000", "http://localhost:8080", ":3000", "port 5173"
        let patterns: [(String, Int)] = [
            ("(?:listening|started|running|serving)\\s+(?:on|at)\\s+(?:port\\s+)?(\\d{2,5})", 1),
            ("(?:localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0):(\\d{2,5})", 1),
            ("(?:port|PORT)\\s*[=:]\\s*(\\d{2,5})", 1),
            ("http://[^:]+:(\\d{2,5})", 1),
        ]

        for (pattern, group) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let portRange = Range(match.range(at: group), in: text),
                      let port = Int(text[portRange]),
                      port >= 80 && port <= 65535,
                      !seen.contains(port) else { continue }
                seen.insert(port)

                // Extract context line
                let lineStart = text[..<portRange.lowerBound].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
                let lineEnd = text[portRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
                let context = String(text[lineStart..<lineEnd])
                results.append(DetectedPort(port: port, context: context))
            }
        }
        return results
    }

    // MARK: - Private

    private static func classifyErrorLine(_ line: String) -> ErrorSeverity? {
        let upper = line.uppercased()
        // Skip lines that are just the word in a header/comment context
        let trimmed = upper.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("FATAL") || upper.contains("FATAL ERROR") || upper.contains("PANIC") {
            return .fatal
        }
        if trimmed.hasPrefix("ERROR") || upper.contains("ERROR:") || upper.contains("[ERROR]")
            || upper.contains("TRACEBACK") || upper.contains("EXCEPTION")
            || upper.contains("UNHANDLED REJECTION") {
            return .error
        }
        if trimmed.hasPrefix("WARN") || upper.contains("WARNING:") || upper.contains("[WARN]") {
            return .warning
        }
        // Stack trace indicators
        if trimmed.hasPrefix("AT ") && (upper.contains(".JS:") || upper.contains(".TS:") || upper.contains(".PY:")) {
            return .error
        }
        // Rust panics
        if upper.contains("THREAD '") && upper.contains("PANICKED AT") {
            return .fatal
        }
        return nil
    }
}

// MARK: - Types

struct DetectedError: Sendable {
    var line: String
    var lineNumber: Int
    var severity: ErrorSeverity
}

enum ErrorSeverity: Sendable {
    case warning, error, fatal

    var label: String {
        switch self {
        case .warning: "Warning"
        case .error: "Error"
        case .fatal: "Fatal"
        }
    }
}

struct DetectedURL: Sendable {
    var url: URL
    var context: String
}

struct DetectedPort: Sendable {
    var port: Int
    var context: String
}
