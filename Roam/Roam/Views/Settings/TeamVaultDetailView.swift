import SwiftUI
import SwiftData

/// Detail view for a team vault — shows contents, sync status, push/pull.
struct TeamVaultDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var vault: TeamVaultRecord

    @Query private var allHosts: [HostRecord]
    @Query private var allWorkspaces: [WorkspaceRecord]
    @Query private var allSnippets: [SnippetRecord]

    @State private var vaultService = TeamVaultService()
    @State private var passphrase = ""

    // Self-hosted config (shown when provider is selfHosted)
    @State private var serverURL = ""
    @State private var bearerToken = ""
    @State private var hasLoadedProviderConfig = false

    private let configurationStore = TeamVaultSyncConfigurationStore()

    private var vaultHosts: [HostRecord] {
        allHosts.filter { $0.vaultScope == vault.id }
    }

    private var vaultWorkspaces: [WorkspaceRecord] {
        allWorkspaces.filter { $0.vaultScope == vault.id }
    }

    private var vaultSnippets: [SnippetRecord] {
        allSnippets.filter { $0.vaultScope == vault.id }
    }

    private var canSync: Bool {
        !passphrase.isEmpty && vaultService.syncStatus != .syncing
    }

    var body: some View {
        Form {
            contentsSection
            providerConfigSection
            passphraseSection
            syncActionsSection
            statusSection
            manageSection
        }
        .navigationTitle(vault.name)
        .task {
            loadProviderConfigurationIfNeeded()
        }
        .onChange(of: serverURL) {
            persistProviderConfiguration()
        }
        .onChange(of: bearerToken) {
            persistProviderConfiguration()
        }
    }

    // MARK: - Contents

    private var contentsSection: some View {
        Section("Contents") {
            LabeledContent("Hosts", value: "\(vaultHosts.count)")
            LabeledContent("Workspaces", value: "\(vaultWorkspaces.count)")
            LabeledContent("Snippets", value: "\(vaultSnippets.count)")
        }
    }

    // MARK: - Provider Config

    @ViewBuilder
    private var providerConfigSection: some View {
        if vault.syncProviderType == SyncProviderType.selfHosted.rawValue {
            Section("Self-Hosted Server") {
                TextField("Server URL", text: $serverURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Bearer Token (optional)", text: $bearerToken)
                Label("Stored on this device and reused for future vault syncs.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Passphrase

    private var passphraseSection: some View {
        Section("Encryption") {
            SecureField("Vault Passphrase", text: $passphrase)
            Text("All team members use the same passphrase to access this vault.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sync Actions

    private var syncActionsSection: some View {
        Section {
            HStack {
                Button {
                    Task { await doPush() }
                } label: {
                    Label("Push", systemImage: "arrow.up.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSync)

                Button {
                    Task { await doPull() }
                } label: {
                    Label("Pull", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSync)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section("Status") {
            switch vaultService.syncStatus {
            case .idle:
                Label("Ready", systemImage: "circle")
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

            if let lastSync = vault.lastSyncDate {
                LabeledContent("Last Synced", value: lastSync.formatted(.relative(presentation: .named)))
            }
        }
    }

    // MARK: - Manage

    private var manageSection: some View {
        Section("Manage Items") {
            NavigationLink("Add Hosts to Vault") {
                AddToVaultView(vaultID: vault.id, items: allHosts.filter { $0.vaultScope == nil }) { host in
                    host.vaultScope = vault.id
                }
            }
            NavigationLink("Add Snippets to Vault") {
                AddToVaultView(vaultID: vault.id, items: allSnippets.filter { $0.vaultScope == nil }) { snippet in
                    snippet.vaultScope = vault.id
                }
            }
        }
    }

    // MARK: - Actions

    private func makeProvider() -> (any SyncProvider)? {
        guard let type = SyncProviderType(rawValue: vault.syncProviderType) else { return nil }
        switch type {
        case .selfHosted:
            guard let url = URL(string: serverURL), !serverURL.isEmpty else { return nil }
            return SelfHostedSyncProvider(serverURL: url, bearerToken: bearerToken.isEmpty ? nil : bearerToken)
        default:
            return nil // Other providers would be configured here
        }
    }

    private func doPush() async {
        guard let provider = makeProvider() else { return }
        await vaultService.pushToVault(
            vault,
            passphrase: passphrase,
            hosts: allHosts,
            snippets: allSnippets,
            workspaces: allWorkspaces,
            provider: provider
        )
    }

    private func doPull() async {
        guard let provider = makeProvider() else { return }
        await vaultService.pullFromVault(
            vault,
            passphrase: passphrase,
            existingHostIDs: Set(allHosts.map(\.id)),
            existingWorkspaceIDs: Set(allWorkspaces.map(\.id)),
            existingSnippetIDs: Set(allSnippets.map(\.id)),
            modelContext: modelContext,
            vaultService: VaultService.shared,
            provider: provider
        )
    }

    private func loadProviderConfigurationIfNeeded() {
        guard !hasLoadedProviderConfig else { return }
        let configuration = configurationStore.load(for: vault)
        serverURL = configuration.serverURL
        bearerToken = configurationStore.loadBearerToken(for: vault)
        hasLoadedProviderConfig = true
    }

    private func persistProviderConfiguration() {
        guard hasLoadedProviderConfig else { return }
        configurationStore.save(
            TeamVaultSyncConfiguration(serverURL: serverURL),
            bearerToken: bearerToken,
            for: vault
        )
        try? modelContext.save()
    }
}

// MARK: - Add to Vault View

private struct AddToVaultView<T: PersistentModel>: View {
    let vaultID: String
    let items: [T]
    let onAdd: (T) -> Void

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Items Available",
                    systemImage: "tray",
                    description: Text("All items are already in a vault or none exist yet.")
                )
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        onAdd(item)
                    } label: {
                        HStack {
                            Text(String(describing: item))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add to Vault")
    }
}
