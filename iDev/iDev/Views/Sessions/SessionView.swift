import SwiftUI

/// Full terminal session view: terminal + modifier key bar + transport chrome.
struct SessionView: View {
    let bridge: any TerminalSessionBridgeProtocol
    var transportType: TransportType = .ssh
    @State private var terminalTitle: String = "Terminal"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TerminalViewRepresentable(bridge: bridge)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            ModifierKeyBar { key in
                Task {
                    try? await bridge.sendToRemote(key.bytes)
                }
            }
        }
        .navigationTitle(terminalTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: Spacing.sm) {
                    ConnectionDot(state: .connected)
                    TransportBadge(transport: transportType)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
                        Task {
                            await bridge.disconnect()
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}
