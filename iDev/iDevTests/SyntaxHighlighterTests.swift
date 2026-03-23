import Testing
import Foundation
@testable import iDev

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {

    @Test("Language detection from file extension")
    func languageDetection() {
        #expect(SyntaxHighlighter.Language.from(extension: "swift") == .swift)
        #expect(SyntaxHighlighter.Language.from(extension: "rs") == .rust)
        #expect(SyntaxHighlighter.Language.from(extension: "py") == .python)
        #expect(SyntaxHighlighter.Language.from(extension: "js") == .javascript)
        #expect(SyntaxHighlighter.Language.from(extension: "ts") == .typescript)
        #expect(SyntaxHighlighter.Language.from(extension: "json") == .json)
        #expect(SyntaxHighlighter.Language.from(extension: "yaml") == .yaml)
        #expect(SyntaxHighlighter.Language.from(extension: "yml") == .yaml)
        #expect(SyntaxHighlighter.Language.from(extension: "md") == .markdown)
        #expect(SyntaxHighlighter.Language.from(extension: "sh") == .shell)
        #expect(SyntaxHighlighter.Language.from(extension: "toml") == .toml)
        #expect(SyntaxHighlighter.Language.from(extension: "unknown") == .plaintext)
        #expect(SyntaxHighlighter.Language.from(extension: "") == .plaintext)
    }

    @Test("Case insensitive extension matching")
    func caseInsensitiveExtension() {
        #expect(SyntaxHighlighter.Language.from(extension: "SWIFT") == .swift)
        #expect(SyntaxHighlighter.Language.from(extension: "Rs") == .rust)
        #expect(SyntaxHighlighter.Language.from(extension: "PY") == .python)
    }

    @Test("Highlight returns non-empty attributed string for code")
    func highlightProducesOutput() {
        let code = "let x = 42"
        let result = SyntaxHighlighter.highlight(content: code, language: .swift)
        #expect(result.length > 0)
        #expect(result.string == code)
    }

    @Test("Highlight preserves text content")
    func highlightPreservesText() {
        let code = "fn main() { println!(\"hello\"); }"
        let result = SyntaxHighlighter.highlight(content: code, language: .rust)
        #expect(result.string == code)
    }

    @Test("Empty content produces empty attributed string")
    func emptyContent() {
        let result = SyntaxHighlighter.highlight(content: "", language: .swift)
        #expect(result.length == 0)
    }

    @Test("Plaintext passes through unchanged")
    func plaintext() {
        let text = "just some text with no highlighting"
        let result = SyntaxHighlighter.highlight(content: text, language: .plaintext)
        #expect(result.string == text)
    }

    @Test("All languages produce valid output without crashing")
    func allLanguages() {
        let sample = "hello world 42 true false // comment"
        for lang in SyntaxHighlighter.Language.allCases {
            let result = SyntaxHighlighter.highlight(content: sample, language: lang)
            #expect(result.string == sample, "Failed for \(lang.rawValue)")
        }
    }

    @Test("JSON highlighting handles braces and colons")
    func jsonHighlighting() {
        let json = #"{"key": "value", "number": 42}"#
        let result = SyntaxHighlighter.highlight(content: json, language: .json)
        #expect(result.string == json)
    }

    @Test("JSX extension detected as JavaScript")
    func jsxExtension() {
        #expect(SyntaxHighlighter.Language.from(extension: "jsx") == .javascript)
        #expect(SyntaxHighlighter.Language.from(extension: "mjs") == .javascript)
        #expect(SyntaxHighlighter.Language.from(extension: "cjs") == .javascript)
    }

    @Test("TSX extension detected as TypeScript")
    func tsxExtension() {
        #expect(SyntaxHighlighter.Language.from(extension: "tsx") == .typescript)
        #expect(SyntaxHighlighter.Language.from(extension: "mts") == .typescript)
    }
}
