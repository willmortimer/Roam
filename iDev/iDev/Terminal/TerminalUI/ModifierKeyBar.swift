import SwiftUI

/// Floating modifier key bar for terminal sessions.
/// Provides Esc, Ctrl, Alt/Meta, Tab, and arrow keys.
struct ModifierKeyBar: View {
    let onKey: (ModifierKey) -> Void

    @State private var ctrlActive = false
    @State private var metaActive = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Escape
                keyButton("Esc") { onKey(.escape) }

                // Ctrl toggle
                toggleButton("Ctrl", isActive: $ctrlActive) {
                    if ctrlActive {
                        // Send next key as Ctrl+key
                    }
                }

                // Meta/Alt toggle
                toggleButton("Alt", isActive: $metaActive) {
                    if metaActive {
                        // Send next key with ESC prefix
                    }
                }

                // Tab
                keyButton("Tab") { onKey(.tab) }

                Divider()
                    .frame(height: 24)

                // Arrow keys
                keyButton("←") { onKey(.arrowLeft) }
                keyButton("↑") { onKey(.arrowUp) }
                keyButton("↓") { onKey(.arrowDown) }
                keyButton("→") { onKey(.arrowRight) }

                Divider()
                    .frame(height: 24)

                // Common shortcuts
                keyButton("^C") { onKey(.ctrlC) }
                keyButton("^D") { onKey(.ctrlD) }
                keyButton("^Z") { onKey(.ctrlZ) }
                keyButton("^L") { onKey(.ctrlL) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    private func keyButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func toggleButton(_ label: String, isActive: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button {
            isActive.wrappedValue.toggle()
            action()
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isActive.wrappedValue ? Color.accentColor.opacity(0.3) : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modifier Key Enum

enum ModifierKey: Sendable {
    case escape
    case tab
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case ctrlC
    case ctrlD
    case ctrlZ
    case ctrlL

    /// The byte sequence to send to the terminal.
    var bytes: Data {
        switch self {
        case .escape:     Data([0x1B])
        case .tab:        Data([0x09])
        case .arrowUp:    Data([0x1B, 0x5B, 0x41]) // ESC [ A
        case .arrowDown:  Data([0x1B, 0x5B, 0x42]) // ESC [ B
        case .arrowRight: Data([0x1B, 0x5B, 0x43]) // ESC [ C
        case .arrowLeft:  Data([0x1B, 0x5B, 0x44]) // ESC [ D
        case .ctrlC:      Data([0x03])
        case .ctrlD:      Data([0x04])
        case .ctrlZ:      Data([0x1A])
        case .ctrlL:      Data([0x0C])
        }
    }
}
