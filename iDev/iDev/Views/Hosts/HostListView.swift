import SwiftUI
import SwiftData

struct HostListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HostRecord.alias) private var hosts: [HostRecord]
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var showingImport = false

    var body: some View {
        List {
            if filteredHosts.isEmpty {
                ContentUnavailableView(
                    "No Hosts",
                    systemImage: "server.rack",
                    description: Text("Add an SSH host to get started.")
                )
            } else {
                ForEach(filteredHosts, id: \.id) { host in
                    NavigationLink(value: host.id) {
                        HostRow(host: host)
                    }
                }
                .onDelete(perform: deleteHosts)
            }
        }
        .searchable(text: $searchText, prompt: "Search hosts")
        .navigationTitle("Hosts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Host", systemImage: "plus") {
                        showingEditor = true
                    }
                    Button("Import from SSH Config", systemImage: "square.and.arrow.down") {
                        showingImport = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(for: String.self) { hostID in
            HostDetailView(hostID: hostID)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                HostEditorView()
            }
        }
        .sheet(isPresented: $showingImport) {
            NavigationStack {
                SSHConfigImportView()
            }
        }
    }

    private var filteredHosts: [HostRecord] {
        if searchText.isEmpty { return hosts }
        return hosts.filter {
            $0.alias.localizedCaseInsensitiveContains(searchText) ||
            $0.hostname.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private func deleteHosts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredHosts[index])
        }
    }
}

struct HostRow: View {
    let host: HostRecord

    private var liveness: ConnectionDot.ConnectionLiveness {
        guard let lastSeen = host.lastSeen else { return .unknown }
        return Date().timeIntervalSince(lastSeen) < 300 ? .connected : .disconnected
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            ConnectionDot(state: liveness)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(host.alias)
                    .font(.headline)

                AddressLabel(username: host.username, hostname: host.hostname, port: host.port)

                HStack(spacing: Spacing.sm) {
                    EnvironmentBadge(environment: host.environment)

                    if host.preferredTransport == .mosh {
                        TransportBadge(transport: .mosh)
                    }

                    if !host.jumpChain.isEmpty {
                        Text("\(host.jumpChain.count) hop\(host.jumpChain.count == 1 ? "" : "s")")
                            .codeBadge(color: .iDev.dormant)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host.alias), \(host.username) at \(host.hostname) port \(host.port), \(host.environment)")
    }
}
