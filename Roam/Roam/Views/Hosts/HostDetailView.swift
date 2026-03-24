import SwiftUI
import SwiftData
import RoamSSH

struct HostDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    let hostID: String
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [HostRecord]
    @Query(sort: \HostRecord.alias) private var allHosts: [HostRecord]
    @State private var showingEditor = false
    @State private var showingConnectionSheet = false
    @State private var presentedSession: ManagedSession?
    @State private var diagnosticsState: ConnectionTestState = .idle
    @State private var diagnosticsReport: HostConnectivityReport?
    @State private var showingHelperConnectionSheet = false
    @State private var showingHelperInstallSheet = false
    @State private var helperWorkflowState: HostHelperWorkflowState = .idle
    @State private var helperDetectionResult: HelperDetectionResult?
    @State private var helperSession: LibSSH2Session?
    @State private var helperRPCResponsive: Bool?
    @State private var pendingHelperCheck = false
    @State private var helperAlertMessage: String?

    private var host: HostRecord? {
        hosts.first { $0.id == hostID }
    }

    private var activeSessionsForHost: [ManagedSession] {
        sessionManager.sessions.filter { $0.restorationContext.hostID == hostID }
    }

    var body: some View {
        if let host {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    connectionHeader(host)
                    badgeStrip(host)

                    if !activeSessionsForHost.isEmpty {
                        activeSessionsCard(host)
                    }

                    connectionCard(host)
                    diagnosticsCard(host)
                    helperCard(host)

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
                            showingConnectionSheet = true
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
            .sheet(isPresented: $showingConnectionSheet) {
                ConnectionSheet(host: host) { sshSession, shell in
                    host.lastSeen = .now
                    presentedSession = sessionManager.registerConnectedSession(
                        host: host,
                        restorationContext: .directHost(host: host),
                        sshSession: sshSession,
                        shellChannel: shell
                    )
                    showingConnectionSheet = false
                }
            }
            .sheet(isPresented: $showingHelperConnectionSheet) {
                ConnectionSheet(host: host) { sshSession, shell in
                    showingHelperConnectionSheet = false
                    helperSession = sshSession
                    pendingHelperCheck = true
                    Task {
                        await shell.close()
                    }
                }
            }
            .sheet(isPresented: $showingHelperInstallSheet) {
                if let helperDetectionResult {
                    HelperInstallSheet(
                        detectionResult: helperDetectionResult,
                        onInstall: {
                            showingHelperInstallSheet = false
                            Task {
                                await installOrUpgradeHelper(for: host)
                            }
                        },
                        onSkip: {
                            showingHelperInstallSheet = false
                            Task {
                                await cleanupHelperSession()
                            }
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
            .onChange(of: showingHelperConnectionSheet) { _, isPresented in
                guard !isPresented, pendingHelperCheck, let session = helperSession else {
                    return
                }
                pendingHelperCheck = false
                Task {
                    await detectHelper(for: host, using: session)
                }
            }
            .alert(
                "Helper Check Failed",
                isPresented: Binding(
                    get: { helperAlertMessage != nil },
                    set: { if !$0 { helperAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(helperAlertMessage ?? "An unknown helper error occurred.")
            }
            .fullScreenCover(item: $presentedSession) { session in
                NavigationStack {
                    SessionView(session: session)
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
                    .codeBadge(color: .Roam.dormant)
            }
        }
    }

    // MARK: - Active Sessions Card

    private func activeSessionsCard(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Active Sessions", systemImage: "terminal")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ForEach(activeSessionsForHost) { session in
                HStack(spacing: Spacing.sm) {
                    ConnectionDot(state: session.connectionLiveness)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(session.restorationContext.workspaceName ?? session.hostAlias)
                            .font(.subheadline)

                        Text(sessionUptime(session))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    TransportBadge(transport: session.transportType)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func sessionUptime(_ session: ManagedSession) -> String {
        let elapsed = Date().timeIntervalSince(session.createdAt)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        if elapsed < 3600 {
            let m = Int(elapsed) / 60
            let s = Int(elapsed) % 60
            return "\(m)m \(s)s"
        }
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        return "\(h)h \(m)m"
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

    // MARK: - Helper Card

    private func helperCard(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center) {
                Label("Roam Helper", systemImage: "shippingbox")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingHelperConnectionSheet = true
                } label: {
                    if helperWorkflowState == .checking || helperWorkflowState == .installing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(helperButtonTitle, systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(helperWorkflowState == .checking || helperWorkflowState == .installing)
            }

            VStack(spacing: 0) {
                infoRow(
                    label: "Status",
                    value: helperStatusTitle(host),
                    icon: helperStatusIcon,
                    valueColor: helperStatusColor
                )

                if let helperVersion = helperVersion(host) {
                    Divider().padding(.leading, 44)
                    infoRow(
                        label: "Version",
                        value: helperVersion,
                        icon: "number",
                        mono: true
                    )
                }

                if let lastCheck = helperLastCheck(host) {
                    Divider().padding(.leading, 44)
                    infoRow(
                        label: "Last Check",
                        value: lastCheck.formatted(date: .abbreviated, time: .shortened),
                        icon: "clock"
                    )
                }

                if let helperRPCResponsive {
                    Divider().padding(.leading, 44)
                    infoRow(
                        label: "RPC",
                        value: helperRPCResponsive ? "Responsive" : "Unavailable",
                        icon: helperRPCResponsive ? "dot.radiowaves.left.and.right" : "wifi.slash",
                        valueColor: helperRPCResponsive ? .Roam.alive : .Roam.caution
                    )
                }
            }

            Text(helperSubtitle(host))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                helperBenefit("Tmux pane roles and smarter workspace resume")
                helperBenefit("Preview/port discovery and public preview workflows")
                helperBenefit("Repo, diff, test, log, and artifact views")
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Diagnostics Card

    private func diagnosticsCard(_ host: HostRecord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .center) {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    runDiagnostics(for: host)
                } label: {
                    if diagnosticsState == .testing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(diagnosticsReport == nil ? "Run Probe" : "Re-run", systemImage: diagnosticsState.icon)
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(diagnosticsState == .testing)
            }

            if let diagnosticsReport {
                VStack(spacing: 0) {
                    infoRow(
                        label: "TCP",
                        value: diagnosticsReport.isReachable ? "Reachable" : "Unavailable",
                        icon: diagnosticsReport.isReachable ? "checkmark.circle.fill" : "xmark.circle.fill",
                        valueColor: diagnosticsReport.isReachable ? .Roam.alive : .Roam.danger
                    )
                    Divider().padding(.leading, 44)
                    infoRow(
                        label: "Latency",
                        value: diagnosticsReport.latencyMS.map { "\($0) ms" } ?? "--",
                        icon: "timer",
                        mono: true,
                        valueColor: diagnosticsReport.isReachable ? .Roam.alive : .primary
                    )
                    Divider().padding(.leading, 44)
                    infoRow(
                        label: "DNS",
                        value: diagnosticsReport.dnsSummary,
                        icon: "network"
                    )
                    Divider().padding(.leading, 44)
                    infoRow(
                        label: "Probe",
                        value: diagnosticsReport.checkedAt.formatted(date: .abbreviated, time: .shortened),
                        icon: "clock"
                    )

                    if let lastHelperVersion = host.lastHelperVersion {
                        Divider().padding(.leading, 44)
                        infoRow(label: "Helper", value: lastHelperVersion, icon: "shippingbox", mono: true)
                    }

                    if let lastHelperCheck = host.lastHelperCheck {
                        Divider().padding(.leading, 44)
                        infoRow(
                            label: "Helper Check",
                            value: lastHelperCheck.formatted(date: .abbreviated, time: .shortened),
                            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                        )
                    }
                }

                if !diagnosticsReport.resolvedAddresses.isEmpty {
                    Divider().padding(.vertical, Spacing.xs)

                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: "list.bullet.rectangle")
                            .frame(width: 24)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Resolved Addresses")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(diagnosticsReport.resolvedAddresses.joined(separator: "\n"))
                                .font(.mono(.caption))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }

                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                }

                if let failureMessage = diagnosticsReport.failureMessage {
                    Divider().padding(.vertical, Spacing.xs)

                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: "exclamationmark.triangle")
                            .frame(width: 24)
                            .foregroundStyle(.Roam.caution)

                        Text(failureMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                }
            } else {
                Text("Resolve DNS and test TCP reachability on the configured port without attempting SSH authentication.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                valueColor: host.fingerprintTrustState == .trusted ? .Roam.alive : .Roam.danger
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
                        .codeBadge(color: .Roam.dormant)
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

    private func runDiagnostics(for host: HostRecord) {
        diagnosticsState = .testing

        Task {
            let report = await HostConnectivityProbe.run(hostname: host.hostname, port: host.port)

            await MainActor.run {
                diagnosticsReport = report
                if let latency = report.latencyMS {
                    diagnosticsState = .success(latencyMS: latency)
                } else {
                    diagnosticsState = .failure(
                        message: report.failureMessage ?? report.dnsErrorMessage ?? "Connection failed"
                    )
                }
            }
        }
    }

    private var helperButtonTitle: String {
        switch helperWorkflowState {
        case .idle:
            "Check Helper"
        case .checking:
            "Checking"
        case .installing:
            "Installing"
        case .installed:
            "Re-check"
        case .notInstalled, .outdated, .failed:
            "Check Again"
        }
    }

    private var helperStatusIcon: String {
        switch helperWorkflowState {
        case .installed:
            "checkmark.circle.fill"
        case .outdated:
            "arrow.up.circle.fill"
        case .notInstalled:
            "xmark.circle.fill"
        case .failed:
            "exclamationmark.triangle"
        case .checking, .installing:
            "hourglass"
        case .idle:
            "questionmark.circle"
        }
    }

    private var helperStatusColor: Color {
        switch helperWorkflowState {
        case .installed:
            .Roam.alive
        case .outdated:
            .Roam.caution
        case .notInstalled, .failed:
            .Roam.danger
        case .checking, .installing:
            .accentColor
        case .idle:
            .primary
        }
    }

    private func helperStatusTitle(_ host: HostRecord) -> String {
        switch helperWorkflowState {
        case .installed(let version):
            return "Installed (\(version))"
        case .outdated(let current, let required):
            return "Outdated (\(current) < \(required))"
        case .notInstalled:
            return "Not installed"
        case .failed(let message):
            return message
        case .checking:
            return "Checking over SSH"
        case .installing:
            return "Installing on host"
        case .idle:
            if let version = host.lastHelperVersion {
                return "Installed (\(version))"
            }
            if host.lastHelperCheck != nil {
                return "Unavailable at last check"
            }
            return "Not checked yet"
        }
    }

    private func helperSubtitle(_ host: HostRecord) -> String {
        switch helperWorkflowState {
        case .installed:
            return "The helper is ready on this host. Helper-backed cockpit and lens features can start as soon as a session is opened."
        case .outdated:
            return "This host has an older helper binary. Updating it will restore the newer cockpit and workflow features."
        case .notInstalled:
            return "No helper binary was detected on this host. Run the helper check and install flow to enable richer workspace automation."
        case .failed:
            return "The helper check did not complete cleanly. Re-run it once connectivity and auth look good."
        case .checking:
            return "Connecting and asking the host for its helper version."
        case .installing:
            return "Uploading the bundled helper and verifying it on the remote host."
        case .idle:
            if host.lastHelperVersion != nil {
                return "This is the last recorded helper version for the host. Re-check to verify it still matches what is on the machine."
            }
            return "The app does not know helper status until it performs an authenticated check on the remote host."
        }
    }

    private func helperVersion(_ host: HostRecord) -> String? {
        switch helperWorkflowState {
        case .installed(let version):
            return version
        case .outdated(let current, _):
            return current
        default:
            return host.lastHelperVersion
        }
    }

    private func helperLastCheck(_ host: HostRecord) -> Date? {
        host.lastHelperCheck
    }

    private func helperBenefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.tint)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func detectHelper(for host: HostRecord, using session: LibSSH2Session) async {
        await MainActor.run {
            helperWorkflowState = .checking
            helperRPCResponsive = nil
            helperAlertMessage = nil
        }

        let installService = HelperInstallService(sshSession: session)
        let detection = await installService.detectHelper()

        await MainActor.run {
            helperDetectionResult = detection
            host.lastHelperCheck = .now
        }

        switch detection {
        case .installed(let version):
            let rpcResponsive = await verifyHelperRPC(using: session)
            await MainActor.run {
                host.lastHelperVersion = version
                helperRPCResponsive = rpcResponsive
                helperWorkflowState = .installed(version: version)
            }
            await cleanupHelperSession()

        case .outdated(let current, let required):
            await MainActor.run {
                host.lastHelperVersion = current
                helperWorkflowState = .outdated(current: current, required: required)
            }
            await presentHelperInstallSheet()

        case .notInstalled:
            await MainActor.run {
                host.lastHelperVersion = nil
                helperWorkflowState = .notInstalled
            }
            await presentHelperInstallSheet()

        case .error(let message):
            await MainActor.run {
                host.lastHelperVersion = nil
                helperWorkflowState = .failed(message: message)
                helperAlertMessage = message
            }
            await cleanupHelperSession()
        }
    }

    private func installOrUpgradeHelper(for host: HostRecord) async {
        guard let session = helperSession, let detectionResult = helperDetectionResult else {
            return
        }

        await MainActor.run {
            helperWorkflowState = .installing
            helperRPCResponsive = nil
        }

        let installService = HelperInstallService(sshSession: session)

        do {
            let arch = try await installService.detectArchitecture()
            let binaryData = try await HelperBinaryLocator.binaryData(for: arch)

            switch detectionResult {
            case .outdated:
                try await installService.upgradeHelper(binaryData: binaryData)
            case .notInstalled, .error:
                try await installService.installHelper(binaryData: binaryData)
            case .installed:
                break
            }

            await detectHelper(for: host, using: session)
        } catch {
            await MainActor.run {
                helperDetectionResult = .error(error.localizedDescription)
                helperWorkflowState = .failed(message: error.localizedDescription)
                helperAlertMessage = error.localizedDescription
                host.lastHelperCheck = .now
            }
            await cleanupHelperSession()
        }
    }

    private func verifyHelperRPC(using session: LibSSH2Session) async -> Bool {
        let helperClient = HelperClient(sshSession: session)

        do {
            try await helperClient.start()
            return await helperClient.isAvailable()
        } catch {
            return false
        }
    }

    private func cleanupHelperSession() async {
        let session = await MainActor.run { () -> LibSSH2Session? in
            let session = helperSession
            helperSession = nil
            return session
        }

        if let session {
            await session.disconnect()
        }
    }

    private func presentHelperInstallSheet() async {
        try? await Task.sleep(for: .milliseconds(200))
        await MainActor.run {
            showingHelperInstallSheet = true
        }
    }
}

private enum HostHelperWorkflowState: Equatable {
    case idle
    case checking
    case installing
    case installed(version: String)
    case outdated(current: String, required: String)
    case notInstalled
    case failed(message: String)
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
