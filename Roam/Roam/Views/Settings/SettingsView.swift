import SwiftUI

struct SettingsView: View {
    private var lowBandwidth = LowBandwidthService.shared

    @AppStorage("appearance") private var appearance: AppAppearance = .system

    var body: some View {
        List {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }

                NavigationLink {
                    TerminalSettingsView()
                } label: {
                    Label("Terminal", systemImage: "textformat")
                }
            }
            Section("Security") {
                NavigationLink {
                    BiometricSettingsView()
                } label: {
                    Label("Biometric Lock", systemImage: "faceid")
                }
            }
            Section("Data") {
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                NavigationLink {
                    ImportView()
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
            }
            Section("Sync") {
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    Label("Sync Settings", systemImage: "arrow.triangle.2.circlepath")
                }
                NavigationLink {
                    TeamVaultView()
                } label: {
                    Label("Team Vaults", systemImage: "person.3")
                }
            }
            Section("Performance") {
                Toggle("Low Bandwidth Mode", isOn: Bindable(lowBandwidth).isEnabled)
                if lowBandwidth.isEnabled {
                    Text("Reduces polling frequency, disables animations, and throttles terminal refresh rate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                Text("Roam is an open-source remote development workspace for iPhone and iPad, built around SSH, saved workspaces, and fast session recovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Designed for terminal-first development away from your desk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Appearance

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
