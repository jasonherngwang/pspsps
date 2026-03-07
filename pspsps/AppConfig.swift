import Foundation

struct AppConfig: Codable, Sendable, Equatable {

    // MARK: - ASR
    var asrEngine: ASREngineOption = .parakeet
    var whisperKitModel: String = "openai_whisper-large-v3-turbo"
    var parakeetModel: String = "parakeet-tdt-0.6b-v3"

    // MARK: - Post-processing
    var postProcessor: PostProcessorOption = .passthrough
    var ollamaModel: String = "qwen3.5:4b"
    var ollamaHost: String = "http://localhost:11434"

    // MARK: - Audio
    var audioInputDeviceUID: String? = nil
    var gainNormalizationEnabled: Bool = true
    var gainTargetDBFS: Float = -20.0
    var maxRecordingDurationSeconds: Double = 30.0

    // MARK: - Hotkey
    var hotkeyKeyCode: UInt16 = 49          // Space
    var hotkeyModifiers: UInt64 = 0x0008_0000  // CGEventFlags.maskAlternate
    var hotkeyMode: HotkeyMode = .pushToTalk

    // MARK: - UI
    var showTranscriptInOverlay: Bool = true
    var overlayDurationSeconds: Double = 3.0
    var soundFeedbackEnabled: Bool = true
    var pasteboardRestoreDelaySeconds: Double = 0.3

    // MARK: - History
    var keepTranscriptHistory: Bool = true
    var maxHistoryItems: Int = 100

    // MARK: - Enums

    enum ASREngineOption: String, Codable, CaseIterable, Sendable {
        case whisperKit = "WhisperKit"
        case parakeet   = "Parakeet"
    }

    enum PostProcessorOption: String, Codable, CaseIterable, Sendable {
        case ollama      = "Ollama"
        case passthrough = "None"
    }

    enum HotkeyMode: String, Codable, CaseIterable, Sendable {
        case pushToTalk = "Push to Talk"
        case toggle     = "Toggle"
    }

    // MARK: - Persistence

    static let defaultsKey = "AppConfig"

    static var current: AppConfig {
        load(from: .standard)
    }

    static func load(from defaults: UserDefaults = .standard) -> AppConfig {
        guard let data = defaults.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppConfig.defaultsKey)
    }
}
