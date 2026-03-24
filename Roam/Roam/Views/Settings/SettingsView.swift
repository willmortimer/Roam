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
            Section("Local Storage") {
                LocalStorageSettingsSection()
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

                Link(destination: URL(string: "https://github.com/willmortimer/roam")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                NavigationLink {
                    LicensesView()
                } label: {
                    Label("Third-Party Licenses", systemImage: "doc.text")
                }

                Text("Roam is an open-source remote development workspace for iPhone and iPad, built around SSH, saved workspaces, and fast session recovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Licenses

private struct LicensesView: View {
    var body: some View {
        List {
            Section("Fonts") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("JetBrains Mono Nerd Fonts")
                        .font(.headline)
                    Text("Copyright 2020 The JetBrains Mono Project Authors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("SIL Open Font License 1.1")
                        .codeBadge(color: .accentColor)
                }
                .padding(.vertical, Spacing.xs)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Meslo LG Nerd Fonts")
                        .font(.headline)
                    Text("Copyright 2009, 2010, 2013 Andre Berg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Apache License 2.0")
                        .codeBadge(color: .accentColor)
                }
                .padding(.vertical, Spacing.xs)
            }

            Section("Libraries") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("libssh2")
                        .font(.headline)
                    Text("BSD-3-Clause License")
                        .codeBadge(color: .accentColor)
                }
                .padding(.vertical, Spacing.xs)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SwiftTerm")
                        .font(.headline)
                    Text("MIT License")
                        .codeBadge(color: .accentColor)
                }
                .padding(.vertical, Spacing.xs)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Yams")
                        .font(.headline)
                    Text("MIT License")
                        .codeBadge(color: .accentColor)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Local Storage Settings

private struct LocalStorageSettingsSection: View {
    private let fileService = LocalFileService.shared
    @State private var storageSize: String = "Calculating..."
    @State private var iCloudEnabled: Bool = LocalFileService.shared.isICloudEnabled

    var body: some View {
        Toggle("iCloud Drive Sync", isOn: $iCloudEnabled)
            .onChange(of: iCloudEnabled) { _, newValue in
                fileService.isICloudEnabled = newValue
            }

        if !fileService.isICloudAvailable && iCloudEnabled {
            Text("iCloud is not available on this device. Files will be stored locally.")
                .font(.caption)
                .foregroundStyle(.Roam.caution)
        } else if iCloudEnabled {
            Text("Local files are synced to iCloud Drive and available across your devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Files are stored locally in the app's documents directory.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Storage Used", value: storageSize)

        NavigationLink {
            LocalFileBrowserView()
        } label: {
            Label("Browse Local Files", systemImage: "folder")
        }
    }

    private func calculateSize() {
        let bytes = fileService.homeDirectorySize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        storageSize = formatter.string(fromByteCount: Int64(bytes))
    }
}
