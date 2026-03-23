import SwiftUI
import SwiftData
import iDevSSH

/// Connection progress sheet shown during SSH connect flow.
struct ConnectionSheet: View {
    let host: HostRecord
    let onConnected: (LibSSH2Session, ShellChannel) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var phase: ConnectionPhase = .connecting
    @State private var errorMessage: String?
    @State private var passwordPrompt = false
    @State private var password = ""
    @State private var hostKeyVerification: HostKeyVerificationState?

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Spacer()

                phaseIcon
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))

                VStack(spacing: Spacing.sm) {
                    Text(phaseTitle)
                        .font(.title3.bold())
                        .contentTransition(.numericText())

                    Text(phaseSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xxl)
                }

                if phase != .failed {
                    stepsIndicator
                }

                Spacer()

                if phase == .failed {
                    Button("Dismiss") { dismiss() }
                        .buttonStyle(.bordered)
                        .padding(.bottom, Spacing.xxl)
                }
            }
            .animation(.snappy(duration: 0.3), value: phase)
            .padding()
            .navigationTitle("Connecting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Password Required", isPresented: $passwordPrompt) {
                SecureField("Password", text: $password)
                Button("Connect") {
                    Task { await connectWithPassword() }
                }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text("Enter password for \(host.username)@\(host.hostname)")
            }
            .sheet(item: $hostKeyVerification) { verification in
                HostKeyVerificationSheet(
                    hostname: host.hostname,
                    port: host.port,
                    hostKey: verification.hostKey,
                    existingRecord: verification.existingRecord,
                    onDecision: { decision in
                        hostKeyVerification = nil
                        Task { await handleHostKeyDecision(decision, session: verification.session) }
                    }
                )
            }
            .task {
                await startConnection()
            }
        }
    }

    // MARK: - Phase Display

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .connecting:
            Image(systemName: "network")
                .foregroundStyle(.tint)
        case .verifyingHostKey:
            Image(systemName: "lock.shield")
                .foregroundStyle(.tint)
        case .authenticating:
            Image(systemName: "person.badge.key")
                .foregroundStyle(.tint)
        case .openingShell:
            Image(systemName: "terminal")
                .foregroundStyle(.tint)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.iDev.danger)
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .connecting: "Connecting"
        case .verifyingHostKey: "Verifying Host Key"
        case .authenticating: "Authenticating"
        case .openingShell: "Opening Shell"
        case .failed: "Connection Failed"
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case .connecting: "\(host.hostname):\(host.port)"
        case .verifyingHostKey: "Checking known hosts"
        case .authenticating: host.username
        case .openingShell: "Almost there..."
        case .failed: errorMessage ?? "An unknown error occurred."
        }
    }

    // MARK: - Steps Indicator

    private var stepsIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(ConnectionPhase.orderedPhases, id: \.self) { step in
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 8, height: 8)
                    .scaleEffect(step == phase ? 1.3 : 1.0)
                    .animation(.spring(duration: 0.3), value: phase)
            }
        }
        .padding(.top, Spacing.sm)
    }

    private func stepColor(for step: ConnectionPhase) -> Color {
        let ordered = ConnectionPhase.orderedPhases
        guard let currentIndex = ordered.firstIndex(of: phase),
              let stepIndex = ordered.firstIndex(of: step) else {
            return .iDev.dormant
        }
        if stepIndex < currentIndex { return .iDev.alive }
        if stepIndex == currentIndex { return .accentColor }
        return .iDev.dormant
    }

    // MARK: - Connection Flow

    private func startConnection() async {
        let session = LibSSH2Session()

        do {
            phase = .connecting
            try await session.connect(hostname: host.hostname, port: host.port)

            phase = .verifyingHostKey
            let hostKeyInfo = try session.hostKey()
            let knownHostsService = KnownHostsService(modelContext: modelContext)
            let sshHostKey = SSHHostKey(
                algorithm: hostKeyInfo.algorithm,
                fingerprint: hostKeyInfo.fingerprint,
                rawKey: hostKeyInfo.rawKey
            )

            let verification = knownHostsService.verify(
                hostname: host.hostname,
                port: host.port,
                hostKey: sshHostKey
            )

            switch verification {
            case .trusted:
                await proceedToAuth(session: session)
            case .newHost:
                hostKeyVerification = HostKeyVerificationState(
                    session: session, hostKey: sshHostKey, existingRecord: nil
                )
            case .mismatch(let old, _):
                hostKeyVerification = HostKeyVerificationState(
                    session: session, hostKey: sshHostKey, existingRecord: old
                )
            }
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func handleHostKeyDecision(_ decision: HostKeyDecision, session: LibSSH2Session) async {
        switch decision {
        case .trustAlways(let hostKey):
            let knownHostsService = KnownHostsService(modelContext: modelContext)
            knownHostsService.trustHost(hostname: host.hostname, port: host.port, hostKey: hostKey)
            await proceedToAuth(session: session)
        case .trustOnce:
            await proceedToAuth(session: session)
        case .reject:
            await session.disconnect()
            phase = .failed
            errorMessage = "Host key rejected"
        }
    }

    private func proceedToAuth(session: LibSSH2Session) async {
        phase = .authenticating

        do {
            if host.authMethod == .password {
                passwordPrompt = true
                return
            }

            let vaultService = VaultService()
            let authGateService = AuthGateService()
            let authenticator = SSHAuthenticator(vaultService: vaultService, authGateService: authGateService)
            let credential = try await authenticator.resolveCredential(for: host)
            try await session.authenticate(credential: credential)
            await openShell(session: session)
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func connectWithPassword() async {
        let session = LibSSH2Session()
        do {
            try await session.connect(hostname: host.hostname, port: host.port)
            let credential = AuthCredential(username: host.username, method: .password(password))
            try await session.authenticate(credential: credential)
            await openShell(session: session)
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func openShell(session: LibSSH2Session) async {
        phase = .openingShell
        do {
            let shell = try await session.openShell()
            onConnected(session, shell)
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Types

private enum ConnectionPhase: Hashable {
    case connecting
    case verifyingHostKey
    case authenticating
    case openingShell
    case failed

    static let orderedPhases: [ConnectionPhase] = [.connecting, .verifyingHostKey, .authenticating, .openingShell]
}

struct HostKeyVerificationState: Identifiable {
    let id = UUID()
    let session: LibSSH2Session
    let hostKey: SSHHostKey
    let existingRecord: KnownHostRecord?
}

enum HostKeyDecision {
    case trustAlways(SSHHostKey)
    case trustOnce
    case reject
}
