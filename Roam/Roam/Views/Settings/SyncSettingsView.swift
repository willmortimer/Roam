import SwiftUI
import SwiftData

/// Settings screen for configuring BYO sync with a pluggable provider.
struct SyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [HostRecord]
    @Query private var workspaces: [WorkspaceRecord]
    @Query private var snippets: [SnippetRecord]

    @State private var settings = SyncSettingsDraft()
    @State private var syncEngine = SyncEngine()
    @State private var hasLoadedPersistedSettings = false

    private let configurationStore = SyncProviderConfigurationStore()

    private var canSync: Bool {
        !settings.syncPassword.isEmpty &&
        syncEngine.syncStatus != .syncing &&
        syncEngine.provider != nil
    }

    private var canResolveConflict: Bool {
        canSync && syncEngine.pendingConflict != nil
    }

    var body: some View {
        Form {
            providerSection
            if settings.selectedProvider != .none {
                providerConfigSection
                passwordSection
                syncActionsSection
                if let conflict = syncEngine.pendingConflict {
                    conflictSection(conflict)
                }
            }
            statusSection
        }
        .navigationTitle("Sync")
        .task {
            loadPersistedSettingsIfNeeded()
        }
        .onChange(of: settings) {
            guard hasLoadedPersistedSettings else { return }
            configurationStore.save(settings)
            syncEngine.clearPendingConflict()
            configureProvider()
        }
    }

    // MARK: - Provider Picker

    private var providerSection: some View {
        Section("Provider") {
            Picker("Sync Provider", selection: $settings.selectedProvider) {
                ForEach(SyncProviderType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
        }
    }

    // MARK: - Provider Config

    @ViewBuilder
    private var providerConfigSection: some View {
        switch settings.selectedProvider {
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
                TextField("Repository (owner/repo)", text: $settings.gitRepo)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Branch", text: $settings.gitBranch)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Personal Access Token", text: $settings.gitToken)
            }
        case .webDAV:
            Section("WebDAV Server") {
                TextField("Server URL", text: $settings.webdavURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Username", text: $settings.webdavUsername)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $settings.webdavPassword)
            }
        case .s3:
            Section("S3-Compatible Storage") {
                TextField("Endpoint URL", text: $settings.s3Endpoint)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Bucket", text: $settings.s3Bucket)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Region", text: $settings.s3Region)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Access Key", text: $settings.s3AccessKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Secret Key", text: $settings.s3SecretKey)
            }
        case .selfHosted:
            Section("Self-Hosted Sync Server") {
                TextField("Server URL", text: $settings.selfHostedURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Bearer Token (optional)", text: $settings.selfHostedToken)
                Label("Run your own sync server with Docker. Data is encrypted locally and this configuration is stored on-device.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Password

    private var passwordSection: some View {
        Section("Encryption") {
            SecureField("Sync Password", text: $settings.syncPassword)
            Text("Your data is encrypted locally before syncing. The provider never sees your plaintext data. The password is stored in Keychain on this device.")
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

            if settings.selectedProvider != .none && syncEngine.provider == nil {
                Text("Complete the selected provider configuration to enable sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Conflict Review

    private func conflictSection(_ conflict: SyncConflictState) -> some View {
        Section("Remote Changes") {
            VStack(alignment: .leading, spacing: 10) {
                Text(conflict.statusMessage)
                    .font(.subheadline.weight(.semibold))

                LabeledContent("Remote Export", value: conflict.preview.exportedAt)

                if conflict.remoteOnlyHosts > 0 {
                    LabeledContent("New Hosts", value: "\(conflict.remoteOnlyHosts)")
                }
                if conflict.remoteOnlyWorkspaces > 0 {
                    LabeledContent("New Workspaces", value: "\(conflict.remoteOnlyWorkspaces)")
                }
                if conflict.remoteOnlySnippets > 0 {
                    LabeledContent("New Snippets", value: "\(conflict.remoteOnlySnippets)")
                }

                if conflict.hasConflicts {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Conflicting Items")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(conflict.conflicts.prefix(5))) { item in
                            Text(item.displayTitle)
                                .font(.caption)
                        }

                        if conflict.conflicts.count > 5 {
                            Text("+ \(conflict.conflicts.count - 5) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button {
                Task { await useRemoteChanges() }
            } label: {
                Label("Use Remote Changes", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canResolveConflict)

            Button {
                Task { await keepLocalChanges() }
            } label: {
                Label("Keep Local and Push", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canResolveConflict)
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
                    .foregroundStyle(.Roam.alive)
            case .error(let msg):
                Label(msg, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.Roam.danger)
            }

            if let lastSync = syncEngine.lastSyncDate {
                LabeledContent("Last Synced", value: lastSync.formatted(.relative(presentation: .named)))
            }
        }
    }

    // MARK: - Actions

    private func loadPersistedSettingsIfNeeded() {
        guard !hasLoadedPersistedSettings else { return }
        settings = configurationStore.load()
        configureProvider()
        hasLoadedPersistedSettings = true
    }

    private func configureProvider() {
        syncEngine.provider = makeProvider()
    }

    private func makeProvider() -> (any SyncProvider)? {
        switch settings.selectedProvider {
        case .none:
            return nil
        case .iCloudDrive:
            return ICloudDriveSyncProvider()
        case .git:
            guard !settings.gitRepo.isEmpty, !settings.gitToken.isEmpty else { return nil }
            return GitSyncProvider(
                repo: settings.gitRepo,
                branch: settings.gitBranch.isEmpty ? "main" : settings.gitBranch,
                token: settings.gitToken
            )
        case .webDAV:
            guard let url = URL(string: settings.webdavURL), !settings.webdavURL.isEmpty else { return nil }
            return WebDAVSyncProvider(
                serverURL: url,
                username: settings.webdavUsername.isEmpty ? nil : settings.webdavUsername,
                password: settings.webdavPassword.isEmpty ? nil : settings.webdavPassword
            )
        case .s3:
            guard let url = URL(string: settings.s3Endpoint),
                  !settings.s3Endpoint.isEmpty,
                  !settings.s3Bucket.isEmpty,
                  !settings.s3AccessKey.isEmpty,
                  !settings.s3SecretKey.isEmpty else { return nil }
            return S3SyncProvider(
                endpoint: url,
                bucket: settings.s3Bucket,
                region: settings.s3Region.isEmpty ? "us-east-1" : settings.s3Region,
                accessKey: settings.s3AccessKey,
                secretKey: settings.s3SecretKey
            )
        case .selfHosted:
            guard let url = URL(string: settings.selfHostedURL), !settings.selfHostedURL.isEmpty else { return nil }
            return SelfHostedSyncProvider(
                serverURL: url,
                bearerToken: settings.selfHostedToken.isEmpty ? nil : settings.selfHostedToken
            )
        }
    }

    private func doSync() async {
        configureProvider()
        await syncEngine.sync(
            password: settings.syncPassword,
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
            password: settings.syncPassword,
            hosts: hosts,
            workspaces: workspaces,
            snippets: snippets
        )
    }

    private func doPull() async {
        configureProvider()
        await syncEngine.pull(
            password: settings.syncPassword,
            existingHostIDs: Set(hosts.map(\.id)),
            existingWorkspaceIDs: Set(workspaces.map(\.id)),
            existingSnippetIDs: Set(snippets.map(\.id)),
            modelContext: modelContext,
            vault: VaultService.shared
        )
    }

    private func useRemoteChanges() async {
        configureProvider()
        await syncEngine.useRemoteChanges(
            password: settings.syncPassword,
            hosts: hosts,
            workspaces: workspaces,
            snippets: snippets,
            modelContext: modelContext,
            vault: VaultService.shared
        )
    }

    private func keepLocalChanges() async {
        configureProvider()
        await syncEngine.keepLocalChanges(
            password: settings.syncPassword,
            hosts: hosts,
            workspaces: workspaces,
            snippets: snippets
        )
    }
}
