import Foundation

// MARK: - RPC Envelope

nonisolated struct HelperRPCRequest: Encodable, Sendable {
    var id: String
    var method: String
    var params: AnyCodable

    nonisolated init(id: String = UUID().uuidString, method: String, params: some Encodable) {
        self.id = id
        self.method = method
        self.params = AnyCodable(params)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encode(params, forKey: .params)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case method
        case params
    }
}

nonisolated struct HelperRPCResponse: Decodable, Sendable {
    var id: String
    var result: AnyCodable?
    var error: HelperRPCError?

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        result = try container.decodeIfPresent(AnyCodable.self, forKey: .result)
        error = try container.decodeIfPresent(HelperRPCError.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case error
    }
}

nonisolated struct HelperRPCError: Codable, Sendable {
    var code: Int
    var message: String
}

// MARK: - tmux DTOs

nonisolated struct TmuxSessionDTO: Codable, Sendable {
    var name: String
    var created: UInt64
    var attached: Bool
    var windows: Int
}

nonisolated struct TmuxPaneDTO: Codable, Sendable {
    var pane_id: String
    var window: String
    var index: Int
    var title: String
    var current_command: String
    var cwd: String
    var width: Int
    var height: Int
    var active: Bool
}

// MARK: - Process DTOs

nonisolated struct ListeningPortDTO: Codable, Sendable {
    var port: Int
    var pid: Int
    var process_name: String
    var cwd: String?
}

nonisolated struct PreviewCandidateDTO: Codable, Sendable {
    var port: Int
    var pid: Int
    var process_name: String
    var cwd: String?
    var framework_hint: String?
    var process_label: String?
    var health_hint: String?
    var startup_elapsed_secs: Int?
}

// MARK: - Git DTOs

nonisolated struct GitStatusDTO: Codable, Sendable {
    var branch: String
    var clean: Bool
    var staged: Int
    var modified: Int
    var untracked: Int
    var ahead: Int
    var behind: Int
    var files: [GitStatusFileDTO]?
}

nonisolated struct GitStatusFileDTO: Codable, Sendable {
    var path: String
    var index_status: String
    var worktree_status: String

    var isStaged: Bool { index_status != "." }
    var isModified: Bool { worktree_status != "." && worktree_status != "?" }
    var isUntracked: Bool { worktree_status == "?" }
}

nonisolated struct GitDiffSummaryDTO: Codable, Sendable {
    var files_changed: Int
    var insertions: Int
    var deletions: Int
    var file_list: [GitDiffFileDTO]
}

nonisolated struct GitDiffFileDTO: Codable, Sendable {
    var path: String
    var status: String
}

// MARK: - Git Write DTOs (Phase 3)

nonisolated struct GitCommitResultDTO: Codable, Sendable {
    var hash: String
    var message: String
}

nonisolated struct GitBranchInfoDTO: Codable, Sendable {
    var name: String
    var is_current: Bool
    var is_remote: Bool
    var upstream: String?
}

nonisolated struct GitPushResultDTO: Codable, Sendable {
    var ok: Bool
    var message: String
}

nonisolated struct GitPullResultDTO: Codable, Sendable {
    var ok: Bool
    var message: String
    var conflicts: [String]
}

nonisolated struct GitStashEntryDTO: Codable, Sendable {
    var index: Int
    var message: String
}

// MARK: - Artifact DTOs

nonisolated struct ArtifactDTO: Codable, Sendable {
    var path: String
    var size: UInt64
    var modified: UInt64
    var kind: String
}

// MARK: - Workspace DTOs

nonisolated struct ResumePlanDTO: Codable, Sendable {
    var tmux_session_exists: Bool
    var recommended_attach_target: String?
    var forward_candidates: [PreviewCandidateDTO]
    var recent_artifacts: [String]
}

// MARK: - Proxy DTOs (Phase 4)

nonisolated struct ProxyRouteDTO: Codable, Sendable {
    var path_prefix: String
    var target_port: Int
    var strip_prefix: Bool
}

nonisolated struct ProxyStatusDTO: Codable, Sendable {
    var running: Bool
    var listen_port: Int?
    var routes: [ProxyRouteDTO]
}

// MARK: - Tunnel DTOs (Phase 4)

nonisolated struct TunnelInfoDTO: Codable, Sendable {
    var provider: String
    var public_url: String
    var local_port: Int
    var pid: Int
}

// MARK: - Test Report DTOs (Phase 4)

nonisolated struct TestReportSummaryDTO: Codable, Sendable {
    var total: Int
    var passed: Int
    var failed: Int
    var skipped: Int
    var duration_secs: Double
    var failures: [TestFailureDTO]
}

nonisolated struct TestFailureDTO: Codable, Sendable {
    var name: String
    var message: String
    var file: String?
    var line: Int?
}

// MARK: - Type-erased Codable wrapper

nonisolated struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    nonisolated init(_ value: some Encodable) {
        self.value = value
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is NSNull {
            try container.encodeNil()
        } else if let encodable = value as? (any Encodable) {
            try encodable.encode(to: encoder)
        } else {
            try container.encodeNil()
        }
    }
}
