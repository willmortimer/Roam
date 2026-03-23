import SwiftUI
import SwiftTerm

/// UIViewRepresentable wrapping SwiftTerm's iOS `TerminalView`.
/// Bridges between SwiftUI lifecycle and the UIKit terminal emulator.
struct TerminalViewRepresentable: UIViewRepresentable {
    let bridge: any TerminalSessionBridgeProtocol
    var font: UIFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero, font: font)
        terminal.terminalDelegate = context.coordinator
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .white
        terminal.optionAsMetaKey = true
        terminal.allowMouseReporting = true
        terminal.becomeFirstResponder()
        context.coordinator.startReading(terminal: terminal)
        return terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Font changes can be applied here if needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        private let bridge: any TerminalSessionBridgeProtocol
        private var readTask: Task<Void, Never>?

        init(bridge: any TerminalSessionBridgeProtocol) {
            self.bridge = bridge
            super.init()
        }

        deinit {
            readTask?.cancel()
        }

        /// Start reading from the remote and feeding into the terminal.
        func startReading(terminal: TerminalView) {
            readTask?.cancel()
            readTask = Task { [weak self, weak terminal] in
                guard let self else { return }
                do {
                    for try await data in self.bridge.remoteDataStream() {
                        guard !Task.isCancelled else { break }
                        let bytes = ArraySlice(data)
                        terminal?.feed(byteArray: bytes)
                    }
                } catch {
                    // Stream ended or error — connection likely dropped
                }
            }
        }

        // MARK: - TerminalViewDelegate

        nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bridgeRef = bridge
            Task {
                try? await bridgeRef.sendToRemote(Data(data))
            }
        }

        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            let bridgeRef = bridge
            Task {
                try? await bridgeRef.resizePTY(columns: newCols, rows: newRows)
            }
        }

        nonisolated func setTerminalTitle(source: TerminalView, title: String) {
            // Could update a @Published title property here
        }

        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could track CWD for workspace context
        }

        nonisolated func scrolled(source: TerminalView, position: Double) {
            // No-op
        }

        nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }

        nonisolated func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                Task { @MainActor in
                    UIPasteboard.general.string = text
                }
            }
        }

        nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
            // No-op
        }

        nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
            // No-op
        }

        nonisolated func bell(source: TerminalView) {
            Task { @MainActor in
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        }
    }
}
