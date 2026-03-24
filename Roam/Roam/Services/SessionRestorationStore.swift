import Foundation

enum SessionRestorationSource: String, Codable, Hashable, Sendable {
    case directHost
    case workspace
}

struct SessionRestorationContext: Codable, Hashable, Sendable {
    let id: String
    let source: SessionRestorationSource
    let hostID: String
    let workspaceID: String?
    let workspaceName: String?

    static func directHost(host: HostRecord, restorationID: String = UUID().uuidString) -> SessionRestorationContext {
        SessionRestorationContext(
            id: restorationID,
            source: .directHost,
            hostID: host.id,
            workspaceID: nil,
            workspaceName: nil
        )
    }

    static func workspace(
        host: HostRecord,
        workspace: WorkspaceRecord,
        restorationID: String = UUID().uuidString
    ) -> SessionRestorationContext {
        SessionRestorationContext(
            id: restorationID,
            source: .workspace,
            hostID: host.id,
            workspaceID: workspace.id,
            workspaceName: workspace.name
        )
    }
}

enum SessionRestoreStatus: String, Codable, Hashable, Sendable {
    case pending
    case restoring
    case failed

    var title: String {
        switch self {
        case .pending:
            "Pending"
        case .restoring:
            "Restoring"
        case .failed:
            "Failed"
        }
    }
}

struct PersistedSessionSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let source: SessionRestorationSource
    let hostID: String
    let hostAlias: String
    let username: String
    let hostname: String
    let port: Int
    let workspaceID: String?
    let workspaceName: String?
    var restoreStatus: SessionRestoreStatus
    var lastErrorMessage: String?
    let createdAt: Date
    var updatedAt: Date

    var displayName: String {
        workspaceName ?? hostAlias
    }

    var restorationContext: SessionRestorationContext {
        SessionRestorationContext(
            id: id,
            source: source,
            hostID: hostID,
            workspaceID: workspaceID,
            workspaceName: workspaceName
        )
    }
}

struct SessionRestorationStore {
    private let defaults: UserDefaults
    private let storageKey = "roam.persistedSessionSnapshots.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [PersistedSessionSnapshot] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([PersistedSessionSnapshot].self, from: data)
        } catch {
            defaults.removeObject(forKey: storageKey)
            return []
        }
    }

    func save(_ snapshots: [PersistedSessionSnapshot]) {
        guard !snapshots.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }

        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }

        defaults.set(data, forKey: storageKey)
    }
}
