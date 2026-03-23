import Testing
import Foundation
@testable import iDev

@Suite("HelperDTO Decoding")
struct HelperDTOTests {
    let decoder = JSONDecoder()

    @Test("Decode GitStatusDTO")
    func gitStatus() throws {
        let json = """
        {
            "branch": "main",
            "clean": false,
            "staged": 2,
            "modified": 1,
            "untracked": 3,
            "ahead": 1,
            "behind": 0,
            "files": [
                {"path": "src/main.rs", "index_status": "M", "worktree_status": "."},
                {"path": "new.txt", "index_status": ".", "worktree_status": "?"}
            ]
        }
        """.data(using: .utf8)!

        let status = try decoder.decode(GitStatusDTO.self, from: json)
        #expect(status.branch == "main")
        #expect(!status.clean)
        #expect(status.staged == 2)
        #expect(status.modified == 1)
        #expect(status.untracked == 3)
        #expect(status.ahead == 1)
        #expect(status.behind == 0)
        #expect(status.files?.count == 2)
        #expect(status.files?[0].isStaged == true)
        #expect(status.files?[1].isUntracked == true)
    }

    @Test("Decode PreviewCandidateDTO with Phase 4 fields")
    func previewCandidate() throws {
        let json = """
        {
            "port": 3000,
            "pid": 1234,
            "process_name": "node",
            "cwd": "/app",
            "framework_hint": "next",
            "process_label": "npm run dev",
            "health_hint": "ready",
            "startup_elapsed_secs": 5
        }
        """.data(using: .utf8)!

        let candidate = try decoder.decode(PreviewCandidateDTO.self, from: json)
        #expect(candidate.port == 3000)
        #expect(candidate.process_label == "npm run dev")
        #expect(candidate.health_hint == "ready")
        #expect(candidate.startup_elapsed_secs == 5)
    }

    @Test("Decode PreviewCandidateDTO with minimal fields")
    func previewCandidateMinimal() throws {
        let json = """
        {"port": 8080, "pid": 99, "process_name": "python"}
        """.data(using: .utf8)!

        let candidate = try decoder.decode(PreviewCandidateDTO.self, from: json)
        #expect(candidate.port == 8080)
        #expect(candidate.process_label == nil)
        #expect(candidate.health_hint == nil)
    }

    @Test("Decode TunnelInfoDTO")
    func tunnelInfo() throws {
        let json = """
        {
            "provider": "cloudflare",
            "public_url": "https://abc123.trycloudflare.com",
            "local_port": 3000,
            "pid": 5678
        }
        """.data(using: .utf8)!

        let info = try decoder.decode(TunnelInfoDTO.self, from: json)
        #expect(info.provider == "cloudflare")
        #expect(info.public_url == "https://abc123.trycloudflare.com")
        #expect(info.local_port == 3000)
    }

    @Test("Decode ProxyStatusDTO")
    func proxyStatus() throws {
        let json = """
        {
            "running": true,
            "listen_port": 9000,
            "routes": [
                {"path_prefix": "/api", "target_port": 3000, "strip_prefix": true},
                {"path_prefix": "/", "target_port": 8080, "strip_prefix": false}
            ]
        }
        """.data(using: .utf8)!

        let status = try decoder.decode(ProxyStatusDTO.self, from: json)
        #expect(status.running)
        #expect(status.listen_port == 9000)
        #expect(status.routes.count == 2)
        #expect(status.routes[0].strip_prefix == true)
    }

    @Test("Decode TestReportSummaryDTO")
    func testReport() throws {
        let json = """
        {
            "total": 42,
            "passed": 38,
            "failed": 3,
            "skipped": 1,
            "duration_secs": 12.5,
            "failures": [
                {"name": "test_login", "message": "assert failed", "file": "tests/auth.rs", "line": 42},
                {"name": "test_timeout", "message": "timed out"},
                {"name": "test_parse", "message": "unexpected EOF", "file": "src/parser.rs"}
            ]
        }
        """.data(using: .utf8)!

        let report = try decoder.decode(TestReportSummaryDTO.self, from: json)
        #expect(report.total == 42)
        #expect(report.passed == 38)
        #expect(report.failed == 3)
        #expect(report.skipped == 1)
        #expect(report.duration_secs == 12.5)
        #expect(report.failures.count == 3)
        #expect(report.failures[0].line == 42)
        #expect(report.failures[1].file == nil)
        #expect(report.failures[2].line == nil)
    }

    @Test("Decode GitCommitResultDTO")
    func commitResult() throws {
        let json = """
        {"hash": "abc123def", "message": "fix: resolve login bug"}
        """.data(using: .utf8)!

        let result = try decoder.decode(GitCommitResultDTO.self, from: json)
        #expect(result.hash == "abc123def")
        #expect(result.message == "fix: resolve login bug")
    }

    @Test("Decode TmuxSessionDTO")
    func tmuxSession() throws {
        let json = """
        {"name": "dev", "created": 1700000000, "attached": true, "windows": 3}
        """.data(using: .utf8)!

        let session = try decoder.decode(TmuxSessionDTO.self, from: json)
        #expect(session.name == "dev")
        #expect(session.attached)
        #expect(session.windows == 3)
    }

    @Test("GitStatusFileDTO computed properties")
    func gitStatusFileProperties() throws {
        let staged = GitStatusFileDTO(path: "a.txt", index_status: "M", worktree_status: ".")
        #expect(staged.isStaged)
        #expect(!staged.isModified)
        #expect(!staged.isUntracked)

        let modified = GitStatusFileDTO(path: "b.txt", index_status: ".", worktree_status: "M")
        #expect(!modified.isStaged)
        #expect(modified.isModified)

        let untracked = GitStatusFileDTO(path: "c.txt", index_status: ".", worktree_status: "?")
        #expect(untracked.isUntracked)
        #expect(!untracked.isModified) // '?' is not a modification
    }
}
