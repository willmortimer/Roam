import SwiftUI
import SwiftData

struct HostListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HostRecord.alias) private var hosts: [HostRecord]
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var showingSFTPEditor = false
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
                    NavigationLink(value: HostNavigationTarget(id: host.id)) {
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
                    Button("New SSH Host", systemImage: "terminal") {
                        showingEditor = true
                    }
                    Button("New SFTP Host", systemImage: "externaldrive.connected.to.line.below") {
                        showingSFTPEditor = true
                    }
                    Divider()
                    Button("Import from SSH Config", systemImage: "square.and.arrow.down") {
                        showingImport = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add host")
            }
        }
        .navigationDestination(for: HostNavigationTarget.self) { target in
            HostDetailView(hostID: target.id)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                HostEditorView(initialHostType: .ssh)
            }
        }
        .sheet(isPresented: $showingSFTPEditor) {
            NavigationStack {
                HostEditorView(initialHostType: .sftp)
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

private struct HostNavigationTarget: Hashable {
    let id: String
}

struct HostRow: View {
    let host: HostRecord

    private var liveness: ConnectionDot.ConnectionLiveness {
        guard let lastSeen = host.lastSeen else { return .unknown }
        return Date().timeIntervalSince(lastSeen) < 300 ? .connected : .disconnected
    }

    private var hostIcon: String {
        switch host.hostType {
        case .ssh: "terminal"
        case .sftp: "externaldrive.connected.to.line.below"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: hostIcon)
                .foregroundStyle(host.hostType == .sftp ? Color.accentColor : Color(.secondaryLabel))
                .frame(width: 20)
                .padding(.top, 4)

            ConnectionDot(state: liveness)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(host.alias)
                    .font(.headline)

                AddressLabel(username: host.username, hostname: host.hostname, port: host.port)

                HStack(spacing: Spacing.sm) {
                    Text(host.hostType == .sftp ? "SFTP" : "SSH")
                        .codeBadge(color: host.hostType == .sftp ? .accentColor : .Roam.dormant)

                    EnvironmentBadge(environment: host.environment)

                    if host.preferredTransport == .mosh && host.hostType == .ssh {
                        TransportBadge(transport: .mosh)
                    }

                    if !host.jumpChain.isEmpty {
                        Text("\(host.jumpChain.count) hop\(host.jumpChain.count == 1 ? "" : "s")")
                            .codeBadge(color: .Roam.dormant)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host.hostType == .sftp ? "SFTP" : "SSH") host \(host.alias), \(host.username) at \(host.hostname) port \(host.port), \(host.environment)")
    }
}
