import SwiftUI

// MARK: - Spacing Scale

/// 4pt base spacing scale. Use these everywhere instead of hardcoded values.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Semantic Colors

/// Top-level namespace for Roam semantic colors.
/// Accessible as `.Roam.alive` in both `Color` and `ShapeStyle` contexts.
enum RoamPalette {
    static let codeBackground = Color("CodeBackground", bundle: .main)
    static let cardSurface = Color(UIColor.secondarySystemGroupedBackground)
    static let alive = Color("TerminalGreen", bundle: .main)
    static let caution = Color("TerminalAmber", bundle: .main)
    static let danger = Color(.systemRed)
    static let dormant = Color(.tertiaryLabel)

    static func environmentColor(_ env: String) -> Color {
        switch env.lowercased() {
        case "prod", "production": danger
        case "staging": caution
        default: .accentColor
        }
    }

    static func trustColor(_ trust: TrustClass) -> Color {
        switch trust {
        case .trustedDev: .accentColor
        case .production: caution
        case .untrusted: danger
        }
    }
}

/// Enables `.Roam.alive` inside `.foregroundStyle()` and other ShapeStyle contexts.
extension ShapeStyle where Self == Color {
    static var Roam: RoamPalette.Type { RoamPalette.self }
}

/// Enables `Color.Roam.alive` for explicit Color references.
extension Color {
    static var Roam: RoamPalette.Type { RoamPalette.self }
}

// MARK: - Typography

extension Font {
    /// SF Mono for machine-readable text: addresses, ports, fingerprints.
    static func mono(_ style: TextStyle = .caption) -> Font {
        .system(style, design: .monospaced)
    }

    /// Bold mono for badges and labels.
    static func monoBold(_ style: TextStyle = .caption2) -> Font {
        .system(style, design: .monospaced).bold()
    }
}

// MARK: - View Modifiers

/// Elevated card surface with subtle shadow.
struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(Spacing.md)
            .background(RoamPalette.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.06),
                radius: 3, x: 0, y: 1
            )
    }
}

/// Monospaced capsule badge for environments, tags, ports.
struct CodeBadge: ViewModifier {
    var color: Color = .accentColor

    func body(content: Content) -> some View {
        content
            .font(.monoBold())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Small filled status dot overlay.
struct StatusDot: ViewModifier {
    var color: Color

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .offset(x: 2, y: -2)
        }
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func codeBadge(color: Color = .accentColor) -> some View {
        modifier(CodeBadge(color: color))
    }

    func statusDot(_ color: Color) -> some View {
        modifier(StatusDot(color: color))
    }
}

// MARK: - Reusable Components

/// Environment capsule badge with semantic color.
struct EnvironmentBadge: View {
    let environment: String

    private var label: String {
        switch environment.lowercased() {
        case "prod", "production": "PROD"
        case "staging": "STG"
        case "dev", "development": "DEV"
        default: environment.uppercased()
        }
    }

    var body: some View {
        Text(label)
            .codeBadge(color: RoamPalette.environmentColor(environment))
    }
}

/// Trust class capsule badge.
struct TrustBadge: View {
    let trustClass: TrustClass

    private var label: String {
        switch trustClass {
        case .trustedDev: "TRUSTED"
        case .production: "PROD"
        case .untrusted: "UNTRUSTED"
        }
    }

    var body: some View {
        Text(label)
            .codeBadge(color: RoamPalette.trustColor(trustClass))
    }
}

/// Transport type badge (SSH / MOSH).
struct TransportBadge: View {
    let transport: TransportType

    var body: some View {
        Text(transport.rawValue.uppercased())
            .codeBadge(color: transport == .mosh ? RoamPalette.caution : RoamPalette.dormant)
    }
}

/// Small inline status indicator dot.
struct ConnectionDot: View {
    let state: ConnectionLiveness

    enum ConnectionLiveness {
        case connected
        case connecting
        case disconnected
        case unknown
    }

    private var color: Color {
        switch state {
        case .connected: RoamPalette.alive
        case .connecting: RoamPalette.caution
        case .disconnected: RoamPalette.danger
        case .unknown: RoamPalette.dormant
        }
    }

    private var label: String {
        switch state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnected: "Disconnected"
        case .unknown: "Unknown"
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }
}

/// Monospaced address label: user@host:port
struct AddressLabel: View {
    let username: String
    let hostname: String
    let port: Int

    var body: some View {
        Text("\(username)@\(hostname):\(port)")
            .font(.mono())
            .foregroundStyle(.secondary)
    }
}
