import SwiftUI
import iDevSSH

/// Lightweight text editor for remote files, with syntax highlighting and line numbers.
/// Intentionally minimal — not a full IDE.
struct FileEditorView: View {
    let filePath: String
    let sftpChannel: SFTPChannel

    @State private var editorService = FileEditorService()
    @State private var showSearch = false
    @State private var searchText = ""

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var fileExtension: String {
        (fileName as NSString).pathExtension
    }

    private var language: SyntaxHighlighter.Language {
        // Handle Dockerfile specially (no extension)
        if fileName.lowercased().hasPrefix("dockerfile") { return .dockerfile }
        return .from(extension: fileExtension)
    }

    var body: some View {
        Group {
            if editorService.isLoading {
                ProgressView("Loading \(fileName)...")
            } else if let error = editorService.errorMessage, editorService.content.isEmpty {
                ContentUnavailableView(
                    "Cannot Open File",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                editorContent
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .task {
            await editorService.loadFile(path: filePath, sftpChannel: sftpChannel)
        }
        .overlay(alignment: .top) {
            if showSearch {
                searchBar
            }
        }
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: false) {
                highlightedTextView
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            statusBar
        }
    }

    private var highlightedTextView: some View {
        let lines = editorService.content.components(separatedBy: "\n")
        let lineNumberWidth = max(String(lines.count).count, 3)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 0) {
                    // Line number
                    Text(String(format: "%\(lineNumberWidth)d", index + 1))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: CGFloat(lineNumberWidth) * 8 + 8, alignment: .trailing)
                        .padding(.trailing, 8)

                    // Highlighted line content
                    if line.isEmpty {
                        Text(" ")
                            .font(.system(size: 13, design: .monospaced))
                    } else {
                        let highlighted = SyntaxHighlighter.highlight(
                            content: line,
                            language: language,
                            fontSize: 13
                        )
                        Text(AttributedString(highlighted))
                    }
                }
                .background(searchHighlightBackground(line: line, lineIndex: index))
            }
        }
    }

    // MARK: - Search Highlight

    @ViewBuilder
    private func searchHighlightBackground(line: String, lineIndex: Int) -> some View {
        if !searchText.isEmpty && line.localizedCaseInsensitiveContains(searchText) {
            Color.yellow.opacity(0.15)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            Button("Done") {
                showSearch = false
                searchText = ""
            }
            .font(.callout.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text(language.rawValue.uppercased())
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary, in: Capsule())

            if editorService.isReadOnly {
                Label("Read Only", systemImage: "lock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            let lines = editorService.content.components(separatedBy: "\n").count
            Text("\(lines) lines")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if editorService.isDirty {
                Text("Modified")
                    .font(.caption2.bold())
                    .foregroundStyle(.iDev.caution)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 12) {
                Button("Search", systemImage: "magnifyingglass") {
                    showSearch.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)

                if !editorService.isReadOnly {
                    Button {
                        Task { await editorService.saveFile(sftpChannel: sftpChannel) }
                    } label: {
                        if editorService.isSaving {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!editorService.isDirty || editorService.isSaving)
                }
            }
        }
    }
}

// MARK: - Editable Text Editor (for non-read-only mode)

/// A simple editable wrapper that hooks into FileEditorService.
struct EditableFileEditorView: View {
    let filePath: String
    let sftpChannel: SFTPChannel

    @State private var editorService = FileEditorService()
    @State private var showSearch = false
    @State private var searchText = ""

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var fileExtension: String {
        (fileName as NSString).pathExtension
    }

    var body: some View {
        Group {
            if editorService.isLoading {
                ProgressView("Loading \(fileName)...")
            } else if let error = editorService.errorMessage, editorService.content.isEmpty {
                ContentUnavailableView(
                    "Cannot Open File",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                TextEditor(text: $editorService.content)
                    .font(.system(size: 13, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(editorService.isReadOnly)
                    .onChange(of: editorService.content) {
                        editorService.isDirty = true
                    }
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !editorService.isReadOnly {
                    Button {
                        Task { await editorService.saveFile(sftpChannel: sftpChannel) }
                    } label: {
                        if editorService.isSaving {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!editorService.isDirty || editorService.isSaving)
                }
            }
        }
        .task {
            await editorService.loadFile(path: filePath, sftpChannel: sftpChannel)
        }
    }
}
