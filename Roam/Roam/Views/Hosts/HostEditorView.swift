import SwiftUI
import SwiftData

struct HostEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HostRecord.alias) private var allHosts: [HostRecord]
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]

    var existingHost: HostRecord?

    // Connection
    @State private var alias = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""

    // Authentication
    @State private var authMethod: AuthMethod = .key
    @State private var selectedKeyID: String?

    // Transport
    @State private var transport: TransportType = .ssh

    // Jump chain
    @State private var jumpChainIDs: [String] = []

    // Organization
    @State private var environment = "dev"
    @State private var trustClass: TrustClass = .trustedDev
    @State private var tags = ""
    @State private var folder = ""
    @State private var notes = ""

    // Connection test
    @State private var testState: ConnectionTestState = .idle

    private var isNew: Bool { existingHost == nil }
    private var canSave: Bool {
        !alias.isEmpty
        && !hostname.isEmpty
        && !username.isEmpty
        && (authMethod != .key || selectedKeyID != nil)
    }
    private var selectedKeyRecord: SSHKeyRecord? {
        guard let selectedKeyID else { return nil }
        return keys.first { key in
            key.keychainReference == selectedKeyID || key.id == selectedKeyID
        }
    }
    private var hasMissingSelectedKey: Bool {
        authMethod == .key && selectedKeyID != nil && selectedKeyRecord == nil
    }

    private var testAccessibilityLabel: String {
        switch testState {
        case .idle: "Test Connection"
        case .testing: "Testing connection"
        case .success(let ms): "Connection succeeded, \(ms) milliseconds"
        case .failure(let msg): "Connection failed, \(msg)"
        }
    }

    var body: some View {
        Form {
            connectionSection
            authenticationSection
            transportSection
            if !allHosts.isEmpty {
                jumpChainSection
            }
            organizationSection
            notesSection
            connectionTestSection
        }
        .navigationTitle(isNew ? "New Host" : "Edit Host")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { populateFromExisting() }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        Section {
            LabeledContent {
                TextField("my-server", text: $alias)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            } label: {
                Label("Name", systemImage: "tag")
            }

            LabeledContent {
                TextField("192.168.1.100 or host.example.com", text: $hostname)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            } label: {
                Label("Host", systemImage: "globe")
            }

            LabeledContent {
                TextField("22", text: $port)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 80)
            } label: {
                Label("Port", systemImage: "number")
            }

            LabeledContent {
                TextField("root", text: $username)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            } label: {
                Label("User", systemImage: "person")
            }
        } header: {
            Text("Connection")
        } footer: {
            if !hostname.isEmpty && !username.isEmpty {
                Text("ssh \(username)@\(hostname)\(port != "22" ? " -p \(port)" : "")")
                    .font(.mono(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Authentication Section

    private var authenticationSection: some View {
        Section("Authentication") {
            Picker(selection: $authMethod) {
                Label("SSH Key", systemImage: "key").tag(AuthMethod.key)
                Label("Password", systemImage: "lock").tag(AuthMethod.password)
                Label("Agent", systemImage: "person.badge.key").tag(AuthMethod.agent)
            } label: {
                Label("Method", systemImage: "shield")
            }

            if authMethod == .key {
                Picker(selection: $selectedKeyID) {
                    Text("None").tag(nil as String?)
                    ForEach(keys, id: \.id) { key in
                        HStack {
                            Text(key.label)
                            Spacer()
                        }.tag(key.keychainReference as String?)
                    }
                } label: {
                    Label("Key", systemImage: "key.fill")
                }

                if keys.isEmpty {
                    Label("No SSH keys in vault — add one in Settings > Vault", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.Roam.caution)
                } else if hasMissingSelectedKey {
                    Label("The selected key is no longer available in the vault on this device. Re-select a key or switch to password auth.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.Roam.caution)
                }
            }
        }
    }

    // MARK: - Transport Section

    private var transportSection: some View {
        Section {
            Picker(selection: $transport) {
                Text("SSH").tag(TransportType.ssh)
                Text("Mosh").tag(TransportType.mosh)
            } label: {
                Label("Transport", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("Transport")
        } footer: {
            if transport == .mosh {
                Text("Mosh provides roaming and resilience over UDP. Requires mosh-server on the remote host. SSH is used for SFTP, helper, and port forwarding regardless.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Jump Chain Section

    private var jumpChainSection: some View {
        Section {
            ForEach(jumpChainIDs, id: \.self) { hopID in
                if let host = allHosts.first(where: { $0.id == hopID }) {
                    Label(host.alias, systemImage: "arrow.right.circle")
                } else {
                    Label(hopID, systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                jumpChainIDs.remove(atOffsets: offsets)
            }

            Menu {
                ForEach(allHosts.filter({ $0.id != existingHost?.id }), id: \.id) { host in
                    Button(host.alias) {
                        jumpChainIDs.append(host.id)
                    }
                }
            } label: {
                Label("Add Jump Host", systemImage: "plus.circle")
            }
        } header: {
            Text("ProxyJump Chain")
        } footer: {
            if !jumpChainIDs.isEmpty {
                Text("Connection will hop through \(jumpChainIDs.count) intermediar\(jumpChainIDs.count == 1 ? "y" : "ies") before reaching the target.")
                    .font(.caption)
            }
        }
    }

    // MARK: - Organization Section

    private var organizationSection: some View {
        Section("Organization") {
            Picker(selection: $environment) {
                Label("Development", systemImage: "hammer").tag("dev")
                Label("Staging", systemImage: "flask").tag("staging")
                Label("Production", systemImage: "shield.checkered").tag("prod")
            } label: {
                Label("Environment", systemImage: "tray.full")
            }

            Picker(selection: $trustClass) {
                Text("Trusted Dev").tag(TrustClass.trustedDev)
                Text("Production").tag(TrustClass.production)
                Text("Untrusted").tag(TrustClass.untrusted)
            } label: {
                Label("Trust Level", systemImage: "checkmark.shield")
            }

            LabeledContent {
                TextField("gpu, ml, web", text: $tags)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            } label: {
                Label("Tags", systemImage: "tag")
            }

            LabeledContent {
                TextField("ml-cluster", text: $folder)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
            } label: {
                Label("Folder", systemImage: "folder")
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 60)
        }
    }

    // MARK: - Connection Test Section

    private var connectionTestSection: some View {
        Section {
            Button {
                testConnection()
            } label: {
                HStack {
                    Label("Test Connection", systemImage: testState.icon)

                    Spacer()

                    switch testState {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView()
                    case .success(let latency):
                        Text("\(latency)ms")
                            .foregroundStyle(.Roam.alive)
                            .font(.mono(.callout))
                    case .failure(let message):
                        Text(message)
                            .foregroundStyle(.Roam.danger)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
            .disabled(hostname.isEmpty || testState == .testing)
            .accessibilityLabel(testAccessibilityLabel)
            .accessibilityHint(hostname.isEmpty ? "Enter a hostname first." : "Tests TCP reachability on the specified port.")
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Tests TCP reachability on the specified port. Does not attempt SSH authentication.")
                .font(.caption)
        }
    }

    // MARK: - Connection Test Logic

    private func testConnection() {
        testState = .testing
        let host = hostname
        let portNum = Int(port) ?? 22

        Task {
            let report = await HostConnectivityProbe.run(hostname: host, port: portNum)

            await MainActor.run {
                if let latency = report.latencyMS {
                    testState = .success(latencyMS: latency)
                } else {
                    testState = .failure(
                        message: report.failureMessage ?? report.dnsErrorMessage ?? "Connection failed"
                    )
                }
            }
        }
    }

    // MARK: - Populate / Save

    private func populateFromExisting() {
        guard let host = existingHost else { return }
        alias = host.alias
        hostname = host.hostname
        port = "\(host.port)"
        username = host.username
        authMethod = host.authMethod
        if let hostKeyReference = host.keyReference,
           let matchingKey = keys.first(where: { key in
               key.keychainReference == hostKeyReference || key.id == hostKeyReference
           }) {
            selectedKeyID = matchingKey.keychainReference
        } else {
            selectedKeyID = host.keyReference
        }
        transport = host.preferredTransport
        environment = host.environment
        trustClass = host.trustClass
        tags = host.tags.joined(separator: ", ")
        folder = host.folder ?? ""
        notes = host.notes
        jumpChainIDs = host.jumpChain
    }

    private func save() {
        let parsedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let parsedPort = Int(port) ?? 22

        if let host = existingHost {
            host.alias = alias
            host.hostname = hostname
            host.port = parsedPort
            host.username = username
            host.authMethod = authMethod
            host.keyReference = authMethod == .key ? selectedKeyID : nil
            host.preferredTransport = transport
            host.jumpChain = jumpChainIDs
            host.tags = parsedTags
            host.folder = folder.isEmpty ? nil : folder
            host.notes = notes
            host.environment = environment
            host.trustClass = trustClass
            host.updatedAt = Date()
        } else {
            let host = HostRecord(
                alias: alias,
                hostname: hostname,
                port: parsedPort,
                username: username,
                authMethod: authMethod,
                keyReference: authMethod == .key ? selectedKeyID : nil,
                jumpChain: jumpChainIDs,
                tags: parsedTags,
                folder: folder.isEmpty ? nil : folder,
                notes: notes,
                environment: environment,
                trustClass: trustClass,
                preferredTransport: transport
            )
            modelContext.insert(host)
        }

        dismiss()
    }
}

// MARK: - Connection Test State

enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success(latencyMS: Int)
    case failure(message: String)

    var icon: String {
        switch self {
        case .idle: "bolt.horizontal"
        case .testing: "bolt.horizontal"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        }
    }
}
