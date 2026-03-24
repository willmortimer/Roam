import SwiftUI

/// Filters terminal output for error patterns and displays them grouped by severity.
struct ErrorsLensView: View {
    let helperClient: (any HelperClientProtocol)?
    let tmuxSession: String
    let paneIDs: [String]

    @State private var errors: [DetectedError] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var severityFilter: ErrorSeverityFilter = .all

    private var filteredErrors: [DetectedError] {
        var result = errors
        if severityFilter != .all {
            result = result.filter { $0.severity == severityFilter.severity }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.line.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        Group {
            if helperClient == nil || paneIDs.isEmpty {
                ContentUnavailableView(
                    "No Panes",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Assign panes to capture error output.")
                )
            } else if isLoading && errors.isEmpty {
                ProgressView("Scanning for errors...")
            } else if errors.isEmpty {
                ContentUnavailableView("No Errors", systemImage: "checkmark.circle", description: Text("No errors detected in captured output."))
            } else {
                errorList
            }
        }
        .navigationTitle("Errors")
        .searchable(text: $searchText, prompt: "Filter errors")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Capture", systemImage: "arrow.clockwise") {
                    Task { await captureAndScan() }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Picker("Severity", selection: $severityFilter) {
                    ForEach(ErrorSeverityFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
            }
        }
        .task { await captureAndScan() }
    }

    private var errorList: some View {
        List {
            Section {
                HStack(spacing: Spacing.lg) {
                    severityCount(label: "Fatal", count: errors.filter { $0.severity == .fatal }.count, color: .Roam.danger)
                    severityCount(label: "Error", count: errors.filter { $0.severity == .error }.count, color: .Roam.caution)
                    severityCount(label: "Warning", count: errors.filter { $0.severity == .warning }.count, color: .yellow)
                }
                .padding(.vertical, Spacing.xs)
                .accessibilityElement(children: .combine)
            }

            Section("Detected Issues (\(filteredErrors.count))") {
                ForEach(Array(filteredErrors.enumerated()), id: \.offset) { _, error in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: 6) {
                            Image(systemName: severityIcon(error.severity))
                                .font(.caption)
                                .foregroundStyle(severityColor(error.severity))
                                .accessibilityHidden(true)
                            Text(error.severity.label)
                                .font(.caption2.bold())
                                .foregroundStyle(severityColor(error.severity))
                            Spacer()
                            Text("L\(error.lineNumber)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Text(error.line)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(3)
                    }
                    .padding(.vertical, Spacing.xxs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(error.severity.label) at line \(error.lineNumber): \(error.line)")
                }
            }
        }
    }

    private func severityCount(label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(count > 0 ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func severityIcon(_ severity: ErrorSeverity) -> String {
        switch severity {
        case .fatal: "flame.fill"
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    private func severityColor(_ severity: ErrorSeverity) -> Color {
        switch severity {
        case .fatal: .Roam.danger
        case .error: .Roam.caution
        case .warning: .yellow
        }
    }

    private func captureAndScan() async {
        guard let helper = helperClient else { return }
        isLoading = true

        var allErrors: [DetectedError] = []
        for paneID in paneIDs {
            do {
                let content = try await helper.capturePaneContent(session: tmuxSession, paneID: paneID, lines: 500)
                let detected = TerminalOutputParser.detectErrors(in: content)
                allErrors.append(contentsOf: detected)
            } catch {
                // Non-fatal
            }
        }
        errors = allErrors
        isLoading = false
    }
}

// MARK: - Severity Filter

private enum ErrorSeverityFilter: String, CaseIterable, Identifiable {
    case all, fatal, error, warning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .fatal: "Fatal"
        case .error: "Errors"
        case .warning: "Warnings"
        }
    }

    var severity: ErrorSeverity? {
        switch self {
        case .all: nil
        case .fatal: .fatal
        case .error: .error
        case .warning: .warning
        }
    }
}
