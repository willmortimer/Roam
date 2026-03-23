import SwiftUI
import iDevSSH

/// SFTP file browser with directory navigation, download, upload, and file management.
struct FileBrowserView: View {
    let sftpChannel: SFTPChannel?
    var initialPath: String = "/"

    @State private var currentPath: String = "/"
    @State private var entries: [SFTPFileEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigationPath: [String] = []

    // Transfer state
    @State private var activeTransfer: FileTransferState?
    @State private var showingUploadPicker = false
    @State private var showingNewFolder = false
    @State private var newFolderName = ""

    // Context actions
    @State private var renameTarget: SFTPFileEntry?
    @State private var renameText = ""

    var body: some View {
        Group {
            if sftpChannel == nil {
                ContentUnavailableView(
                    "No Connection",
                    systemImage: "folder",
                    description: Text("Connect to a host to browse files via SFTP.")
                )
            } else if isLoading && entries.isEmpty {
                ProgressView("Loading...")
            } else if let errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                fileList
            }
        }
        .navigationTitle(currentPath.split(separator: "/").last.map(String.init) ?? "Files")
        .toolbar {
            if sftpChannel != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Folder", systemImage: "folder.badge.plus") {
                            newFolderName = ""
                            showingNewFolder = true
                        }
                        Button("Upload File", systemImage: "arrow.up.doc") {
                            showingUploadPicker = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            currentPath = initialPath
            await loadDirectory(path: initialPath)
        }
        .refreshable {
            await loadDirectory(path: currentPath)
        }
        .alert("New Folder", isPresented: $showingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { Task { await createFolder() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Rename") { Task { await performRename() } }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .overlay {
            if let transfer = activeTransfer {
                FileTransferOverlay(state: transfer)
            }
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            // Parent directory
            if currentPath != "/" {
                Button {
                    Task { await navigateUp() }
                } label: {
                    Label("..", systemImage: "folder")
                        .foregroundStyle(.primary)
                }
            }

            // Directories first, then files, alphabetical
            let sorted = entries.sorted { a, b in
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            ForEach(sorted, id: \.name) { entry in
                FileEntryRow(entry: entry) {
                    if entry.isDirectory {
                        Task { await navigateTo(entry.name) }
                    } else {
                        Task { await downloadFile(entry) }
                    }
                }
                .contextMenu {
                    if !entry.isDirectory {
                        if isTextFile(entry.name) {
                            NavigationLink("Open in Editor", value: fullPath(for: entry))
                        }
                        Button("Download", systemImage: "arrow.down.circle") {
                            Task { await downloadFile(entry) }
                        }
                    }
                    Button("Rename", systemImage: "pencil") {
                        renameText = entry.name
                        renameTarget = entry
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await deleteEntry(entry) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: EditorDestination.self) { dest in
            if let sftp = sftpChannel {
                FileEditorView(filePath: dest.path, sftpChannel: sftp)
            }
        }
    }

    // MARK: - File Helpers

    private func fullPath(for entry: SFTPFileEntry) -> EditorDestination {
        let path = currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)"
        return EditorDestination(path: path)
    }

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
        // Also match extensionless known files
        let lower = name.lowercased()
        return lower == "dockerfile" || lower == "makefile" || lower == "justfile"
            || lower == ".gitignore" || lower == ".editorconfig" || lower == ".env"
    }

    // MARK: - Navigation

    private func loadDirectory(path: String) async {
        guard let sftp = sftpChannel else { return }
        isLoading = true
        errorMessage = nil

        do {
            entries = try await sftp.listDirectory(path: path)
            currentPath = path
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func navigateTo(_ name: String) async {
        let newPath = currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
        navigationPath.append(currentPath)
        await loadDirectory(path: newPath)
    }

    private func navigateUp() async {
        if let previous = navigationPath.popLast() {
            await loadDirectory(path: previous)
        } else {
            let parent = (currentPath as NSString).deletingLastPathComponent
            await loadDirectory(path: parent.isEmpty ? "/" : parent)
        }
    }

    // MARK: - File Operations

    private func downloadFile(_ entry: SFTPFileEntry) async {
        guard let sftp = sftpChannel else { return }

        let remotePath = currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)"
        let transfer = FileTransferState(filename: entry.name, totalBytes: Int64(entry.size), isUploading: false)
        activeTransfer = transfer

        do {
            var data = Data()
            for try await chunk in sftp.download(remotePath: remotePath) {
                data.append(chunk)
                transfer.transferredBytes = Int64(data.count)
            }

            // Save to temp and share
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
            try data.write(to: tempURL)
            transfer.completedURL = tempURL

            activeTransfer = nil
        } catch {
            transfer.error = error.localizedDescription
            try? await Task.sleep(for: .seconds(2))
            activeTransfer = nil
        }
    }

    private func createFolder() async {
        guard let sftp = sftpChannel, !newFolderName.isEmpty else { return }
        let path = currentPath == "/" ? "/\(newFolderName)" : "\(currentPath)/\(newFolderName)"

        do {
            try await sftp.mkdir(path: path)
            await loadDirectory(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRename() async {
        guard let sftp = sftpChannel,
              let target = renameTarget,
              !renameText.isEmpty,
              renameText != target.name else {
            renameTarget = nil
            return
        }

        let fromPath = currentPath == "/" ? "/\(target.name)" : "\(currentPath)/\(target.name)"
        let toPath = currentPath == "/" ? "/\(renameText)" : "\(currentPath)/\(renameText)"
        renameTarget = nil

        do {
            try await sftp.rename(from: fromPath, to: toPath)
            await loadDirectory(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEntry(_ entry: SFTPFileEntry) async {
        guard let sftp = sftpChannel else { return }
        let path = currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)"

        do {
            try await sftp.remove(path: path)
            entries.removeAll { $0.name == entry.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - File Entry Row

private struct FileEntryRow: View {
    let entry: SFTPFileEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(for: entry.name))
                    .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
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
                }
            }
        }
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

// MARK: - Transfer State

@Observable
class FileTransferState {
    let filename: String
    let totalBytes: Int64
    let isUploading: Bool
    var transferredBytes: Int64 = 0
    var error: String?
    var completedURL: URL?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(transferredBytes) / Double(totalBytes)
    }

    init(filename: String, totalBytes: Int64, isUploading: Bool) {
        self.filename = filename
        self.totalBytes = totalBytes
        self.isUploading = isUploading
    }
}

// MARK: - Editor Destination

struct EditorDestination: Hashable {
    var path: String
}

// MARK: - Transfer Overlay

private struct FileTransferOverlay: View {
    let state: FileTransferState

    var body: some View {
        VStack(spacing: 12) {
            if let error = state.error {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.iDev.danger)
                Text(error)
                    .font(.caption)
            } else {
                ProgressView(value: state.progress) {
                    Text(state.isUploading ? "Uploading..." : "Downloading...")
                        .font(.caption)
                } currentValueLabel: {
                    Text(state.filename)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}
