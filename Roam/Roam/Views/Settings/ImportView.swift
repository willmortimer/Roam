import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import app data from an encrypted .roambackup file.
struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingHosts: [HostRecord]
    @Query private var existingWorkspaces: [WorkspaceRecord]
    @Query private var existingSnippets: [SnippetRecord]

    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var password = ""
    @State private var preview: ImportPreview?
    @State private var result: ImportResult?
    @State private var isDecrypting = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // Step 1: Select file
            Section("Select Backup File") {
                Button {
                    showFilePicker = true
                } label: {
                    Label(
                        selectedFileURL?.lastPathComponent ?? "Choose .roambackup file",
                        systemImage: "doc"
                    )
                }
            }

            // Step 2: Password
            if selectedFileURL != nil {
                Section("Password") {
                    SecureField("Backup password", text: $password)
                    Button {
                        Task { await decryptAndPreview() }
                    } label: {
                        if isDecrypting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Decrypt")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(password.isEmpty || isDecrypting)
                }
            }

            // Step 3: Preview
            if let preview {
                Section("Backup Contents") {
                    LabeledContent("Exported", value: preview.exportedAt)
                    LabeledContent("Hosts", value: "\(preview.hostCount)")
                    LabeledContent("Workspaces", value: "\(preview.workspaceCount)")
                    LabeledContent("Snippets", value: "\(preview.snippetCount)")
                    if preview.keyCount > 0 {
                        LabeledContent("SSH Keys", value: "\(preview.keyCount)")
                    }
                }

                Section {
                    Button {
                        Task { await doImport() }
                    } label: {
                        if isImporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Import")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isImporting)
                }
            }

            // Result
            if let result {
                Section {
                    Label(result.summary, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.Roam.alive)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.Roam.danger)
                }
            }
        }
        .navigationTitle("Import")
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { fileResult in
            switch fileResult {
            case .success(let urls):
                selectedFileURL = urls.first
                preview = nil
                result = nil
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func decryptAndPreview() async {
        guard let url = selectedFileURL else { return }
        isDecrypting = true
        errorMessage = nil

        do {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let service = ImportService()
            preview = try service.preview(blob: data, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isDecrypting = false
    }

    private func doImport() async {
        guard let preview else { return }
        isImporting = true
        errorMessage = nil

        do {
            let service = ImportService()
            result = try service.apply(
                preview,
                existingHostIDs: Set(existingHosts.map(\.id)),
                existingWorkspaceIDs: Set(existingWorkspaces.map(\.id)),
                existingSnippetIDs: Set(existingSnippets.map(\.id)),
                modelContext: modelContext,
                vault: VaultService.shared
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}
