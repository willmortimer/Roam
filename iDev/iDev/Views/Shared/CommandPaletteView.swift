import SwiftUI

/// Full-screen command palette triggered by Cmd+K or Cmd+Shift+P.
struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var provider: any CommandPaletteActionProvider
    var context: PaletteContext

    private var filteredActions: [PaletteAction] {
        let all = provider.actions(context: context)
        guard !query.isEmpty else { return all }
        return all
            .compactMap { action -> (PaletteAction, Int)? in
                let titleScore = FuzzyMatcher.score(query: query, target: action.title)
                let subtitleScore = action.subtitle.flatMap { FuzzyMatcher.score(query: query, target: $0) }
                let best = [titleScore, subtitleScore].compactMap { $0 }.max()
                guard let score = best else { return nil }
                return (action, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                actionList
            }
            .background(Color.iDev.codeBackground)
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { isSearchFocused = true }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tint)
                .font(.callout)
            TextField("Type a command...", text: $query)
                .focused($isSearchFocused)
                .textFieldStyle(.plain)
                .font(.mono(.body))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    if let first = filteredActions.first {
                        first.action()
                        dismiss()
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - Action List

    private var actionList: some View {
        List {
            ForEach(filteredActions) { action in
                Button {
                    action.action()
                    dismiss()
                } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: action.icon)
                            .frame(width: 28)
                            .foregroundStyle(.tint)
                            .font(.callout)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(action.title)
                                .font(.subheadline)
                            if let subtitle = action.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let shortcut = action.shortcut {
                            Text(shortcut)
                                .font(.monoBold(.caption2))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.iDev.codeBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(.quaternary, lineWidth: 0.5)
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }

            if filteredActions.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
