import Foundation
import Yams

/// Encodes and decodes workspace definitions to/from YAML format
/// matching the schema in the design spec (Section 13.2).
nonisolated enum WorkspaceYAMLCodec {

    /// Encode a WorkspaceRecord to YAML string.
    static func encode(_ workspace: WorkspaceRecord) throws -> String {
        var dict: [String: Any] = [
            "version": 1,
            "id": workspace.id,
            "name": workspace.name,
            "description": workspace.descriptionText,
            "environment": workspace.environment,
            "host_ref": workspace.hostReference,
            "shell": workspace.shell,
            "repo_path": workspace.repoPath,
            "startup_dir": workspace.startupDir,
        ]

        // tmux
        var tmuxDict: [String: Any] = [
            "session_name": workspace.tmuxSessionName,
            "attach_policy": "resume_or_create",
        ]
        if let layout = workspace.tmuxLayoutTemplate {
            tmuxDict["layout"] = layout
        }
        let panes = workspace.tmuxPanes.map { pane -> [String: String] in
            ["role": pane.role.rawValue, "window": pane.window]
        }
        if !panes.isEmpty {
            tmuxDict["panes"] = panes
        }
        dict["tmux"] = tmuxDict

        if let agent = workspace.preferredAgentCommand {
            dict["preferred_agent_command"] = agent
        }

        // forwards
        let forwards = workspace.savedForwards.map { fwd -> [String: Any] in
            var d: [String: Any] = [
                "name": fwd.name,
                "remote_host": fwd.remoteHost,
                "remote_port": fwd.remotePort,
                "auto_preview": fwd.autoPreview,
            ]
            if let local = fwd.localPort {
                d["local_port"] = local
            }
            return d
        }
        if !forwards.isEmpty {
            dict["saved_forwards"] = forwards
        }

        // preview rules
        let rules = workspace.previewRules
        dict["preview_rules"] = [
            "auto_detect": rules.autoDetect,
            "open_in_app": rules.openInApp,
        ]

        if !workspace.artifactRoots.isEmpty {
            dict["artifact_roots"] = workspace.artifactRoots
        }
        if !workspace.notes.isEmpty {
            dict["notes"] = workspace.notes
        }
        if !workspace.tags.isEmpty {
            dict["tags"] = workspace.tags
        }
        dict["trust_zone"] = workspace.trustZone

        return try Yams.dump(object: dict, allowUnicode: true)
    }

    /// Decode a YAML string into workspace field values.
    /// Returns a tuple of values that can be used to create or update a WorkspaceRecord.
    static func decode(_ yaml: String) throws -> WorkspaceYAMLFields {
        guard let dict = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw YAMLCodecError.invalidFormat
        }

        let tmux = dict["tmux"] as? [String: Any] ?? [:]
        let panesRaw = tmux["panes"] as? [[String: String]] ?? []
        let panes = panesRaw.compactMap { d -> PaneDefinition? in
            guard let roleStr = d["role"], let role = PaneRole(rawValue: roleStr),
                  let window = d["window"] else { return nil }
            return PaneDefinition(role: role, window: window)
        }

        let forwardsRaw = dict["saved_forwards"] as? [[String: Any]] ?? []
        let forwards = forwardsRaw.compactMap { d -> ForwardDefinition? in
            guard let name = d["name"] as? String,
                  let remotePort = d["remote_port"] as? Int else { return nil }
            return ForwardDefinition(
                name: name,
                remoteHost: d["remote_host"] as? String ?? "127.0.0.1",
                remotePort: remotePort,
                localPort: d["local_port"] as? Int,
                autoPreview: d["auto_preview"] as? Bool ?? false
            )
        }

        let previewDict = dict["preview_rules"] as? [String: Any] ?? [:]

        return WorkspaceYAMLFields(
            id: dict["id"] as? String,
            name: dict["name"] as? String ?? "Untitled",
            descriptionText: dict["description"] as? String ?? "",
            environment: dict["environment"] as? String ?? "dev",
            hostReference: dict["host_ref"] as? String ?? "",
            shell: dict["shell"] as? String ?? "/bin/zsh",
            repoPath: dict["repo_path"] as? String ?? "",
            startupDir: dict["startup_dir"] as? String ?? "",
            tmuxSessionName: tmux["session_name"] as? String ?? "",
            tmuxLayoutTemplate: tmux["layout"] as? String,
            tmuxPanes: panes,
            preferredAgentCommand: dict["preferred_agent_command"] as? String,
            savedForwards: forwards,
            previewRules: PreviewRulesConfig(
                autoDetect: previewDict["auto_detect"] as? Bool ?? true,
                openInApp: previewDict["open_in_app"] as? Bool ?? true
            ),
            artifactRoots: dict["artifact_roots"] as? [String] ?? [],
            notes: dict["notes"] as? String ?? "",
            tags: dict["tags"] as? [String] ?? [],
            trustZone: dict["trust_zone"] as? String ?? "trusted_dev"
        )
    }
}

/// Decoded workspace fields from YAML.
nonisolated struct WorkspaceYAMLFields: Sendable {
    var id: String?
    var name: String
    var descriptionText: String
    var environment: String
    var hostReference: String
    var shell: String
    var repoPath: String
    var startupDir: String
    var tmuxSessionName: String
    var tmuxLayoutTemplate: String?
    var tmuxPanes: [PaneDefinition]
    var preferredAgentCommand: String?
    var savedForwards: [ForwardDefinition]
    var previewRules: PreviewRulesConfig
    var artifactRoots: [String]
    var notes: String
    var tags: [String]
    var trustZone: String
}

nonisolated enum YAMLCodecError: Error, LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        "Invalid YAML format"
    }
}
