import Foundation
import RoamSSH

// MARK: - RPC Param Types

private nonisolated struct EmptyParams: Encodable, Sendable {}

private nonisolated struct SessionParams: Encodable, Sendable {
    var session: String
}

private nonisolated struct CapturePaneParams: Encodable, Sendable {
    var session: String
    var pane_id: String
    var lines: Int
}

private nonisolated struct SendKeysParams: Encodable, Sendable {
    var session: String
    var pane_id: String
    var keys: String
}

private nonisolated struct WorkspacePathParams: Encodable, Sendable {
    var workspace_path: String?
}

private nonisolated struct RepoPathParams: Encodable, Sendable {
    var repo_path: String
}

private nonisolated struct ArtifactsParams: Encodable, Sendable {
    var roots: [String]
    var since_hours: Int
}

private nonisolated struct WorkspaceIDParams: Encodable, Sendable {
    var workspace_id: String
}

// Phase 3: git write param types

private nonisolated struct GitStageParams: Encodable, Sendable {
    var repo_path: String
    var paths: [String]
}

private nonisolated struct GitCommitParams: Encodable, Sendable {
    var repo_path: String
    var message: String
    var amend: Bool?
}

private nonisolated struct GitPushParams: Encodable, Sendable {
    var repo_path: String
    var set_upstream: Bool?
}

private nonisolated struct GitPullParams: Encodable, Sendable {
    var repo_path: String
    var rebase: Bool?
}

private nonisolated struct GitCheckoutParams: Encodable, Sendable {
    var repo_path: String
    var ref_name: String
    var create: Bool?

    enum CodingKeys: String, CodingKey {
        case repo_path
        case ref_name = "ref"
        case create
    }
}

private nonisolated struct GitStashParams: Encodable, Sendable {
    var repo_path: String
    var message: String?
}

private nonisolated struct GitStashPopParams: Encodable, Sendable {
    var repo_path: String
    var index: Int?
}

// Phase 4: proxy, tunnel, testing param types

private nonisolated struct ProxyStartParams: Encodable, Sendable {
    var listen_port: Int
    var routes: [ProxyRouteParam]
}

private nonisolated struct ProxyRouteParam: Encodable, Sendable {
    var path_prefix: String
    var target_port: Int
    var strip_prefix: Bool
}

private nonisolated struct TunnelPortParams: Encodable, Sendable {
    var port: Int
}

private nonisolated struct TestReportParams: Encodable, Sendable {
    var path: String
    var format: String
}

// MARK: - Helper Transport Abstraction

/// Unified transport for NDJSON RPC — either SSH exec channel (stdio) or direct-tcpip (daemon).
private enum HelperTransport: @unchecked Sendable {
    case stdio(ExecChannel)
    case daemon(DirectTCPIPChannel)

    nonisolated func write(_ data: Data) async throws {
        switch self {
        case .stdio(let channel): try await channel.write(data)
        case .daemon(let channel): try await channel.write(data)
        }
    }

    nonisolated func readStream() -> AsyncThrowingStream<Data, Error> {
        switch self {
        case .stdio(let channel): channel.readStdout()
        case .daemon(let channel): channel.read()
        }
    }
}

// MARK: - Helper Client

