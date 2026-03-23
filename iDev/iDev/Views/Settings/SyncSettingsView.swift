import SwiftUI
import SwiftData

/// Settings screen for configuring BYO sync with a pluggable provider.
struct SyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [HostRecord]
    @Query private var workspaces: [WorkspaceRecord]
    @Query private var snippets: [SnippetRecord]

    @State private var selectedProvider: SyncProviderType = .none
    @State private var syncPassword = ""
    @State private var syncEngine = SyncEngine()

    // iCloud
    // (no additional config needed)

    // Git (GitHub API)
    @State private var gitRepo = ""       // owner/repo format
    @State private var gitBranch = "main"
    @State private var gitToken = ""

    // WebDAV
    @State private var webdavURL = ""
    @State private var webdavUsername = ""
    @State private var webdavPassword = ""

    // S3
    @State private var s3Endpoint = ""
    @State private var s3Bucket = ""
    @State private var s3Region = "us-east-1"
    @State private var s3AccessKey = ""
    @State private var s3SecretKey = ""

    // Self-Hosted
    @State private var selfHostedURL = ""
    @State private var selfHostedToken = ""

    private var canSync: Bool {
        !syncPassword.isEmpty && selectedProvider != .none && syncEngine.syncStatus != .syncing
    }

    var body: some View {
        Form {
            providerSection
            if selectedProvider != .none {
                providerConfigSection
                passwordSection
                syncActionsSection
            }
            statusSection
        }
        .navigationTitle("Sync")
        .onChange(of: selectedProvider) {
            configureProvider()
        }
    }

    // MARK: - Provider Picker

    private var providerSection: some View {
        Section("Provider") {
            Picker("Sync Provider", selection: $selectedProvider) {
                ForEach(SyncProviderType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
        }
    }

    // MARK: - Provider Config

    @ViewBuilder
    private var providerConfigSection: some View {
        switch selectedProvider {
        case .none:
            EmptyView()
        case .iCloudDrive:
            Section("iCloud Drive") {
                Label("Syncs via your iCloud Drive account. No additional configuration needed.", systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .git:
            Section("GitHub Repository") {
                TextField("Repository (owner/repo)", text: $gitRepo)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Branch", text: $gitBranch)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Personal Access Token", text: $gitToken)
            }
        case .webDAV:
            Section("WebDAV Server") {
                TextField("Server URL", text: $webdavURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Username", text: $webdavUsername)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $webdavPassword)
            }
        case .s3:
            Section("S3-Compatible Storage") {
                TextField("Endpoint URL", text: $s3Endpoint)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Bucket", text: $s3Bucket)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Region", text: $s3Region)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Access Key", text: $s3AccessKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Secret Key", text: $s3SecretKey)
            }
        case .selfHosted:
            Section("Self-Hosted Sync Server") {
                TextField("Server URL", text: $selfHostedURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Bearer Token (optional)", text: $selfHostedToken)
                Text("Run your own sync server with Docker. Data is encrypted locally — the server never sees plaintext.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Password

    private var passwordSection: some View {
        Section("Encryption") {
            SecureField("Sync Password", text: $syncPassword)
            Text("Your data is encrypted locally before syncing. The provider never sees your plaintext data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sync Actions

    private var syncActionsSection: some View {
        Section {
            Button {
                Task { await doSync() }
            } label: {
                if syncEngine.syncStatus == .syncing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!canSync)

            HStack {
                Button("Push") {
                    Task { await doPush() }
                }
                .disabled(!canSync)

                Spacer()

                Button("Pull") {
                    Task { await doPull() }
                }
                .disabled(!canSync)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            switch syncEngine.syncStatus {
            case .idle:
                Label("Not synced", systemImage: "circle")
                    .foregroundStyle(.secondary)
            case .syncing:
                Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tint)
            case .complete:
                Label("Sync complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.iDev.alive)
            case .error(let msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.iDev.danger)
            }

            if let lastSync = syncEngine.lastSyncDate {
                LabeledContent("Last Synced", value: lastSync.formatted(.relative(presentation: .named)))
            }
        }
    }

    // MARK: - Actions

    private func configureProvider() {
        switch selectedProvider {
        case .none:
            syncEngine.provider = nil
        case .iCloudDrive:
            syncEngine.provider = ICloudDriveSyncProvider()
        case .git:
            if !gitRepo.isEmpty, !gitToken.isEmpty {
                syncEngine.provider = GitSyncProvider(repo: gitRepo, branch: gitBranch, token: gitToken)
            }
        case .webDAV:
            if let url = URL(string: webdavURL), !webdavURL.isEmpty {
                syncEngine.provider = WebDAVSyncProvider(
                    serverURL: url,
                    username: webdavUsername.isEmpty ? nil : webdavUsername,
                    password: webdavPassword.isEmpty ? nil : webdavPassword
                )
            }
        case .s3:
            if let url = URL(string: s3Endpoint), !s3Endpoint.isEmpty {
                syncEngine.provider = S3SyncProvider(
                    endpoint: url,
                    bucket: s3Bucket,
                    region: s3Region,
                    accessKey: s3AccessKey,
                    secretKey: s3SecretKey
                )
            }
        case .selfHosted:
            if let url = URL(string: selfHostedURL), !selfHostedURL.isEmpty {
                syncEngine.provider = SelfHostedSyncProvider(
                    serverURL: url,
                    bearerToken: selfHostedToken.isEmpty ? nil : selfHostedToken
                )
            }
        }
    }

    private func doSync() async {
        configureProvider()
        await syncEngine.sync(
            password: syncPassword,
            hosts: hosts,
            workspaces: workspaces,
            snippets: snippets,
            modelContext: modelContext,
            vault: VaultService.shared
        )
    }

    private func doPush() async {
        configureProvider()
        await syncEngine.push(
            password: syncPassword,
            hosts: hosts,
            workspaces: workspaces,
            snippets: snippets
        )
    }

    private func doPull() async {
        configureProvider()
        await syncEngine.pull(
            password: syncPassword,
            existingHostIDs: Set(hosts.map(\.id)),
            existingWorkspaceIDs: Set(workspaces.map(\.id)),
            existingSnippetIDs: Set(snippets.map(\.id)),
            modelContext: modelContext,
            vault: VaultService.shared
        )
    }
}
