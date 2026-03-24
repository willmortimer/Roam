import Foundation
import Observation

/// Maintains a ring buffer of recent clipboard entries from terminal sessions.
@Observable
final class ClipboardHistoryService {
    static let shared = ClipboardHistoryService()

    struct Entry: Identifiable, Codable {
        let id: UUID
        let text: String
        let sourceHost: String?
        let timestamp: Date

        init(text: String, sourceHost: String? = nil) {
            self.id = UUID()
            self.text = text
            self.sourceHost = sourceHost
            self.timestamp = Date()
        }
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 50
    private let storageKey = "clipboardHistory"

    private init() {
        loadFromDisk()
    }

    /// Record a new clipboard entry.
    func record(text: String, sourceHost: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Deduplicate: if the most recent entry has the same text, skip
        if entries.first?.text == trimmed { return }

        let entry = Entry(text: trimmed, sourceHost: sourceHost)
        entries.insert(entry, at: 0)

        // Trim to max size
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        saveToDisk()
    }

    /// Clear all history.
    func clearAll() {
        entries.removeAll()
        saveToDisk()
    }

    /// Remove a specific entry.
    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        saveToDisk()
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }
}
