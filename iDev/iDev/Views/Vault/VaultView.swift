import SwiftUI
import SwiftData

struct VaultView: View {
    @State private var selectedSection: VaultSection = .keys
    @State private var showingKeyGenerator = false

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
                KeyListSection()
            case .knownHosts:
                KnownHostsSection()
            }
        }
        .navigationTitle("Vault")
        .toolbar {
            if selectedSection == .keys {
                ToolbarItem(placement: .primaryAction) {
                    Button("Generate Key", systemImage: "plus") {
                        showingKeyGenerator = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingKeyGenerator) {
            NavigationStack {
                KeyGeneratorView()
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
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]

    var body: some View {
        if keys.isEmpty {
            ContentUnavailableView(
                "No SSH Keys",
                systemImage: "key",
                description: Text("Generate or import an SSH key to authenticate with hosts.")
            )
        } else {
            ForEach(keys, id: \.id) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(key.label)
                        .font(.headline)
                    Text(key.keyType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Known Hosts

struct KnownHostsSection: View {
    @Query(sort: \KnownHostRecord.hostname) private var knownHosts: [KnownHostRecord]

    var body: some View {
        if knownHosts.isEmpty {
            ContentUnavailableView(
                "No Known Hosts",
                systemImage: "checkmark.shield",
                description: Text("Host fingerprints will appear here after your first connection.")
            )
        } else {
            ForEach(knownHosts, id: \.id) { kh in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(kh.hostname):\(kh.port)")
                        .font(.headline)
                    Text(kh.fingerprint)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
