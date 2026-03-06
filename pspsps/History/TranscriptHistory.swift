import Foundation

/// Persists transcript entries to ~/Library/Application Support/pspsps/history.json.
@MainActor
final class TranscriptHistory: ObservableObject {

    @Published private(set) var entries: [TranscriptEntry] = []

    private let fileURL: URL
    private let maxHistoryItemsOverride: Int?

    private var effectiveMaxHistoryItems: Int {
        maxHistoryItemsOverride ?? AppConfig.current.maxHistoryItems
    }

    /// Designated initializer.
    /// - Parameters:
    ///   - fileURL: Override storage location (for tests). Defaults to
    ///              `~/Library/Application Support/pspsps/history.json`.
    ///   - maxHistoryItemsOverride: Cap on number of entries (for tests). Defaults to
    ///                               `AppConfig.current.maxHistoryItems`.
    init(fileURL: URL? = nil, maxHistoryItemsOverride: Int? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = appSupport.appendingPathComponent("pspsps")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("history.json")
        }
        self.maxHistoryItemsOverride = maxHistoryItemsOverride
        load()
    }

    // MARK: - Public API

    /// Prepends a new entry, trimming to `maxHistoryItems` if needed, then saves.
    func add(entry: TranscriptEntry) {
        entries.insert(entry, at: 0)
        let max = effectiveMaxHistoryItems
        if entries.count > max {
            entries = Array(entries.prefix(max))
        }
        save()
    }

    /// Removes the entry with the given id, then saves.
    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Returns entries whose `text` contains `query` (case-insensitive substring match).
    /// Returns all entries when `query` is empty.
    func search(query: String) -> [TranscriptEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    /// Removes all entries and saves.
    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
