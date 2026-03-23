import Foundation
import UIKit

/// Regex-based syntax highlighting for common languages.
/// Returns an `NSAttributedString` suitable for display in a text view.
nonisolated enum SyntaxHighlighter {

    enum Language: String, Sendable, CaseIterable {
        case swift, rust, python, javascript, typescript
        case json, yaml, markdown, dockerfile, shell, toml
        case plaintext

        static func from(extension ext: String) -> Language {
            switch ext.lowercased() {
            case "swift": .swift
            case "rs": .rust
            case "py", "pyi": .python
            case "js", "jsx", "mjs", "cjs": .javascript
            case "ts", "tsx", "mts": .typescript
            case "json", "jsonl": .json
            case "yaml", "yml": .yaml
            case "md", "markdown": .markdown
            case "dockerfile": .dockerfile
            case "sh", "bash", "zsh", "fish": .shell
            case "toml": .toml
            default: .plaintext
            }
        }
    }

    /// Highlight the given source text and return an attributed string.
    static func highlight(content: String, language: Language, fontSize: CGFloat = 13) -> NSAttributedString {
        let baseFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)

        let base: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: UIColor.label,
        ]

        let result = NSMutableAttributedString(string: content, attributes: base)

        guard language != .plaintext else { return result }

        let rules = Self.rules(for: language)
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            for match in regex.matches(in: content, range: fullRange) {
                let range = rule.captureGroup < match.numberOfRanges
                    ? match.range(at: rule.captureGroup)
                    : match.range
                guard range.location != NSNotFound else { continue }

                result.addAttribute(.foregroundColor, value: rule.color, range: range)
                if rule.bold {
                    result.addAttribute(.font, value: boldFont, range: range)
                }
            }
        }

        return result
    }

    // MARK: - Rules

    private struct Rule {
        var pattern: String
        var color: UIColor
        var bold: Bool = false
        var options: NSRegularExpression.Options = []
        var captureGroup: Int = 0
    }

    private static func rules(for language: Language) -> [Rule] {
        var rules: [Rule] = []

        // Comments (applied first, can be overridden by later rules for strings inside comments — but ordering here means comments win)
        switch language {
        case .swift, .rust, .javascript, .typescript, .json, .toml:
            rules.append(Rule(pattern: "//.*$", color: .commentColor, options: .anchorsMatchLines))
            rules.append(Rule(pattern: "/\\*[\\s\\S]*?\\*/", color: .commentColor, options: .dotMatchesLineSeparators))
        case .python, .shell, .yaml, .dockerfile:
            rules.append(Rule(pattern: "#.*$", color: .commentColor, options: .anchorsMatchLines))
        case .markdown:
            break // no traditional comments
        case .plaintext:
            break
        }

        // Strings
        switch language {
        case .swift, .rust, .javascript, .typescript, .python, .shell, .yaml, .toml:
            rules.append(Rule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", color: .stringColor))
            rules.append(Rule(pattern: "'(?:[^'\\\\]|\\\\.)*'", color: .stringColor))
        case .json:
            rules.append(Rule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", color: .stringColor))
        case .markdown, .dockerfile, .plaintext:
            rules.append(Rule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", color: .stringColor))
        }

        // Python triple-quoted strings
        if language == .python {
            rules.append(Rule(pattern: "\"\"\"[\\s\\S]*?\"\"\"", color: .stringColor, options: .dotMatchesLineSeparators))
            rules.append(Rule(pattern: "'''[\\s\\S]*?'''", color: .stringColor, options: .dotMatchesLineSeparators))
        }

        // Numbers
        switch language {
        case .swift, .rust, .python, .javascript, .typescript, .json, .yaml, .toml:
            rules.append(Rule(pattern: "\\b(?:0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?)\\b", color: .numberColor))
        default:
            break
        }

        // Keywords
        switch language {
        case .swift:
            rules.append(Rule(
                pattern: "\\b(?:actor|associatedtype|async|await|break|case|catch|class|continue|default|defer|deinit|do|else|enum|extension|fallthrough|fileprivate|final|for|func|guard|if|import|in|init|inout|internal|is|lazy|let|nonisolated|open|operator|override|private|protocol|public|repeat|rethrows|return|self|Self|some|static|struct|subscript|super|switch|Task|throw|throws|try|typealias|var|weak|where|while)\\b",
                color: .keywordColor, bold: true
            ))
            // Types
            rules.append(Rule(pattern: "\\b(?:Any|Array|Bool|Character|Dictionary|Double|Float|Int|Never|Optional|Result|Set|String|UInt|Void)\\b", color: .typeColor))
            // Attributes
            rules.append(Rule(pattern: "@\\w+", color: .attributeColor))
        case .rust:
            rules.append(Rule(
                pattern: "\\b(?:as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while)\\b",
                color: .keywordColor, bold: true
            ))
            rules.append(Rule(pattern: "\\b(?:bool|char|f32|f64|i8|i16|i32|i64|i128|isize|str|u8|u16|u32|u64|u128|usize|Box|Option|Result|String|Vec)\\b", color: .typeColor))
            // Macros
            rules.append(Rule(pattern: "\\b\\w+!", color: .macroColor))
            // Attributes
            rules.append(Rule(pattern: "#\\[.*?\\]", color: .attributeColor))
            // Lifetimes
            rules.append(Rule(pattern: "'[a-zA-Z_]\\w*", color: .typeColor))
        case .python:
            rules.append(Rule(
                pattern: "\\b(?:False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)\\b",
                color: .keywordColor, bold: true
            ))
            rules.append(Rule(pattern: "\\b(?:int|float|str|bool|list|dict|tuple|set|bytes|type|object)\\b", color: .typeColor))
            // Decorators
            rules.append(Rule(pattern: "@\\w+", color: .attributeColor))
        case .javascript, .typescript:
            rules.append(Rule(
                pattern: "\\b(?:async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|from|function|if|import|in|instanceof|let|new|of|return|static|super|switch|this|throw|try|typeof|var|void|while|with|yield)\\b",
                color: .keywordColor, bold: true
            ))
            if language == .typescript {
                rules.append(Rule(
                    pattern: "\\b(?:abstract|any|boolean|declare|enum|implements|interface|keyof|module|namespace|never|number|private|protected|public|readonly|string|symbol|type|undefined|unknown)\\b",
                    color: .typeColor
                ))
            }
        case .json:
            // JSON keys (before the colon)
            rules.append(Rule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"(?=\\s*:)", color: .keywordColor, bold: true))
        case .yaml:
            // YAML keys
            rules.append(Rule(pattern: "^\\s*[\\w.-]+(?=\\s*:)", color: .keywordColor, bold: true, options: .anchorsMatchLines))
            rules.append(Rule(pattern: "\\b(?:true|false|null|yes|no)\\b", color: .numberColor))
        case .markdown:
            // Headings
            rules.append(Rule(pattern: "^#{1,6}\\s.*$", color: .keywordColor, bold: true, options: .anchorsMatchLines))
            // Bold
            rules.append(Rule(pattern: "\\*\\*.*?\\*\\*", color: .label, bold: true))
            // Italic
            rules.append(Rule(pattern: "\\*.*?\\*", color: .secondaryLabel))
            // Inline code
            rules.append(Rule(pattern: "`[^`]+`", color: .stringColor))
            // Links
            rules.append(Rule(pattern: "\\[.*?\\]\\(.*?\\)", color: .typeColor))
        case .dockerfile:
            rules.append(Rule(
                pattern: "^(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\\b",
                color: .keywordColor, bold: true, options: .anchorsMatchLines
            ))
        case .shell:
            rules.append(Rule(
                pattern: "\\b(?:alias|bg|break|case|cd|command|continue|do|done|echo|elif|else|esac|eval|exec|exit|export|fg|fi|for|function|getopts|if|in|local|printf|read|readonly|return|select|set|shift|source|then|time|trap|type|ulimit|umask|unalias|unset|until|wait|while)\\b",
                color: .keywordColor, bold: true
            ))
            // Variables
            rules.append(Rule(pattern: "\\$\\{?\\w+\\}?", color: .typeColor))
        case .toml:
            // Section headers
            rules.append(Rule(pattern: "^\\[\\[?[^\\]]*\\]\\]?", color: .keywordColor, bold: true, options: .anchorsMatchLines))
            rules.append(Rule(pattern: "\\b(?:true|false)\\b", color: .numberColor))
        case .plaintext:
            break
        }

        // Boolean/nil literals
        switch language {
        case .swift:
            rules.append(Rule(pattern: "\\b(?:true|false|nil)\\b", color: .numberColor))
        case .rust:
            rules.append(Rule(pattern: "\\b(?:true|false|None|Some)\\b", color: .numberColor))
        case .javascript, .typescript:
            rules.append(Rule(pattern: "\\b(?:true|false|null|undefined|NaN|Infinity)\\b", color: .numberColor))
        case .json:
            rules.append(Rule(pattern: "\\b(?:true|false|null)\\b", color: .numberColor))
        default:
            break
        }

        return rules
    }
}

// MARK: - Color Palette (adapts to light/dark mode)

private extension UIColor {
    static let commentColor = UIColor.secondaryLabel
    static let stringColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.84, green: 0.36, blue: 0.36, alpha: 1)  // soft red
            : UIColor(red: 0.76, green: 0.22, blue: 0.17, alpha: 1)  // darker red
    }
    static let keywordColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.47, blue: 0.86, alpha: 1)  // purple
            : UIColor(red: 0.43, green: 0.27, blue: 0.73, alpha: 1)
    }
    static let typeColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.35, green: 0.74, blue: 0.73, alpha: 1)  // teal
            : UIColor(red: 0.11, green: 0.51, blue: 0.51, alpha: 1)
    }
    static let numberColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.82, green: 0.68, blue: 0.35, alpha: 1)  // gold
            : UIColor(red: 0.65, green: 0.49, blue: 0.15, alpha: 1)
    }
    static let attributeColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.56, green: 0.74, blue: 0.44, alpha: 1)  // green
            : UIColor(red: 0.33, green: 0.55, blue: 0.22, alpha: 1)
    }
    static let macroColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.65, blue: 0.86, alpha: 1)  // blue
            : UIColor(red: 0.15, green: 0.44, blue: 0.70, alpha: 1)
    }
}
