import SwiftUI

/// Text editor for local files with syntax highlighting and line numbers.
struct LocalFileEditorView: View {
    let fileURL: URL

    @State private var editorService = FileEditorService()
    @State private var isEditing = false
    @State private var showSearch = false
    @State private var searchText = ""

    private var fileName: String {
        fileURL.lastPathComponent
    }

    private var fileExtension: String {
        fileURL.pathExtension
    }

    private var language: SyntaxHighlighter.Language {
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
            } else if isEditing {
                editModeContent
            } else {
                readModeContent
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .onAppear {
            editorService.loadLocalFile(url: fileURL)
        }
        .overlay(alignment: .top) {
            if showSearch {
                searchBar
            }
        }
    }

    // MARK: - Read Mode (syntax highlighted)

    private var readModeContent: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: false) {
                highlightedTextView
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { statusBar }
    }

    private var highlightedTextView: some View {
        let lines = editorService.content.components(separatedBy: "\n")
        let lineNumberWidth = max(String(lines.count).count, 3)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%\(lineNumberWidth)d", index + 1))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: CGFloat(lineNumberWidth) * 8 + 8, alignment: .trailing)
                        .padding(.trailing, 8)

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
                .background(searchHighlightBackground(line: line))
            }
        }
    }

    // MARK: - Edit Mode

    private var editModeContent: some View {
        TextEditor(text: $editorService.content)
            .font(.system(size: 13, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .disabled(editorService.isReadOnly)
            .onChange(of: editorService.content) {
                editorService.isDirty = true
            }
            .overlay(alignment: .bottom) { statusBar }
    }

    // MARK: - Search

    @ViewBuilder
    private func searchHighlightBackground(line: String) -> some View {
        if !searchText.isEmpty && line.localizedCaseInsensitiveContains(searchText) {
            Color.yellow.opacity(0.15)
        }
    }

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

            Text(isEditing ? "Edit" : "Read")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            let lines = editorService.content.components(separatedBy: "\n").count
            Text("\(lines) lines")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if editorService.isDirty {
                Text("Modified")
                    .font(.caption2.bold())
                    .foregroundStyle(.Roam.caution)
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
                        isEditing.toggle()
                    } label: {
                        Label(
                            isEditing ? "View" : "Edit",
                            systemImage: isEditing ? "eye" : "pencil"
                        )
                    }
                    .keyboardShortcut("e", modifiers: .command)

                    Button {
                        editorService.saveLocalFile()
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
