import SwiftUI

/// Shows recent clipboard entries from terminal sessions.
/// Tapping an entry copies it back to the system pasteboard.
struct ClipboardHistoryView: View {
    let onPaste: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    private let historyService = ClipboardHistoryService.shared

    init(onPaste: ((String) -> Void)? = nil) {
        self.onPaste = onPaste
    }

    var body: some View {
        NavigationStack {
            Group {
                if historyService.entries.isEmpty {
                    ContentUnavailableView(
                        "No Clipboard History",
                        systemImage: "doc.on.clipboard",
                        description: Text("Text copied from terminal sessions will appear here.")
                    )
                } else {
                    List {
                        ForEach(historyService.entries) { entry in
                            Button {
                                UIPasteboard.general.string = entry.text
                                onPaste?(entry.text)
                                dismiss()
                            } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    historyService.remove(id: entry.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Clipboard History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !historyService.entries.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            historyService.clearAll()
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: ClipboardHistoryService.Entry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(entry.text)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(3)
                .foregroundStyle(.primary)

            HStack(spacing: Spacing.sm) {
                if let host = entry.sourceHost {
                    Text(host)
                        .codeBadge(color: .accentColor)
                }

                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}
