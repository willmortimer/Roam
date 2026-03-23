import SwiftUI
import SwiftData

struct HostDetailView: View {
    let hostID: String
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [HostRecord]
    @Query(sort: \HostRecord.alias) private var allHosts: [HostRecord]
    @State private var showingEditor = false

    private var host: HostRecord? {
        hosts.first { $0.id == hostID }
    }

    var body: some View {
        if let host {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    connectionHeader(host)
                    badgeStrip(host)
                    connectionCard(host)

                    if !host.jumpChain.isEmpty {
                        jumpChainCard(host)
                    }

                    if host.fingerprintTrustState != .unknown {
                        hostKeyCard(host)
                    }

                    if !host.tags.isEmpty {
                        tagsCard(host)
                    }

                    if !host.notes.isEmpty {
                        notesCard(host)
                    }

                    timestampsFooter(host)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(host.alias)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Connect") {
                        // TODO: initiate SSH connection
                    }
                    .buttonStyle(.borderedProminent)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Edit", systemImage: "pencil") {
                        showingEditor = true
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                NavigationStack {
                    HostEditorView(existingHost: host)
                }
            }
        } else {
            ContentUnavailableView("Host not found", systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: - Connection Header

    private func connectionHeader(_ host: HostRecord) -> some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: host.preferredTransport == .mosh ? "antenna.radiowaves.left.and.right" : "server.rack")
                    .font(.title)
                    .foregroundStyle(.tint)
            }

            AddressLabel(username: host.username, hostname: host.hostname, port: host.port)
                .font(.mono(.body))

            Text("ssh \(host.username)@\(host.hostname)\(host.port != 22 ? " -p \(host.port)" : "")")
                .font(.mono(.caption))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Badge Strip

    private func badgeStrip(_ host: HostRecord) -> some View {
        HStack(spacing: Spacing.sm) {
            EnvironmentBadge(environment: host.environment)
            TrustBadge(trustClass: host.trustClass)
            TransportBadge(transport: host.preferredTransport)

            if let folder = host.folder {
                Text(folder)
                    .codeBadge(color: .iDev.dormant)
            }
        }
    }

    // MARK: - Connection Info Card

    private func connectionCard(_ host: HostRecord) -> some View {
        VStack(spacing: 0) {
            infoRow(label: "Hostname", value: host.hostname, icon: "globe")
            Divider().padding(.leading, 44)
            infoRow(label: "Port", value: "\(host.port)", icon: "number")
            Divider().padding(.leading, 44)
            infoRow(label: "User", value: host.username, icon: "person")
            Divider().padding(.leading, 44)
            infoRow(label: "Auth", value: host.authMethod.rawValue.capitalized, icon: "shield")
            if let keyRef = host.keyReference {
                Divider().padding(.leading, 44)
                infoRow(label: "Key", value: keyRef, icon: "key.fill", mono: true)
            }
        }
        .cardStyle()
    }

    // MARK: - Jump Chain Card

    private func jumpChainCard(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("ProxyJump Chain", systemImage: "arrow.triangle.branch")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(Array(host.jumpChain.enumerated()), id: \.offset) { index, hopID in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "\(index + 1).circle.fill")
                        .foregroundStyle(.tint)
                        .font(.callout)
                    if let hop = allHosts.first(where: { $0.id == hopID }) {
                        Text(hop.alias)
                            .font(.subheadline)
                        Spacer()
                        Text(hop.hostname)
                            .font(.mono(.caption))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(hopID)
                            .font(.mono(.caption))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Host Key Card

    private func hostKeyCard(_ host: HostRecord) -> some View {
        VStack(spacing: 0) {
            infoRow(label: "Algorithm", value: host.knownHostAlgorithm ?? "--", icon: "lock.shield")
            Divider().padding(.leading, 44)
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "key.horizontal")
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Fingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(host.knownHostFingerprint ?? "--")
                        .font(.mono(.caption))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.sm)
            Divider().padding(.leading, 44)
            infoRow(
                label: "Trust",
                value: host.fingerprintTrustState.rawValue.capitalized,
                icon: host.fingerprintTrustState == .trusted ? "checkmark.shield.fill" : "exclamationmark.shield",
                valueColor: host.fingerprintTrustState == .trusted ? .iDev.alive : .iDev.danger
            )
        }
        .cardStyle()
    }

    // MARK: - Tags Card

    private func tagsCard(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Tags", systemImage: "tag")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            FlowLayout(spacing: Spacing.sm) {
                ForEach(host.tags, id: \.self) { tag in
                    Text(tag)
                        .codeBadge(color: .iDev.dormant)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Notes Card

    private func notesCard(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Notes", systemImage: "note.text")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Text(host.notes)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Timestamps

    private func timestampsFooter(_ host: HostRecord) -> some View {
        HStack {
            if let lastSeen = host.lastSeen {
                Label("Last seen \(lastSeen, style: .relative) ago", systemImage: "clock")
            }
            Spacer()
            Text("Created \(host.createdAt, style: .date)")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, Spacing.xs)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Info Row Helper

    private func infoRow(
        label: String,
        value: String,
        icon: String,
        mono: Bool = false,
        valueColor: Color = .primary
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(mono ? .mono(.subheadline) : .subheadline)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Flow Layout

/// Simple horizontal wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            ), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
