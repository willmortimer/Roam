import Foundation

/// Client-side caller for the Rust helper RPC.
/// Communicates with idev-helper over an SSH exec channel using NDJSON.
nonisolated protocol HelperClientProtocol: Sendable {
    /// Whether the remote helper was detected and is responding.
    func isAvailable() async -> Bool

    /// Generic RPC call.
    func call<P: Encodable & Sendable, R: Decodable>(method: String, params: P) async throws -> R

    // MARK: Phase 1 — Read-only helpers

    func ping() async throws -> Bool
    func listTmuxSessions() async throws -> [TmuxSessionDTO]
    func listTmuxPanes(session: String) async throws -> [TmuxPaneDTO]
    func capturePaneContent(session: String, paneID: String, lines: Int) async throws -> String
    func sendKeys(session: String, paneID: String, keys: String) async throws
    func listPorts() async throws -> [ListeningPortDTO]
    func previewCandidates(workspacePath: String?) async throws -> [PreviewCandidateDTO]
    func gitStatus(repoPath: String) async throws -> GitStatusDTO
    func gitDiffSummary(repoPath: String) async throws -> GitDiffSummaryDTO
    func listRecentArtifacts(roots: [String], sinceHours: Int) async throws -> [ArtifactDTO]
    func resumePlan(workspaceID: String) async throws -> ResumePlanDTO

    // MARK: Phase 2/3 — Git write operations

    func gitStage(repoPath: String, paths: [String]) async throws
    func gitUnstage(repoPath: String, paths: [String]) async throws
    func gitCommit(repoPath: String, message: String, amend: Bool) async throws -> GitCommitResultDTO
    func gitPush(repoPath: String, setUpstream: Bool) async throws -> GitPushResultDTO
    func gitPull(repoPath: String, rebase: Bool) async throws -> GitPullResultDTO
    func gitBranchList(repoPath: String) async throws -> [GitBranchInfoDTO]
    func gitCheckout(repoPath: String, ref: String, create: Bool) async throws
    func gitStash(repoPath: String, message: String?) async throws
    func gitStashPop(repoPath: String, index: Int?) async throws
    func gitStashList(repoPath: String) async throws -> [GitStashEntryDTO]

    // MARK: Phase 4 — Proxy

    func proxyStart(listenPort: Int, routes: [ProxyRouteDTO]) async throws -> ProxyStatusDTO
    func proxyStop() async throws
    func proxyStatus() async throws -> ProxyStatusDTO

    // MARK: Phase 4 — Tunnel

    func tunnelStartCloudflare(port: Int) async throws -> TunnelInfoDTO
    func tunnelStartTailscale(port: Int) async throws -> TunnelInfoDTO
    func tunnelStop() async throws
    func tunnelStatus() async throws -> TunnelInfoDTO?

    // MARK: Phase 4 — Testing

    func parseTestReport(path: String, format: String) async throws -> TestReportSummaryDTO
}
