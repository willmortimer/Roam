import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct VaultView: View {
    @State private var selectedSection: VaultSection = .keys
    @State private var showingKeyGenerator = false
    @State private var showingKeyImport = false

    var body: some View {
        List {
            Picker("Section", selection: $selectedSection) {
                ForEach(VaultSection.allCases, id: \.self) { section in
                    Text(section.title)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            switch selectedSection {
            case .keys:
                KeyListSection(showingKeyImport: $showingKeyImport)
            case .knownHosts:
                KnownHostsSection()
            }
        }
        .navigationTitle("Vault")
        .toolbar {
            if selectedSection == .keys {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add Key", systemImage: "plus") {
                        Button("Generate New Key", systemImage: "wand.and.stars") {
                            showingKeyGenerator = true
                        }
                        Button("Import Key", systemImage: "square.and.arrow.down") {
                            showingKeyImport = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingKeyGenerator) {
            NavigationStack {
                KeyGeneratorView()
            }
        }
        .sheet(isPresented: $showingKeyImport) {
            NavigationStack {
                KeyImportView()
            }
        }
    }
}

enum VaultSection: String, CaseIterable {
    case keys
    case knownHosts

    var title: String {
        switch self {
        case .keys: "SSH Keys"
        case .knownHosts: "Known Hosts"
        }
    }
}

// MARK: - Key List

struct KeyListSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]
    @Binding var showingKeyImport: Bool
    @State private var selectedKey: SSHKeyRecord?
    @State private var showDeleteConfirmation = false
    @State private var keyToDelete: SSHKeyRecord?
    @State private var renamingKey: SSHKeyRecord?
    @State private var renameText = ""

    var body: some View {
        Group {
            if keys.isEmpty {
                ContentUnavailableView(
                    "No SSH Keys",
                    systemImage: "key",
                    description: Text("Generate or import an SSH key to authenticate with hosts.")
                )
            } else {
                ForEach(keys, id: \.id) { key in
                    Button {
                        selectedKey = key
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(key.label)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: Spacing.sm) {
                                    Text(key.keyType.displayName)
                                        .codeBadge(color: .accentColor)
                                    if key.isEncrypted {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(key.createdAt, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contextMenu {
                        Button("Copy Public Key", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = key.publicKeyAuthorizedFormat
                        }
                        Button("Rename", systemImage: "pencil") {
                            renameText = key.label
                            renamingKey = key
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            keyToDelete = key
                            showDeleteConfirmation = true
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            keyToDelete = key
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
        }
        // Key detail sheet
        .sheet(item: $selectedKey) { key in
            NavigationStack {
                KeyDetailSheet(key: key)
            }
        }
        // Rename sheet
        .sheet(isPresented: .init(
            get: { renamingKey != nil },
            set: { if !$0 { renamingKey = nil } }
        )) {
            NavigationStack {
                Form {
                    Section("Key Label") {
                        TextField("Label", text: $renameText)
                    }
                }
                .navigationTitle("Rename Key")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { renamingKey = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            renamingKey?.label = renameText
                            renamingKey = nil
                        }
                        .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        // Delete confirmation
        .alert("Delete Key?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { keyToDelete = nil }
            Button("Delete", role: .destructive) {
                if let key = keyToDelete {
                    deleteKey(key)
                }
                keyToDelete = nil
            }
        } message: {
            Text("This will permanently remove the key \"\(keyToDelete?.label ?? "")\" and its private key from the Keychain. Hosts using this key will need a new key assigned.")
        }
    }

    private func deleteKey(_ key: SSHKeyRecord) {
        try? VaultService.shared.deletePrivateKey(id: key.id)
        try? VaultService.shared.deletePassphrase(keyID: key.id)
        modelContext.delete(key)
    }
}

// MARK: - Key Detail Sheet

private struct KeyDetailSheet: View {
    let key: SSHKeyRecord
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        List {
            Section("Key Info") {
                LabeledContent("Label", value: key.label)
                LabeledContent("Type", value: key.keyType.displayName)
                LabeledContent("Created", value: key.createdAt.formatted(date: .abbreviated, time: .shortened))
                if key.isEncrypted {
                    LabeledContent("Encrypted") {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.Roam.alive)
                    }
                }
            }

            Section {
                Text(key.publicKeyAuthorizedFormat)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = key.publicKeyAuthorizedFormat
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(
                        copied ? "Copied" : "Copy to Clipboard",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
            } header: {
                Text("Public Key")
            } footer: {
                Text("Add this public key to ~/.ssh/authorized_keys on your remote hosts.")
            }

            if !key.notes.isEmpty {
                Section("Notes") {
                    Text(key.notes)
                }
            }
        }
        .navigationTitle(key.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

// MARK: - Key Import View

struct KeyImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var privateKeyText = ""
    @State private var passphrase = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var showingFilePicker = false

    var body: some View {
        Form {
            Section {
                TextField("Key Label", text: $label)
            } footer: {
                Text("A name to identify this key (e.g. \"work laptop\", \"deploy key\").")
            }

            Section {
                TextEditor(text: $privateKeyText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Choose File", systemImage: "doc") {
                    showingFilePicker = true
                }
            } header: {
                Text("Private Key")
            } footer: {
                Text("Paste your private key (begins with -----BEGIN OPENSSH PRIVATE KEY-----) or choose a file.")
            }

            Section {
                SecureField("Passphrase (if encrypted)", text: $passphrase)
            } footer: {
                Text("Leave blank if your key is not passphrase-protected.")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.Roam.danger)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Import Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    Task { await importKey() }
                }
                .disabled(label.isEmpty || privateKeyText.isEmpty || isImporting)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    loadKeyFile(url)
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadKeyFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                privateKeyText = text
                if label.isEmpty {
                    label = url.deletingPathExtension().lastPathComponent
                }
            } else {
                errorMessage = "The file doesn't appear to be a text-based SSH key."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importKey() async {
        isImporting = true
        errorMessage = nil

        let trimmed = privateKeyText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect key type from the PEM header
        let keyType: SSHKeyType
        if trimmed.contains("ed25519") {
            keyType = .ed25519
        } else if trimmed.contains("ecdsa") || trimmed.contains("EC") {
            keyType = .ecdsaP256
        } else {
            keyType = .rsa4096
        }

        // Extract public key from private key (simplified — store the private key and derive public info)
        // For import, we store the private key in keychain and extract a placeholder public key
        guard let privateKeyData = trimmed.data(using: .utf8) else {
            errorMessage = "Failed to encode key data."
            isImporting = false
            return
        }

        // Build a basic authorized_keys format from the key type and label
        let publicKeyFormat = "[\(keyType.displayName) key — imported] \(label)"

        let record = SSHKeyRecord(
            label: label,
            keyType: keyType,
            publicKeyData: Data(),
            publicKeyAuthorizedFormat: publicKeyFormat,
            isEncrypted: !passphrase.isEmpty,
            keychainReference: ""
        )

        do {
            try VaultService.shared.storePrivateKey(id: record.id, data: privateKeyData)
            if !passphrase.isEmpty {
                try VaultService.shared.storePassphrase(keyID: record.id, passphrase: passphrase)
            }
            record.keychainReference = record.id
            modelContext.insert(record)
            dismiss()
        } catch {
            errorMessage = "Failed to store key: \(error.localizedDescription)"
        }

        isImporting = false
    }
}

// MARK: - Known Hosts

struct KnownHostsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnownHostRecord.hostname) private var knownHosts: [KnownHostRecord]
    @State private var showDeleteConfirmation = false
    @State private var hostToDelete: KnownHostRecord?

    var body: some View {
        if knownHosts.isEmpty {
            ContentUnavailableView(
                "No Known Hosts",
                systemImage: "checkmark.shield",
                description: Text("Host fingerprints will appear here after your first connection.")
            )
        } else {
            ForEach(knownHosts, id: \.id) { kh in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("\(kh.hostname):\(kh.port)")
                        .font(.headline)
                    HStack(spacing: Spacing.sm) {
                        Text(kh.algorithm)
                            .codeBadge(color: .secondary)
                        Text(kh.fingerprint)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("First seen \(kh.firstSeen.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contextMenu {
                    Button("Copy Fingerprint", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = kh.fingerprint
                    }
                    Divider()
                    Button("Remove Trust", systemImage: "trash", role: .destructive) {
                        hostToDelete = kh
                        showDeleteConfirmation = true
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Remove", role: .destructive) {
                        hostToDelete = kh
                        showDeleteConfirmation = true
                    }
                }
            }
            .alert("Remove Known Host?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { hostToDelete = nil }
                Button("Remove", role: .destructive) {
                    if let kh = hostToDelete {
                        modelContext.delete(kh)
                    }
                    hostToDelete = nil
                }
            } message: {
                Text("You'll be asked to verify the host key again on next connection to \(hostToDelete?.hostname ?? "this host").")
            }
        }
    }
}

// MARK: - SSHKeyType Display

extension SSHKeyType {
    var displayName: String {
        switch self {
        case .ed25519: "Ed25519"
        case .rsa4096: "RSA 4096"
        case .ecdsaP256: "ECDSA P-256"
        }
    }
}
