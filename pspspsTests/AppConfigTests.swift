import XCTest
@testable import pspsps

final class AppConfigTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppConfigTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEncodeDecodeRoundtrip() throws {
        var config = AppConfig()
        config.asrEngine = .parakeet
        config.whisperKitModel = "custom-whisper"
        config.parakeetModel = "custom-parakeet"
        config.postProcessor = .passthrough
        config.ollamaModel = "llama3:8b"
        config.ollamaHost = "http://192.168.1.10:11434"
        config.audioInputDeviceUID = "test-device-uid"
        config.gainNormalizationEnabled = false
        config.gainTargetDBFS = -15.0
        config.maxRecordingDurationSeconds = 60.0
        config.hotkeyKeyCode = 36
        config.hotkeyModifiers = 0x0001_0000
        config.hotkeyMode = .toggle
        config.showTranscriptInOverlay = false
        config.overlayDurationSeconds = 5.0
        config.soundFeedbackEnabled = false
        config.pasteboardRestoreDelaySeconds = 0.5
        config.keepTranscriptHistory = false
        config.maxHistoryItems = 50

        config.save(to: defaults)
        let loaded = AppConfig.load(from: defaults)

        XCTAssertEqual(loaded.asrEngine, config.asrEngine)
        XCTAssertEqual(loaded.whisperKitModel, config.whisperKitModel)
        XCTAssertEqual(loaded.parakeetModel, config.parakeetModel)
        XCTAssertEqual(loaded.postProcessor, config.postProcessor)
        XCTAssertEqual(loaded.ollamaModel, config.ollamaModel)
        XCTAssertEqual(loaded.ollamaHost, config.ollamaHost)
        XCTAssertEqual(loaded.audioInputDeviceUID, config.audioInputDeviceUID)
        XCTAssertEqual(loaded.gainNormalizationEnabled, config.gainNormalizationEnabled)
        XCTAssertEqual(loaded.gainTargetDBFS, config.gainTargetDBFS)
        XCTAssertEqual(loaded.maxRecordingDurationSeconds, config.maxRecordingDurationSeconds)
        XCTAssertEqual(loaded.hotkeyKeyCode, config.hotkeyKeyCode)
        XCTAssertEqual(loaded.hotkeyModifiers, config.hotkeyModifiers)
        XCTAssertEqual(loaded.hotkeyMode, config.hotkeyMode)
        XCTAssertEqual(loaded.showTranscriptInOverlay, config.showTranscriptInOverlay)
        XCTAssertEqual(loaded.overlayDurationSeconds, config.overlayDurationSeconds)
        XCTAssertEqual(loaded.soundFeedbackEnabled, config.soundFeedbackEnabled)
        XCTAssertEqual(loaded.pasteboardRestoreDelaySeconds, config.pasteboardRestoreDelaySeconds)
        XCTAssertEqual(loaded.keepTranscriptHistory, config.keepTranscriptHistory)
        XCTAssertEqual(loaded.maxHistoryItems, config.maxHistoryItems)
    }

    func testDefaultValues() {
        let config = AppConfig()
        XCTAssertEqual(config.hotkeyKeyCode, 49)
        XCTAssertEqual(config.gainTargetDBFS, -20.0)
        XCTAssertEqual(config.maxRecordingDurationSeconds, 30.0)
        XCTAssertEqual(config.ollamaModel, "qwen3.5:4b")
        XCTAssertEqual(config.asrEngine, .parakeet)
        XCTAssertEqual(config.postProcessor, .passthrough)
        XCTAssertEqual(config.hotkeyMode, .pushToTalk)
    }

    func testDefaultsReturnedWhenNoDataStored() {
        let loaded = AppConfig.load(from: defaults)
        XCTAssertEqual(loaded.hotkeyKeyCode, 49)
        XCTAssertEqual(loaded.ollamaModel, "qwen3.5:4b")
        XCTAssertEqual(loaded.asrEngine, .parakeet)
    }

    func testEnumsAreCaseIterable() {
        XCTAssertEqual(AppConfig.ASREngineOption.allCases.count, 2)
        XCTAssertTrue(AppConfig.ASREngineOption.allCases.contains(.whisperKit))
        XCTAssertTrue(AppConfig.ASREngineOption.allCases.contains(.parakeet))

        XCTAssertEqual(AppConfig.PostProcessorOption.allCases.count, 2)
        XCTAssertTrue(AppConfig.PostProcessorOption.allCases.contains(.ollama))
        XCTAssertTrue(AppConfig.PostProcessorOption.allCases.contains(.passthrough))

        XCTAssertEqual(AppConfig.HotkeyMode.allCases.count, 2)
        XCTAssertTrue(AppConfig.HotkeyMode.allCases.contains(.pushToTalk))
        XCTAssertTrue(AppConfig.HotkeyMode.allCases.contains(.toggle))
    }
}
