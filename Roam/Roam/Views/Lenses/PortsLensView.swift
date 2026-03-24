import SwiftUI

/// Shows active port forwards and detected preview candidates.
struct PortsLensView: View {
    let helperClient: (any HelperClientProtocol)?
    let repoPath: String
    let activeForwards: [ActiveForward]
    let onForwardAndPreview: ((PreviewCandidateDTO) -> Void)?

    @State private var candidates: [PreviewCandidateDTO] = []
    @State private var isLoading = false
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?

    private var forwardedPorts: Set<Int> {
        Set(activeForwards.map(\.remotePort))
    }

    var body: some View {
        Group {
            if helperClient == nil {
                ContentUnavailableView("Helper Required", systemImage: "shippingbox")
            } else if isLoading && activeForwards.isEmpty && candidates.isEmpty {
                ProgressView("Detecting ports...")
            } else if activeForwards.isEmpty && candidates.isEmpty {
                ContentUnavailableView("No Ports", systemImage: "network", description: Text("No active forwards or detected servers."))
            } else {
                portsList
            }
        }
        .navigationTitle("Ports")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Toggle("Live", isOn: $autoRefresh)
            }
        }
        .task {
            await refresh()
            updateRefreshLoop()
        }
        .refreshable { await refresh() }
        .onChange(of: autoRefresh) { _, _ in
            updateRefreshLoop()
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private var portsList: some View {
        List {
            if !activeForwards.isEmpty {
                Section("Active Forwards") {
                    ForEach(activeForwards) { forward in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(forward.name)
                                    .font(.subheadline.bold())
                                HStack(spacing: 4) {
                                    Text("localhost:\(forward.resolvedLocalPort)")
                                    Image(systemName: "arrow.right")
                                    Text("\(forward.remoteHost):\(forward.remotePort)")
                                }
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.Roam.alive)
                        }
                    }
                }
            }

            let unforwarded = candidates.filter { !forwardedPorts.contains($0.port) }
            if !unforwarded.isEmpty {
                Section("Detected Servers") {
                    ForEach(unforwarded, id: \.port) { candidate in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.process_name)
                                    .font(.subheadline.bold())
                                HStack(spacing: 8) {
                                    Text(":\(candidate.port)")
                                        .font(.caption.monospaced())
                                    if let hint = candidate.framework_hint, !hint.isEmpty {
                                        Text(hint)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.tint.opacity(0.15), in: Capsule())
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                onForwardAndPreview?(candidate)
                            } label: {
                                Label("Forward", systemImage: "arrow.right.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func refresh() async {
        guard let helper = helperClient else { return }
        isLoading = true
        do {
            candidates = try await helper.previewCandidates(workspacePath: repoPath.isEmpty ? nil : repoPath)
        } catch {
            // Non-fatal
        }
        isLoading = false
    }

    private func updateRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil

        guard autoRefresh, helperClient != nil else { return }

        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LowBandwidthService.shared.isEnabled ? 45 : 12))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }
}
