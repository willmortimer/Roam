import SwiftUI

/// Sheet for creating a public preview tunnel.
struct PublicPreviewSheet: View {
    let localPort: Int
    let previewService: PublicPreviewService
    let helperClient: (any HelperClientProtocol)?
    let onDismiss: () -> Void

    @State private var selectedProvider: PublicPreviewService.TunnelProvider = .cloudflareTunnel
    @State private var manualURL = ""

    var body: some View {
        NavigationStack {
            Form {
                providerSection

                if let preview = previewService.activePreview, preview.isActive {
                    activeSection(preview: preview)
                } else if selectedProvider == .manual {
                    manualSection
                }

                if previewService.isStarting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Starting tunnel...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = previewService.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.Roam.danger)
                    }
                }
            }
            .navigationTitle("Share Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        Section("Tunnel Provider") {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(PublicPreviewService.TunnelProvider.allCases) { provider in
                    Label(provider.displayName, systemImage: provider.icon)
                        .tag(provider)
                }
            }

            if previewService.activePreview == nil && selectedProvider != .manual {
                Button {
                    Task { await startTunnel() }
                } label: {
                    Label("Start Tunnel on :\(localPort)", systemImage: "arrow.up.forward.circle")
                }
                .disabled(previewService.isStarting || helperClient == nil)
            }
        }
    }

    private func activeSection(preview: PublicPreviewService.PublicPreview) -> some View {
        Section("Public URL") {
            HStack {
                Text(preview.publicURL)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button {
                    UIPasteboard.general.string = preview.publicURL
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            LabeledContent("Port", value: ":\(preview.localPort)")
            LabeledContent("Provider", value: preview.provider.displayName)

            Button(role: .destructive) {
                Task { await stopTunnel() }
            } label: {
                Label("Stop Tunnel", systemImage: "stop.circle")
            }
        }
    }

    private var manualSection: some View {
        Section("Manual Public URL") {
            TextField("https://your-tunnel-url.com", text: $manualURL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !manualURL.isEmpty {
                Button {
                    UIPasteboard.general.string = manualURL
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Actions

    private func startTunnel() async {
        guard let client = helperClient else { return }
        await previewService.startPublicPreview(
            helperClient: client,
            previewPort: localPort,
            provider: selectedProvider
        )
    }

    private func stopTunnel() async {
        guard let client = helperClient else { return }
        await previewService.stopPublicPreview(helperClient: client)
    }
}
