import XCTest
@testable import pspsps

@MainActor
final class TranscriptHistoryTests: XCTestCase {

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    // MARK: - Persistence

    func testSaveAndLoadRoundtrip() throws {
        let url = makeTempFileURL()
        let history = TranscriptHistory(fileURL: url)

        let entries = (0..<5).map { i in
            TranscriptEntry(text: "entry \(i)", sourceApp: "TestApp")
        }
        for entry in entries {
            history.add(entry: entry)
        }
        XCTAssertEqual(history.entries.count, 5)

        // Create a new instance from the same file.
        let loaded = TranscriptHistory(fileURL: url)
        XCTAssertEqual(loaded.entries.count, 5)

        // Entries should match (they are prepended, so reverse insertion order).
        let originalTexts = Set(entries.map(\.text))
        let loadedTexts   = Set(loaded.entries.map(\.text))
        XCTAssertEqual(originalTexts, loadedTexts)
    }

    // MARK: - Search

    func testSearchReturnsOnlyMatchingEntries() {
        let url = makeTempFileURL()
        let history = TranscriptHistory(fileURL: url)

        history.add(entry: TranscriptEntry(text: "The quick brown fox"))
        history.add(entry: TranscriptEntry(text: "Hello world"))
        history.add(entry: TranscriptEntry(text: "FOX in all caps"))
        history.add(entry: TranscriptEntry(text: "No match here"))

        let results = history.search(query: "fox")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.text.localizedCaseInsensitiveContains("fox") })
    }

    func testSearchEmptyQueryReturnsAll() {
        let url = makeTempFileURL()
        let history = TranscriptHistory(fileURL: url)

        history.add(entry: TranscriptEntry(text: "one"))
        history.add(entry: TranscriptEntry(text: "two"))

        XCTAssertEqual(history.search(query: "").count, 2)
    }

    // MARK: - Max items trim

    func testAddBeyondMaxDropsOldest() {
        let url = makeTempFileURL()
        let history = TranscriptHistory(fileURL: url, maxHistoryItemsOverride: 3)

        history.add(entry: TranscriptEntry(text: "oldest"))
        history.add(entry: TranscriptEntry(text: "middle"))
        history.add(entry: TranscriptEntry(text: "newest"))
        // Adding a 4th should drop "oldest"
        history.add(entry: TranscriptEntry(text: "extra"))

        XCTAssertEqual(history.entries.count, 3)
        XCTAssertFalse(history.entries.contains(where: { $0.text == "oldest" }),
                       "Oldest entry should have been trimmed")
        XCTAssertTrue(history.entries.contains(where: { $0.text == "extra" }))
    }

    // MARK: - Delete

    func testDeleteRemovesSpecificEntry() {
        let url = makeTempFileURL()
        let history = TranscriptHistory(fileURL: url)

        let a = TranscriptEntry(text: "alpha")
        let b = TranscriptEntry(text: "beta")
        let c = TranscriptEntry(text: "gamma")
        history.add(entry: a)
        history.add(entry: b)
        history.add(entry: c)

        history.delete(id: b.id)

        XCTAssertEqual(history.entries.count, 2)
        XCTAssertFalse(history.entries.contains(where: { $0.id == b.id }))
        XCTAssertTrue(history.entries.contains(where: { $0.id == a.id }))
        XCTAssertTrue(history.entries.contains(where: { $0.id == c.id }))
    }

    // MARK: - Clear

    func testClearRemovesAllEntries() {
        let url = makeTempFileURL()
        let history = TranscriptHistory(fileURL: url)

        history.add(entry: TranscriptEntry(text: "one"))
        history.add(entry: TranscriptEntry(text: "two"))
        history.clear()

        XCTAssertEqual(history.entries.count, 0)

        // Reload from disk — should also be empty.
        let reloaded = TranscriptHistory(fileURL: url)
        XCTAssertEqual(reloaded.entries.count, 0)
    }
}
