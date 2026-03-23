import SwiftUI

/// Captures and displays log output from server/logs panes with search and error highlighting.
struct LogsLensView: View {
    let helperClient: (any HelperClientProtocol)?
    let tmuxSession: String
    let logPaneIDs: [String]

    @State private var logLines: [LogLine] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var autoRefresh = false
    @State private var refreshTask: Task<Void, Never>?

    private var filteredLines: [LogLine] {
        if searchText.isEmpty {
            return logLines
        }
        return logLines.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if helperClient == nil || logPaneIDs.isEmpty {
                ContentUnavailableView(
                    "No Log Panes",
                    systemImage: "doc.text",
                    description: Text("Assign panes with 'logs' or 'server' roles to use the logs lens.")
                )
            } else if isLoading && logLines.isEmpty {
                ProgressView("Capturing logs...")
            } else if logLines.isEmpty {
                ContentUnavailableView(
                    "No Log Output",
                    systemImage: "doc.text",
                    description: Text("Capture log pane output to see results.")
                )
            } else {
                logContent
            }
        }
        .navigationTitle("Logs")
        .searchable(text: $searchText, prompt: "Filter logs")
        .toolbar {
            if helperClient != nil && !logPaneIDs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Capture", systemImage: "arrow.clockwise") {
                        Task { await captureAll() }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Toggle("Auto-refresh", isOn: $autoRefresh)
                }
            }
        }
        .onChange(of: autoRefresh) { _, enabled in
            if enabled {
                startAutoRefresh()
            } else {
                refreshTask?.cancel()
                refreshTask = nil
            }
        }
        .task { await captureAll() }
    }

    private var logContent: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                    logLineView(line)
                        .id(index)
                        .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
                }
            }
            .listStyle(.plain)
            .onChange(of: logLines.count) {
                if autoRefresh, let last = filteredLines.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func logLineView(_ line: LogLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if line.severity != .normal {
                Image(systemName: line.severity.icon)
                    .font(.caption2)
                    .foregroundStyle(line.severity.color)
                    .frame(width: 14)
            }

            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(line.severity.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func captureAll() async {
        guard let helper = helperClient else { return }
        isLoading = true

        var allLines: [LogLine] = []
        for paneID in logPaneIDs {
            do {
                let content = try await helper.capturePaneContent(session: tmuxSession, paneID: paneID, lines: 500)
                let parsed = parseLogLines(content)
                allLines.append(contentsOf: parsed)
            } catch {
                // Non-fatal
            }
        }

        logLines = allLines
        isLoading = false
    }

    private func startAutoRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await captureAll()
            }
        }
    }

    private func parseLogLines(_ content: String) -> [LogLine] {
        content.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let text = String(line)
            let severity = detectSeverity(text)
            return LogLine(text: text, severity: severity)
        }
    }

    private func detectSeverity(_ text: String) -> LogSeverity {
        let upper = text.uppercased()
        if upper.contains("FATAL") || upper.contains("PANIC") {
            return .fatal
        } else if upper.contains("ERROR") || upper.contains("ERR ") {
            return .error
        } else if upper.contains("WARN") {
            return .warning
        }
        return .normal
    }
}

// MARK: - Log Line Model

private struct LogLine {
    var text: String
    var severity: LogSeverity
}

private enum LogSeverity {
    case normal, warning, error, fatal

    var color: Color {
        switch self {
        case .normal: .primary
        case .warning: .orange
        case .error: .red
        case .fatal: .red
        }
    }

    var icon: String {
        switch self {
        case .normal: "circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        case .fatal: "flame.fill"
        }
    }
}
