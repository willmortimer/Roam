import Foundation

struct SyncSettingsDraft: Codable, Equatable, Sendable {
    var selectedProvider: SyncProviderType = .none
    var syncPassword = ""

    var gitRepo = ""
    var gitBranch = "main"
    var gitToken = ""

    var webdavURL = ""
    var webdavUsername = ""
    var webdavPassword = ""

    var s3Endpoint = ""
    var s3Bucket = ""
    var s3Region = "us-east-1"
    var s3AccessKey = ""
    var s3SecretKey = ""

    var selfHostedURL = ""
    var selfHostedToken = ""
}

private struct StoredSyncSettingsConfiguration: Codable {
    var selectedProvider: SyncProviderType
    var gitRepo: String
    var gitBranch: String
    var webdavURL: String
    var webdavUsername: String
    var s3Endpoint: String
    var s3Bucket: String
    var s3Region: String
    var selfHostedURL: String
}

final class SyncProviderConfigurationStore {
    private let defaults: UserDefaults
    private let vault: VaultService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let configurationKey = "sync.provider.configuration.v1"
    private let syncPasswordSecretID = "sync_password"
    private let gitTokenSecretID = "sync_git_token"
    private let webDAVPasswordSecretID = "sync_webdav_password"
    private let s3AccessKeySecretID = "sync_s3_access_key"
    private let s3SecretKeySecretID = "sync_s3_secret_key"
    private let selfHostedTokenSecretID = "sync_selfhosted_token"

    init(defaults: UserDefaults = .standard, vault: VaultService = .shared) {
        self.defaults = defaults
        self.vault = vault
    }

    func load() -> SyncSettingsDraft {
        var draft = SyncSettingsDraft()

        if let data = defaults.data(forKey: configurationKey),
           let stored = try? decoder.decode(StoredSyncSettingsConfiguration.self, from: data) {
            draft.selectedProvider = stored.selectedProvider
            draft.gitRepo = stored.gitRepo
            draft.gitBranch = stored.gitBranch
            draft.webdavURL = stored.webdavURL
            draft.webdavUsername = stored.webdavUsername
            draft.s3Endpoint = stored.s3Endpoint
            draft.s3Bucket = stored.s3Bucket
            draft.s3Region = stored.s3Region
            draft.selfHostedURL = stored.selfHostedURL
        }

        draft.syncPassword = loadSecret(syncPasswordSecretID)
        draft.gitToken = loadSecret(gitTokenSecretID)
        draft.webdavPassword = loadSecret(webDAVPasswordSecretID)
        draft.s3AccessKey = loadSecret(s3AccessKeySecretID)
        draft.s3SecretKey = loadSecret(s3SecretKeySecretID)
        draft.selfHostedToken = loadSecret(selfHostedTokenSecretID)

        return draft
    }

    func save(_ draft: SyncSettingsDraft) {
        let stored = StoredSyncSettingsConfiguration(
            selectedProvider: draft.selectedProvider,
            gitRepo: draft.gitRepo,
            gitBranch: draft.gitBranch,
            webdavURL: draft.webdavURL,
            webdavUsername: draft.webdavUsername,
            s3Endpoint: draft.s3Endpoint,
            s3Bucket: draft.s3Bucket,
            s3Region: draft.s3Region,
            selfHostedURL: draft.selfHostedURL
        )

        if let data = try? encoder.encode(stored) {
            defaults.set(data, forKey: configurationKey)
        }

        saveSecret(draft.syncPassword, id: syncPasswordSecretID)
        saveSecret(draft.gitToken, id: gitTokenSecretID)
        saveSecret(draft.webdavPassword, id: webDAVPasswordSecretID)
        saveSecret(draft.s3AccessKey, id: s3AccessKeySecretID)
        saveSecret(draft.s3SecretKey, id: s3SecretKeySecretID)
        saveSecret(draft.selfHostedToken, id: selfHostedTokenSecretID)
    }

    private func loadSecret(_ id: String) -> String {
        (try? vault.loadSecret(id: id)) ?? ""
    }

    private func saveSecret(_ value: String, id: String) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? vault.deleteSecret(id: id)
        } else {
            try? vault.storeSecret(id: id, secret: value)
        }
    }
}

struct TeamVaultSyncConfiguration: Codable, Equatable, Sendable {
    var serverURL = ""
}

final class TeamVaultSyncConfigurationStore {
    private let vaultService: VaultService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(vaultService: VaultService = .shared) {
        self.vaultService = vaultService
    }

    func load(for vault: TeamVaultRecord) -> TeamVaultSyncConfiguration {
        guard let data = vault.syncConfigData,
              let config = try? decoder.decode(TeamVaultSyncConfiguration.self, from: data) else {
            return TeamVaultSyncConfiguration()
        }
        return config
    }

    func loadBearerToken(for vault: TeamVaultRecord) -> String {
        (try? vaultService.loadSecret(id: tokenSecretID(for: vault))) ?? ""
    }

    func save(_ configuration: TeamVaultSyncConfiguration, bearerToken: String, for vault: TeamVaultRecord) {
        vault.syncConfigData = try? encoder.encode(configuration)

        if bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? vaultService.deleteSecret(id: tokenSecretID(for: vault))
        } else {
            try? vaultService.storeSecret(id: tokenSecretID(for: vault), secret: bearerToken)
        }
    }

    private func tokenSecretID(for vault: TeamVaultRecord) -> String {
        "team_vault_\(vault.id)_bearer_token"
    }
}
