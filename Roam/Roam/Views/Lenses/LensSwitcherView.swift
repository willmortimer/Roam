import SwiftUI

/// Container view that manages switching between all structured lenses.
struct LensSwitcherView: View {
    let helperClient: (any HelperClientProtocol)?
    let repoPath: String
    let tmuxSession: String
    let paneIDs: [String]
    let testPaneID: String?
    let logPaneIDs: [String]
    let activeForwards: [ActiveForward]
    let onForwardAndPreview: ((PreviewCandidateDTO) -> Void)?

    @State private var selectedLens: Lens

    init(
        helperClient: (any HelperClientProtocol)?,
        repoPath: String,
        tmuxSession: String,
        paneIDs: [String],
        testPaneID: String?,
        logPaneIDs: [String],
        activeForwards: [ActiveForward],
        onForwardAndPreview: ((PreviewCandidateDTO) -> Void)?,
        initialLens: Lens = .diffs
    ) {
        self.helperClient = helperClient
        self.repoPath = repoPath
        self.tmuxSession = tmuxSession
        self.paneIDs = paneIDs
        self.testPaneID = testPaneID
        self.logPaneIDs = logPaneIDs
        self.activeForwards = activeForwards
        self.onForwardAndPreview = onForwardAndPreview
        _selectedLens = State(initialValue: initialLens)
    }

    var body: some View {
        VStack(spacing: 0) {
            lensContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            lensPicker
        }
        .background {
            // Hidden buttons for hardware keyboard shortcuts
            Group {
                Button("") { selectedLens = .diffs }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("") { selectedLens = .tests }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("") { selectedLens = .logs }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var lensContent: some View {
        switch selectedLens {
        case .diffs:
            NavigationStack {
                DiffLensView(helperClient: helperClient, repoPath: repoPath)
            }
        case .tests:
            NavigationStack {
                TestLensView(helperClient: helperClient, tmuxSession: tmuxSession, testPaneID: testPaneID)
            }
        case .logs:
            NavigationStack {
                LogsLensView(helperClient: helperClient, tmuxSession: tmuxSession, logPaneIDs: logPaneIDs)
            }
        case .ports:
            NavigationStack {
                PortsLensView(
                    helperClient: helperClient,
                    repoPath: repoPath,
                    activeForwards: activeForwards,
                    onForwardAndPreview: onForwardAndPreview
                )
            }
        case .errors:
            NavigationStack {
                ErrorsLensView(helperClient: helperClient, tmuxSession: tmuxSession, paneIDs: paneIDs)
            }
        case .repo:
            NavigationStack {
                RepoActionsView(helperClient: helperClient, repoPath: repoPath)
            }
        }
    }

    // MARK: - Picker

    private var lensPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Lens.allCases) { lens in
                    Button {
                        selectedLens = lens
                    } label: {
                        Label(lens.label, systemImage: lens.icon)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selectedLens == lens ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(selectedLens == lens ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

// MARK: - Lens Enum

enum Lens: String, CaseIterable, Identifiable {
    case diffs
    case tests
    case logs
    case ports
    case errors
    case repo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .diffs: "Diffs"
        case .tests: "Tests"
        case .logs: "Logs"
        case .ports: "Ports"
        case .errors: "Errors"
        case .repo: "Repo"
        }
    }

    var icon: String {
        switch self {
        case .diffs: "plus.forwardslash.minus"
        case .tests: "checkmark.circle"
        case .logs: "doc.text"
        case .ports: "network"
        case .errors: "exclamationmark.triangle"
        case .repo: "arrow.triangle.branch"
        }
    }
}
