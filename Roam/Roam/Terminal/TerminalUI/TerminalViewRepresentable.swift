import SwiftUI
import SwiftTerm

/// UIViewRepresentable wrapping SwiftTerm's iOS `TerminalView`.
/// Bridges between SwiftUI lifecycle and the UIKit terminal emulator.
struct TerminalViewRepresentable: UIViewRepresentable {
    let bridge: any TerminalSessionBridgeProtocol
    let sessionState: TerminalSessionState
    var fontFamily: TerminalFontFamily = .system
    var fontSize: CGFloat = 13

    private var fontFaces: TerminalFontFaces {
        TerminalFontCatalog.faces(for: fontFamily, size: fontSize)
    }

    func makeUIView(context: Context) -> TerminalHostingView {
        let hostView = TerminalHostingView(fontFaces: fontFaces)
        let terminal = hostView.terminal
        // Use the system keyboard. SwiftTerm's built-in accessory can swap in
        // a symbols-only KeyboardView, which is confusing on iPhone and noisy
        // in the simulator. Roam provides its own modifier bar below.
        terminal.inputAccessoryView = nil
        // `nil` disables content-type heuristics more reliably than SwiftTerm's
        // default `.none`, which can confuse the simulator input stack.
        terminal.textContentType = nil
        terminal.terminalDelegate = context.coordinator
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .white
        terminal.optionAsMetaKey = true
        terminal.allowMouseReporting = true
        context.coordinator.startReading(terminal: terminal)
        return hostView
    }

    func updateUIView(_ uiView: TerminalHostingView, context: Context) {
        uiView.updateFonts(fontFaces)
        uiView.refreshInputFocus()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge, sessionState: sessionState)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, TerminalViewDelegate {
        private let bridge: any TerminalSessionBridgeProtocol
        private let sessionState: TerminalSessionState
        private var readTask: Task<Void, Never>?

        init(bridge: any TerminalSessionBridgeProtocol, sessionState: TerminalSessionState) {
            self.bridge = bridge
            self.sessionState = sessionState
            super.init()
        }

        deinit {
            readTask?.cancel()
        }

        /// Start reading from the remote and feeding into the terminal.
        func startReading(terminal: TerminalView) {
            readTask?.cancel()
            let bridge = bridge
            let state = sessionState
            readTask = Task { [weak terminal] in
                do {
                    for try await data in bridge.remoteDataStream() {
                        guard !Task.isCancelled else { break }
                        let bytes = ArraySlice(data)
                        await MainActor.run {
                            terminal?.feed(byteArray: bytes)
                            state.recordReceived(bytes: data.count)
                        }
                    }
                } catch {
                    // Stream ended or error — connection likely dropped
                }
            }
        }

        // MARK: - TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bridgeRef = bridge
            let state = sessionState
            Task {
                try? await bridgeRef.sendToRemote(Data(data))
                await MainActor.run { state.recordSent(bytes: data.count) }
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            let bridgeRef = bridge
            let state = sessionState
            Task {
                try? await bridgeRef.resizePTY(columns: newCols, rows: newRows)
                await MainActor.run {
                    state.columns = newCols
                    state.rows = newRows
                }
            }
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            let state = sessionState
            Task { @MainActor in
                state.terminalTitle = title
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            let state = sessionState
            Task { @MainActor in
                state.currentWorkingDirectory = directory
            }
        }

        func scrolled(source: TerminalView, position: Double) {
            // No-op
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                Task { @MainActor in
                    UIPasteboard.general.string = text
                    ClipboardHistoryService.shared.record(text: text)
                }
            }
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
            // No-op
        }

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
            // No-op
        }

        func bell(source: TerminalView) {
            Task { @MainActor in
                #if !targetEnvironment(simulator)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                #endif
            }
        }
    }
}

final class TerminalHostingView: UIView {
    let terminal: HostedTerminalView

    init(fontFaces: TerminalFontFaces) {
        self.terminal = HostedTerminalView(frame: .zero, font: fontFaces.normal)
        super.init(frame: .zero)
        updateFonts(fontFaces)

        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)

        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshInputFocus()
    }

    func updateFonts(_ fontFaces: TerminalFontFaces) {
        terminal.setFonts(
            normal: fontFaces.normal,
            bold: fontFaces.bold,
            italic: fontFaces.italic,
            boldItalic: fontFaces.boldItalic
        )
    }

    func refreshInputFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.terminal.reloadInputViews()
            if !self.terminal.isFirstResponder {
                _ = self.terminal.becomeFirstResponder()
            }
        }
    }
}

final class HostedTerminalView: TerminalView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.reloadInputViews()
            if !self.isFirstResponder {
                _ = self.becomeFirstResponder()
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            reloadInputViews()
        }
        return becameFirstResponder
    }
}
