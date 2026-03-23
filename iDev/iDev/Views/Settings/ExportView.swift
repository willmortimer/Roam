import SwiftUI
import SwiftData

/// Export app data as an encrypted .idevbackup file.
struct ExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var hosts: [HostRecord]
    @Query private var workspaces: [WorkspaceRecord]
    @Query private var snippets: [SnippetRecord]

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var includeKeys = false
    @State private var isExporting = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var body: some View {
        Form {
            Section("Data to Export") {
                LabeledContent("Hosts", value: "\(hosts.count)")
                LabeledContent("Workspaces", value: "\(workspaces.count)")
                LabeledContent("Snippets", value: "\(snippets.count)")
            }

            Section("Security") {
                SecureField("Password", text: $password)
                SecureField("Confirm Password", text: $confirmPassword)

                Toggle("Include SSH Private Keys", isOn: $includeKeys)

                if includeKeys {
                    Label("Private keys will be encrypted within the backup. Only share this file with trusted devices.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.iDev.caution)
                }
            }

            Section {
                Button {
                    Task { await doExport() }
                } label: {
                    if isExporting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Export")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!passwordsMatch || isExporting)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.iDev.danger)
                }
            }
        }
        .navigationTitle("Export")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func doExport() async {
        isExporting = true
        errorMessage = nil

        do {
            let service = ExportService()
            let blob = try service.exportAll(
                password: password,
                includeKeys: includeKeys,
                hosts: hosts,
                workspaces: workspaces,
                snippets: snippets
            )

            let filename = "idev-backup-\(formattedDate()).idevbackup"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try blob.write(to: url)
            exportedURL = url
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isExporting = false
    }

    private func formattedDate() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: .now)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
