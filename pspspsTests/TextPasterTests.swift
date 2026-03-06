import XCTest
@testable import pspsps

@MainActor
final class TextPasterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NSPasteboard.general.clearContents()
    }

    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    // MARK: - Write test

    func testPasteWritesTextToPasteboard() {
        let paster = TextPaster()
        // Use a very long restore delay so the write is still visible when we check.
        paster.paste("hello world", restoreDelay: 60.0)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello world",
            "Pasteboard should contain the pasted text immediately after paste()")
    }

    // MARK: - Restore test

    func testPreviousPasteboardRestoredAfterDelay() async throws {
        let paster = TextPaster()
        let original = "original content"
        NSPasteboard.general.setString(original, forType: .string)

        // Use a short delay; await past it so the asyncAfter callback can fire.
        paster.paste("temporary text", restoreDelay: 0.1)

        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), original,
            "Pasteboard should be restored to original contents after delay")
    }

    // MARK: - Restore delay from AppConfig

    func testRestoreDelayDefaultsToAppConfig() async throws {
        let paster = TextPaster()
        let original = "default delay test"
        NSPasteboard.general.setString(original, forType: .string)

        // nil → uses AppConfig default (0.3s)
        paster.paste("temp", restoreDelay: nil)

        // Wait well past the 0.3s default.
        try await Task.sleep(for: .seconds(1))

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), original,
            "Pasteboard should be restored using the AppConfig default delay")
    }
}
