import SwiftUI

/// Local file browser for the Roam home directory.
struct LocalFileBrowserView: View {
    var initialURL: URL?

    private let fileService = LocalFileService.shared

    @State private var currentURL: URL
    @State private var entries: [LocalFileService.LocalFileEntry] = []
    @State private var errorMessage: String?
    @State private var navigationStack: [URL] = []

    // Actions
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var showingNewFile = false
    @State private var newFileName = ""
    @State private var renameTarget: LocalFileService.LocalFileEntry?
    @State private var renameText = ""
    @State private var deleteConfirmTarget: LocalFileService.LocalFileEntry?

    init(initialURL: URL? = nil) {
        let url = initialURL ?? LocalFileService.shared.homeDirectory
        self.initialURL = initialURL
        self._currentURL = State(initialValue: url)
    }

    private var isAtHome: Bool {
        currentURL == fileService.homeDirectory
    }

    private var directoryTitle: String {
        if isAtHome { return "Local Files" }
        return currentURL.lastPathComponent
    }

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                fileList
            }
        }
        .navigationTitle(directoryTitle)
        .toolbar { toolbarItems }
        .onAppear { loadDirectory() }
        .refreshable { loadDirectory() }
        .sheet(isPresented: $showingNewFolder) {
            newFolderSheet
        }
        .sheet(isPresented: $showingNewFile) {
            newFileSheet
        }
        .sheet(isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            renameSheet
        }
        .confirmationDialog(
            "Delete \(deleteConfirmTarget?.name ?? "")?",
            isPresented: .init(
                get: { deleteConfirmTarget != nil },
                set: { if !$0 { deleteConfirmTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteConfirmTarget {
                    deleteItem(target)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            if !isAtHome {
                Button {
                    navigateUp()
                } label: {
                    Label("Go up one directory", systemImage: "folder")
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                }
            }

            let sorted = entries.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            ForEach(sorted) { entry in
                localFileRow(entry: entry)
                    .contextMenu {
                        contextMenuItems(for: entry)
                    }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: LocalEditorDestination.self) { dest in
            LocalFileEditorView(fileURL: dest.url)
        }
    }

    private func localFileRow(entry: LocalFileService.LocalFileEntry) -> some View {
        Button {
            if entry.isDirectory {
                navigateTo(entry.url)
            }
        } label: {
            HStack {
                Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(for: entry.name))
                    .foregroundStyle(entry.isDirectory ? Color.accentColor : Color(.secondaryLabel))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.sm) {
                        if !entry.isDirectory {
                            Text(formatSize(entry.size))
                        }
                        Text(entry.modifiedDate, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if isTextFile(entry.name) {
                    NavigationLink(value: LocalEditorDestination(url: entry.url)) {
                        EmptyView()
                    }
                    .frame(width: 0)
                    .opacity(0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.isDirectory ? "Folder" : "File"): \(entry.name)")
    }

    @ViewBuilder
    private func contextMenuItems(for entry: LocalFileService.LocalFileEntry) -> some View {
        if !entry.isDirectory && isTextFile(entry.name) {
            NavigationLink("Open in Editor", value: LocalEditorDestination(url: entry.url))
        }

        if !entry.isDirectory {
            ShareLink(item: entry.url)
        }

        Button("Rename", systemImage: "pencil") {
            renameText = entry.name
            renameTarget = entry
        }

        Button("Delete", systemImage: "trash", role: .destructive) {
            deleteConfirmTarget = entry
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("New Folder", systemImage: "folder.badge.plus") {
                    newFolderName = ""
                    showingNewFolder = true
                }
                Button("New File", systemImage: "doc.badge.plus") {
                    newFileName = ""
                    showingNewFile = true
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Create folder or file")
        }
    }

    // MARK: - Sheets

    private var newFolderSheet: some View {
        NavigationStack {
            Form {
                Section("New Folder") {
                    TextField("Folder name", text: $newFolderName)
                }
                Section {
                    Button {
                        createFolder()
                        showingNewFolder = false
                    } label: {
                        Text("Create").frame(maxWidth: .infinity)
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingNewFolder = false }
                }
            }
        }
    }

    private var newFileSheet: some View {
        NavigationStack {
            Form {
                Section("New File") {
                    TextField("Filename (e.g. notes.md)", text: $newFileName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button {
                        createFile()
                        showingNewFile = false
                    } label: {
                        Text("Create").frame(maxWidth: .infinity)
                    }
                    .disabled(newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("New File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingNewFile = false }
                }
            }
        }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section("Rename") {
                    TextField("New name", text: $renameText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Button {
                        performRename()
                    } label: {
                        Text("Rename").frame(maxWidth: .infinity)
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { renameTarget = nil }
                }
            }
        }
    }

    // MARK: - Navigation

    private func loadDirectory() {
        do {
            entries = try fileService.listDirectory(at: currentURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func navigateTo(_ url: URL) {
        navigationStack.append(currentURL)
        currentURL = url
        loadDirectory()
    }

    private func navigateUp() {
        if let previous = navigationStack.popLast() {
            currentURL = previous
        } else {
            currentURL = currentURL.deletingLastPathComponent()
        }
        loadDirectory()
    }

    // MARK: - File Operations

    private func createFolder() {
        guard !newFolderName.isEmpty else { return }
        do {
            try fileService.createDirectory(at: currentURL, name: newFolderName)
            newFolderName = ""
            loadDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFile() {
        guard !newFileName.isEmpty else { return }
        do {
            _ = try fileService.createFile(in: currentURL, name: newFileName)
            newFileName = ""
            loadDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem(_ entry: LocalFileService.LocalFileEntry) {
        do {
            try fileService.deleteItem(at: entry.url)
            entries.removeAll { $0.id == entry.id }
            deleteConfirmTarget = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRename() {
        guard let target = renameTarget, !renameText.isEmpty, renameText != target.name else {
            renameTarget = nil
            return
        }
        do {
            _ = try fileService.renameItem(at: target.url, newName: renameText)
            renameTarget = nil
            renameText = ""
            loadDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private static let textExtensions: Set<String> = [
        "swift", "rs", "py", "pyi", "js", "jsx", "ts", "tsx", "mjs", "cjs", "mts",
        "json", "jsonl", "yaml", "yml", "toml", "xml", "plist", "csv",
        "md", "markdown", "txt", "log", "cfg", "conf", "ini", "env",
        "sh", "bash", "zsh", "fish",
        "html", "htm", "css", "scss", "less", "svg",
        "c", "h", "cpp", "hpp", "m", "mm",
        "java", "kt", "go", "rb", "php", "lua", "zig", "nim",
        "dockerfile", "makefile", "justfile", "gitignore", "editorconfig",
    ]

    private func isTextFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if Self.textExtensions.contains(ext) { return true }
        let lower = name.lowercased()
        return lower == "dockerfile" || lower == "makefile" || lower == "justfile"
            || lower == ".gitignore" || lower == ".editorconfig" || lower == ".env"
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift", "rs", "py", "js", "ts", "go", "rb", "java", "c", "h", "cpp":
            return "doc.text"
        case "json", "yaml", "yml", "toml", "xml":
            return "doc.badge.gearshape"
        case "md", "txt", "log":
            return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg":
            return "photo"
        case "zip", "tar", "gz":
            return "doc.zipper"
        case "sh", "bash", "zsh":
            return "terminal"
        default:
            return "doc"
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Navigation Types

struct LocalEditorDestination: Hashable {
    let url: URL
}
