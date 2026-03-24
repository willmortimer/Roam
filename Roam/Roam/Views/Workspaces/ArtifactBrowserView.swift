import SwiftUI
import SwiftData
import RoamSSH

/// Shows recent build artifacts from the helper's artifact listing.
struct ArtifactBrowserView: View {
    let helperClient: (any HelperClientProtocol)?
    let sftpChannel: SFTPChannel?
    let artifactRoots: [String]
    let workspaceID: String

    @Environment(\.modelContext) private var modelContext
    @Query private var favorites: [FavoriteArtifactRecord]

    @State private var artifacts: [ArtifactDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sinceHours = 24
    @State private var downloadingPath: String?
    @State private var filter: ArtifactFilter = .all

    private var favoritePaths: Set<String> {
        Set(favorites.filter { $0.workspaceReference == workspaceID }.map(\.remotePath))
    }

    private var filteredArtifacts: [ArtifactDTO] {
        switch filter {
        case .all:
            return artifacts
        case .favorites:
            return artifacts.filter { favoritePaths.contains($0.path) }
        }
    }

    var body: some View {
        Group {
            if helperClient == nil {
                ContentUnavailableView(
                    "Helper Required",
                    systemImage: "shippingbox",
                    description: Text("Install the Roam helper on the remote host to browse artifacts.")
                )
            } else if isLoading && artifacts.isEmpty {
                ProgressView("Loading artifacts...")
            } else if artifacts.isEmpty {
                ContentUnavailableView(
                    "No Artifacts",
                    systemImage: "archivebox",
                    description: Text("No recent artifacts found in configured roots.")
                )
            } else {
                artifactList
            }
        }
        .navigationTitle("Artifacts")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Picker("Filter", selection: $filter) {
                    ForEach(ArtifactFilter.allCases) { f in
                        Label(f.label, systemImage: f.icon).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Last 24 hours") { sinceHours = 24; Task { await refresh() } }
                    Button("Last 48 hours") { sinceHours = 48; Task { await refresh() } }
                    Button("Last 7 days") { sinceHours = 168; Task { await refresh() } }
                } label: {
                    Label("Time Range", systemImage: "clock")
                }
            }
        }
        .task {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
    }

    // MARK: - Artifact List

    private var artifactList: some View {
        let favoriteItems = filteredArtifacts.filter { favoritePaths.contains($0.path) }
        let nonFavorites = filteredArtifacts.filter { !favoritePaths.contains($0.path) }
        let grouped = Dictionary(grouping: nonFavorites) { $0.kind }
        let sortedKeys = grouped.keys.sorted()

        return List {
            if !favoriteItems.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteItems, id: \.path) { artifact in
                        ArtifactRow(
                            artifact: artifact,
                            isFavorite: true,
                            isDownloading: downloadingPath == artifact.path,
                            onDownload: { Task { await downloadArtifact(artifact) } },
                            onToggleFavorite: { toggleFavorite(artifact) }
                        )
                    }
                }
            }

            ForEach(sortedKeys, id: \.self) { kind in
                Section(kind.capitalized) {
                    ForEach(grouped[kind] ?? [], id: \.path) { artifact in
                        ArtifactRow(
                            artifact: artifact,
                            isFavorite: false,
                            isDownloading: downloadingPath == artifact.path,
                            onDownload: { Task { await downloadArtifact(artifact) } },
                            onToggleFavorite: { toggleFavorite(artifact) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() async {
        guard let helper = helperClient else { return }
        isLoading = true
        errorMessage = nil

        do {
            artifacts = try await helper.listRecentArtifacts(roots: artifactRoots, sinceHours: sinceHours)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func downloadArtifact(_ artifact: ArtifactDTO) async {
        guard let sftp = sftpChannel else { return }
        downloadingPath = artifact.path

        do {
            var data = Data()
            for try await chunk in sftp.download(remotePath: artifact.path) {
                data.append(chunk)
            }

            let filename = (artifact.path as NSString).lastPathComponent
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: tempURL)
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
        downloadingPath = nil
    }

    private func toggleFavorite(_ artifact: ArtifactDTO) {
        if let existing = favorites.first(where: { $0.remotePath == artifact.path && $0.workspaceReference == workspaceID }) {
            modelContext.delete(existing)
        } else {
            let fav = FavoriteArtifactRecord(
                workspaceReference: workspaceID,
                remotePath: artifact.path,
                kind: artifact.kind
            )
            modelContext.insert(fav)
        }
    }
}

// MARK: - Filter

enum ArtifactFilter: String, CaseIterable, Identifiable {
    case all
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .favorites: "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "star.fill"
        }
    }
}

// MARK: - Artifact Row

private struct ArtifactRow: View {
    let artifact: ArtifactDTO
    let isFavorite: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((artifact.path as NSString).lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formatSize(artifact.size))
                    Text(formatTime(artifact.modified))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                Text(artifact.path)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)

            Button {
                onDownload()
            } label: {
                if isDownloading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                }
            }
            .buttonStyle(.borderless)
            .disabled(isDownloading)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            Button {
                onToggleFavorite()
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
    }

    private func formatSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatTime(_ epoch: UInt64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