/// Concrete helper RPC client that communicates with roam-helper over NDJSON.
/// Supports two transport modes:
/// - **stdio**: SSH exec channel running `roam-helper serve --stdio` (default)
/// - **daemon**: SSH direct-tcpip channel to a running `roam-helper serve --listen` daemon
nonisolated final class HelperClient: HelperClientProtocol, @unchecked Sendable {
    private let sshSession: LibSSH2Session
    private let helperPath: String
    private let daemonPort: Int
    private var transport: HelperTransport?
    private var _available = false
    private var _transportMode: TransportMode = .stdio
    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private let pendingLock = NSLock()

    private var responseBuffer = Data()
    private let bufferLock = NSLock()

    enum TransportMode: String, Sendable { case stdio, daemon }

    var transportMode: TransportMode {
        lock.withLock { _transportMode }
    }

    init(sshSession: LibSSH2Session, helperPath: String = "~/.local/bin/roam-helper", daemonPort: Int = 9876) {
        self.sshSession = sshSession
        self.helperPath = helperPath
        self.daemonPort = daemonPort
    }

    // MARK: - Lifecycle

    /// Start the helper connection. Tries daemon mode first (direct-tcpip to daemonPort),
    /// falls back to stdio mode (SSH exec).
    func start() async throws {
        // Try daemon mode first
        if let daemonTransport = await tryDaemonConnect() {
            lock.withLock {
                self.transport = daemonTransport
                self._transportMode = .daemon
            }
            startReadLoop(transport: daemonTransport)
        } else {
            // Fall back to stdio exec
            let channel = try await sshSession.openExec(command: "\(helperPath) serve --stdio")
            let stdioTransport = HelperTransport.stdio(channel)
            lock.withLock {
                self.transport = stdioTransport
                self._transportMode = .stdio
            }
            startReadLoop(transport: stdioTransport)
        }

        do {
            let isPong = try await ping()
            lock.withLock { _available = isPong }
        } catch {
            lock.withLock { _available = false }
        }
    }

    /// Connect only via stdio exec (skip daemon detection).
    func startStdio() async throws {
        let channel = try await sshSession.openExec(command: "\(helperPath) serve --stdio")
        let stdioTransport = HelperTransport.stdio(channel)
        lock.withLock {
            self.transport = stdioTransport
            self._transportMode = .stdio
        }
        startReadLoop(transport: stdioTransport)

        do {
            let isPong = try await ping()
            lock.withLock { _available = isPong }
        } catch {
            lock.withLock { _available = false }
        }
    }

    func isAvailable() async -> Bool {
        lock.withLock { _available }
    }

    private func tryDaemonConnect() async -> HelperTransport? {
        do {
            let channel = try await sshSession.openDirectTCPIP(remoteHost: "127.0.0.1", remotePort: daemonPort)
            return .daemon(channel)
        } catch {
            return nil
        }
    }

    private func startReadLoop(transport: HelperTransport) {
        Task { [weak self] in
            await self?.readResponses(transport: transport)
        }
    }

    // MARK: - Generic RPC

    func call<P: Encodable & Sendable, R: Decodable>(method: String, params: P) async throws -> R {
        guard let transport = lock.withLock({ self.transport }) else {
            throw HelperError.notConnected
        }

        let requestID = UUID().uuidString
        let request = HelperRPCRequest(id: requestID, method: method, params: params)

        var requestData = try encoder.encode(request)
        requestData.append(0x0A)

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            pendingLock.withLock {
                pending[requestID] = continuation
            }

            Task {
                do {
                    try await transport.write(requestData)
                } catch {
                    let cont = self.pendingLock.withLock {
                        self.pending.removeValue(forKey: requestID)
                    }
                    cont?.resume(throwing: error)
                }
            }
        }

        let response = try decoder.decode(HelperRPCResponse.self, from: responseData)

        if let rpcError = response.error {
            throw HelperError.rpcError(code: rpcError.code, message: rpcError.message)
        }

        guard let result = response.result else {
            throw HelperError.emptyResult
        }

        let resultData = try encoder.encode(result)
        return try decoder.decode(R.self, from: resultData)
    }

    // MARK: - Response Reader

    private func readResponses(transport: HelperTransport) async {
        do {
            for try await data in transport.readStream() {
                bufferLock.withLock {
                    responseBuffer.append(data)
                }
                processBuffer()
            }
        } catch {
            // Stream error
        }

        pendingLock.withLock {
            for (_, continuation) in pending {
                continuation.resume(throwing: HelperError.disconnected)
            }
            pending.removeAll()
        }
    }

    private func processBuffer() {
        bufferLock.withLock {
            while let newlineIndex = responseBuffer.firstIndex(of: 0x0A) {
                let lineData = responseBuffer[responseBuffer.startIndex..<newlineIndex]
                responseBuffer = Data(responseBuffer[responseBuffer.index(after: newlineIndex)...])

                guard !lineData.isEmpty else { continue }

                if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let requestID = json["id"] as? String {
                    pendingLock.withLock {
                        if let continuation = pending.removeValue(forKey: requestID) {
                            continuation.resume(returning: Data(lineData))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Convenience Methods

    func ping() async throws -> Bool {
        nonisolated struct PingResult: Decodable { var pong: Bool }
        let result: PingResult = try await call(method: "ping", params: EmptyParams())
        return result.pong
    }

    func listTmuxSessions() async throws -> [TmuxSessionDTO] {
        try await call(method: "tmux.list_sessions", params: EmptyParams())
    }

    func listTmuxPanes(session: String) async throws -> [TmuxPaneDTO] {
        try await call(method: "tmux.list_panes", params: SessionParams(session: session))
    }

    func capturePaneContent(session: String, paneID: String, lines: Int) async throws -> String {
        nonisolated struct Result: Decodable { var content: String }
        let result: Result = try await call(
            method: "tmux.capture_pane",
            params: CapturePaneParams(session: session, pane_id: paneID, lines: lines)
        )
        return result.content
    }

    func sendKeys(session: String, paneID: String, keys: String) async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(
            method: "tmux.send_keys",
            params: SendKeysParams(session: session, pane_id: paneID, keys: keys)
        )
    }

    func listPorts() async throws -> [ListeningPortDTO] {
        try await call(method: "process.list_ports", params: EmptyParams())
    }

    func previewCandidates(workspacePath: String?) async throws -> [PreviewCandidateDTO] {
        try await call(method: "process.preview_candidates", params: WorkspacePathParams(workspace_path: workspacePath))
    }

    func gitStatus(repoPath: String) async throws -> GitStatusDTO {
        try await call(method: "git.status", params: RepoPathParams(repo_path: repoPath))
    }

    func gitDiffSummary(repoPath: String) async throws -> GitDiffSummaryDTO {
        try await call(method: "git.diff_summary", params: RepoPathParams(repo_path: repoPath))
    }

    func listRecentArtifacts(roots: [String], sinceHours: Int) async throws -> [ArtifactDTO] {
        try await call(method: "artifacts.list_recent", params: ArtifactsParams(roots: roots, since_hours: sinceHours))
    }

    func resumePlan(workspaceID: String) async throws -> ResumePlanDTO {
        try await call(method: "workspace.resume_plan", params: WorkspaceIDParams(workspace_id: workspaceID))
    }

    // MARK: - Phase 3: Git Write Operations

    func gitStage(repoPath: String, paths: [String]) async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(
            method: "git.stage",
            params: GitStageParams(repo_path: repoPath, paths: paths)
        )
    }

    func gitUnstage(repoPath: String, paths: [String]) async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(
            method: "git.unstage",
            params: GitStageParams(repo_path: repoPath, paths: paths)
        )
    }

    func gitCommit(repoPath: String, message: String, amend: Bool = false) async throws -> GitCommitResultDTO {
        try await call(
            method: "git.commit",
            params: GitCommitParams(repo_path: repoPath, message: message, amend: amend ? true : nil)
        )
    }

    func gitPush(repoPath: String, setUpstream: Bool = false) async throws -> GitPushResultDTO {
        try await call(
            method: "git.push",
            params: GitPushParams(repo_path: repoPath, set_upstream: setUpstream ? true : nil)
        )
    }

    func gitPull(repoPath: String, rebase: Bool = false) async throws -> GitPullResultDTO {
        try await call(
            method: "git.pull",
            params: GitPullParams(repo_path: repoPath, rebase: rebase ? true : nil)
        )
    }

    func gitBranchList(repoPath: String) async throws -> [GitBranchInfoDTO] {
        try await call(method: "git.branch_list", params: RepoPathParams(repo_path: repoPath))
    }

    func gitCheckout(repoPath: String, ref: String, create: Bool = false) async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(
            method: "git.checkout",
            params: GitCheckoutParams(repo_path: repoPath, ref_name: `ref`, create: create ? true : nil)
        )
    }

    func gitStash(repoPath: String, message: String? = nil) async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(
            method: "git.stash",
            params: GitStashParams(repo_path: repoPath, message: message)
        )
    }

    func gitStashPop(repoPath: String, index: Int? = nil) async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(
            method: "git.stash_pop",
            params: GitStashPopParams(repo_path: repoPath, index: index)
        )
    }

    func gitStashList(repoPath: String) async throws -> [GitStashEntryDTO] {
        try await call(method: "git.stash_list", params: RepoPathParams(repo_path: repoPath))
    }

    // MARK: - Phase 4: Proxy

    func proxyStart(listenPort: Int, routes: [ProxyRouteDTO]) async throws -> ProxyStatusDTO {
        let routeParams = routes.map {
            ProxyRouteParam(path_prefix: $0.path_prefix, target_port: $0.target_port, strip_prefix: $0.strip_prefix)
        }
        return try await call(
            method: "proxy.start",
            params: ProxyStartParams(listen_port: listenPort, routes: routeParams)
        )
    }

    func proxyStop() async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(method: "proxy.stop", params: EmptyParams())
    }

    func proxyStatus() async throws -> ProxyStatusDTO {
        try await call(method: "proxy.status", params: EmptyParams())
    }

    // MARK: - Phase 4: Tunnel

    func tunnelStartCloudflare(port: Int) async throws -> TunnelInfoDTO {
        try await call(method: "tunnel.start_cloudflare", params: TunnelPortParams(port: port))
    }

    func tunnelStartTailscale(port: Int) async throws -> TunnelInfoDTO {
        try await call(method: "tunnel.start_tailscale", params: TunnelPortParams(port: port))
    }

    func tunnelStop() async throws {
        nonisolated struct Result: Decodable { var ok: Bool }
        let _: Result = try await call(method: "tunnel.stop", params: EmptyParams())
    }

    func tunnelStatus() async throws -> TunnelInfoDTO? {
        nonisolated struct OptionalTunnel: Decodable {
            var provider: String?
            var public_url: String?
            var local_port: Int?
            var pid: Int?

            var toDTO: TunnelInfoDTO? {
                guard let provider, let public_url, let local_port, let pid else { return nil }
                return TunnelInfoDTO(provider: provider, public_url: public_url, local_port: local_port, pid: pid)
            }
        }
        let result: OptionalTunnel = try await call(method: "tunnel.status", params: EmptyParams())
        return result.toDTO
    }

    // MARK: - Phase 4: Testing

    func parseTestReport(path: String, format: String) async throws -> TestReportSummaryDTO {
        try await call(method: "testing.parse_report", params: TestReportParams(path: path, format: format))
    }
}

// MARK: - Helper Error

nonisolated enum HelperError: Error, LocalizedError, Sendable {
    case notConnected
    case disconnected
    case rpcError(code: Int, message: String)
    case emptyResult
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: "Helper not connected"
        case .disconnected: "Helper connection lost"
        case .rpcError(_, let message): "Helper error: \(message)"
        case .emptyResult: "Empty result from helper"
        case .timeout: "Helper request timed out"
        }
    }
}
