import SwiftUI
import SwiftData

/// List and manage team vaults.
struct TeamVaultView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var vaults: [TeamVaultRecord]

    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if vaults.isEmpty {
                ContentUnavailableView(
                    "No Team Vaults",
                    systemImage: "person.3",
                    description: Text("Create a vault to share hosts, snippets, and workspaces with your team.")
                )
            } else {
                List {
                    ForEach(vaults, id: \.id) { vault in
                        NavigationLink(value: TeamVaultNavigationTarget(id: vault.id)) {
                            VaultRow(vault: vault)
                        }
                    }
                    .onDelete(perform: deleteVaults)
                }
            }
        }
        .navigationTitle("Team Vaults")
        .navigationDestination(for: TeamVaultNavigationTarget.self) { target in
            if let vault = vaults.first(where: { $0.id == target.id }) {
                TeamVaultDetailView(vault: vault)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Create Vault", systemImage: "plus") {
                    showCreateSheet = true
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateVaultSheet { name, providerType in
                let vault = TeamVaultRecord(
                    name: name,
                    syncProviderType: providerType.rawValue
                )
                modelContext.insert(vault)
                showCreateSheet = false
            }
        }
    }

    private func deleteVaults(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(vaults[index])
        }
    }
}

private struct TeamVaultNavigationTarget: Hashable {
    let id: String
}

// MARK: - Vault Row

private struct VaultRow: View {
    let vault: TeamVaultRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vault.name)
                .font(.headline)
            HStack {
                if let type = SyncProviderType(rawValue: vault.syncProviderType) {
                    Label(type.displayName, systemImage: type.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let lastSync = vault.lastSyncDate {
                    Text(lastSync, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Create Vault Sheet

private struct CreateVaultSheet: View {
    let onCreate: (String, SyncProviderType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var providerType: SyncProviderType = .selfHosted

    private var validProviders: [SyncProviderType] {
        SyncProviderType.allCases.filter { $0 != .none }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vault Name") {
                    TextField("e.g. Team Infrastructure", text: $name)
                }
                Section("Sync Provider") {
                    Picker("Provider", selection: $providerType) {
                        ForEach(validProviders) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                }
            }
            .navigationTitle("New Team Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(name, providerType) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
