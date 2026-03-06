import AVFoundation
import CoreGraphics
import OSLog

/// Orchestrates the end-to-end voice-to-text flow.
///
/// State machine:
///   idle → recording  (hotkey .started)
///   recording → transcribing  (hotkey .stopped or max-duration auto-stop)
///   transcribing → idle  (paste complete or any error)
@MainActor
final class AppCoordinator: ObservableObject {

    enum AppState {
        case idle
        case recording
        case transcribing
    }

    @Published private(set) var state: AppState = .idle
    @Published private(set) var lastTranscript: String = ""

    let hotkeyManager = HotkeyManager()
    let audioCaptureManager = AudioCaptureManager()
    let textPaster = TextPaster()
    private(set) var pipeline: TranscriptionPipeline

    private let logger = Logger(subsystem: "com.pspsps.pspsps", category: "AppCoordinator")

    init() {
        pipeline = PipelineFactory.build()
        setupCallbacks()
        Task { await self.startup() }
    }

    // MARK: - Private

    private func startup() async {
        do {
            try await pipeline.asrEngine.loadModel()
        } catch {
            logger.error("Model load failed: \(error)")
        }
        startHotkeyListening()
    }

    private func startHotkeyListening() {
        let config = AppConfig.current
        do {
            try hotkeyManager.startListening(
                keyCode: config.hotkeyKeyCode,
                modifiers: CGEventFlags(rawValue: config.hotkeyModifiers),
                mode: config.hotkeyMode
            )
        } catch {
            logger.error("Hotkey listener failed to start: \(error)")
        }
    }

    private func setupCallbacks() {
        hotkeyManager.onHotkeyEvent = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch event {
                case .started: self.handleHotkeyStarted()
                case .stopped: self.handleHotkeyStopped()
                }
            }
        }

        audioCaptureManager.onAutoStop = { [weak self] buffer in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.runTranscription(buffer: buffer)
            }
        }
    }

    private func handleHotkeyStarted() {
        guard state == .idle else { return }
        do {
            try audioCaptureManager.startCapture()
            state = .recording
        } catch {
            logger.error("Audio capture failed to start: \(error)")
        }
    }

    private func handleHotkeyStopped() {
        guard state == .recording else { return }
        let buffer = audioCaptureManager.stopCapture()
        runTranscription(buffer: buffer)
    }

    private func runTranscription(buffer: AVAudioPCMBuffer) {
        state = .transcribing
        Task {
            do {
                let text = try await pipeline.run(buffer: buffer)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lastTranscript = trimmed
                    textPaster.paste(trimmed)
                }
            } catch {
                logger.error("Transcription error: \(error)")
            }
            state = .idle
        }
    }
}
