import SwiftUI
import SwiftData

/// Allows users to import hosts from their ~/.ssh/config file.
struct SSHConfigImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HostRecord.alias) private var existingHosts: [HostRecord]

    @State private var entries: [SSHConfigEntry] = []
    @State private var selected: Set<String> = []
    @State private var importCount = 0
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if !hasLoaded {
                ProgressView("Reading SSH config...")
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Hosts Found",
                    systemImage: "doc.text",
                    description: Text("No importable hosts were found in ~/.ssh/config.\nWildcard entries and patterns are skipped.")
                )
            } else if importCount > 0 {
                importCompleteView
            } else {
                entryList
            }
        }
        .navigationTitle("Import SSH Config")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if !entries.isEmpty && importCount == 0 {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selected.count)") {
                        performImport()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .task {
            entries = SSHConfigParser.parseDefaultConfig()
            // Pre-select entries that don't already exist
            let existingAliases = Set(existingHosts.map(\.alias))
            for entry in entries where !existingAliases.contains(entry.alias) {
                selected.insert(entry.alias)
            }
            hasLoaded = true
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            Section {
                HStack {
                    Text("\(entries.count) hosts found in ~/.ssh/config")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(selected.count == entries.count ? "Deselect All" : "Select All") {
                        if selected.count == entries.count {
                            selected.removeAll()
                        } else {
                            selected = Set(entries.map(\.alias))
                        }
                    }
                    .font(.subheadline)
                }
            }

            Section("Hosts") {
                ForEach(entries, id: \.alias) { entry in
                    SSHConfigEntryRow(
                        entry: entry,
                        isSelected: selected.contains(entry.alias),
                        alreadyExists: existingHosts.contains(where: { $0.alias == entry.alias })
                    ) {
                        if selected.contains(entry.alias) {
                            selected.remove(entry.alias)
                        } else {
                            selected.insert(entry.alias)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Import Complete

    private var importCompleteView: some View {
        ContentUnavailableView(
            "Imported \(importCount) Host\(importCount == 1 ? "" : "s")",
            systemImage: "checkmark.circle",
            description: Text("Your SSH hosts have been added to iDev.")
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }

    // MARK: - Import Logic

    private func performImport() {
        var count = 0
        for entry in entries where selected.contains(entry.alias) {
            let host = HostRecord(
                alias: entry.alias,
                hostname: entry.hostname,
                port: entry.port,
                username: entry.user ?? "root"
            )
            modelContext.insert(host)
            count += 1
        }
        importCount = count
    }
}

// MARK: - Entry Row

private struct SSHConfigEntryRow: View {
    let entry: SSHConfigEntry
    let isSelected: Bool
    let alreadyExists: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                    .font(.title3)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text(entry.alias)
                            .font(.headline)
                        if alreadyExists {
                            Text("exists")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.fill.tertiary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("\(entry.user ?? "—")@\(entry.hostname):\(entry.port)")
                        .font(.mono(.caption))
                        .foregroundStyle(.secondary)

                    if let identityFile = entry.identityFile {
                        Label(identityFile, systemImage: "key")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let proxy = entry.proxyJump {
                        Label("via \(proxy)", systemImage: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.alias), \(entry.user ?? "no user") at \(entry.hostname) port \(entry.port)\(alreadyExists ? ", already imported" : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to toggle selection.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
