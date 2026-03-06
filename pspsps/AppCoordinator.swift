import AppKit
import AVFoundation
import Combine
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

    /// Live-bound app configuration. Saving to UserDefaults on every change.
    @Published var config: AppConfig = .current {
        didSet { config.save() }
    }

    let hotkeyManager = HotkeyManager()
    let audioCaptureManager = AudioCaptureManager()
    let textPaster = TextPaster()
    let downloadManager = ModelDownloadManager()
    let transcriptHistory = TranscriptHistory()
    private(set) var pipeline: TranscriptionPipeline

    // Frontmost app captured at recording start so it can be stored with the entry.
    private var capturedSourceApp: String?
    private var capturedSourceAppBundleID: String?

    private let logger = Logger(subsystem: "com.pspsps.pspsps", category: "AppCoordinator")
    private var cancellables: Set<AnyCancellable> = []

    // Track previous values to detect meaningful config changes.
    private var prevASREngine: AppConfig.ASREngineOption
    private var prevPostProcessor: AppConfig.PostProcessorOption
    private var prevHotkeyKeyCode: UInt16
    private var prevHotkeyModifiers: UInt64
    private var prevHotkeyMode: AppConfig.HotkeyMode

    init() {
        let initialConfig = AppConfig.current
        prevASREngine      = initialConfig.asrEngine
        prevPostProcessor  = initialConfig.postProcessor
        prevHotkeyKeyCode  = initialConfig.hotkeyKeyCode
        prevHotkeyModifiers = initialConfig.hotkeyModifiers
        prevHotkeyMode     = initialConfig.hotkeyMode

        pipeline = PipelineFactory.build(from: initialConfig)
        setupCallbacks()
        observeConfigChanges()
        Task { await self.startup() }
    }

    // MARK: - Pipeline Rebuild

    func rebuildPipeline() {
        let oldEngine = pipeline.asrEngine
        pipeline = PipelineFactory.build(from: config)
        oldEngine.unloadModel()
        Task {
            do {
                try await self.pipeline.asrEngine.loadModel()
            } catch {
                self.logger.error("Model reload failed: \(error)")
            }
        }
    }

    // MARK: - Private

    private func observeConfigChanges() {
        $config
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                MainActor.assumeIsolated {
                    self?.handleConfigChange(to: newConfig)
                }
            }
            .store(in: &cancellables)
    }

    private func handleConfigChange(to newConfig: AppConfig) {
        let needsPipelineRebuild =
            newConfig.asrEngine != prevASREngine ||
            newConfig.postProcessor != prevPostProcessor

        let needsHotkeyRestart =
            newConfig.hotkeyKeyCode != prevHotkeyKeyCode ||
            newConfig.hotkeyModifiers != prevHotkeyModifiers ||
            newConfig.hotkeyMode != prevHotkeyMode

        prevASREngine      = newConfig.asrEngine
        prevPostProcessor  = newConfig.postProcessor
        prevHotkeyKeyCode  = newConfig.hotkeyKeyCode
        prevHotkeyModifiers = newConfig.hotkeyModifiers
        prevHotkeyMode     = newConfig.hotkeyMode

        if needsPipelineRebuild {
            rebuildPipeline()
        }
        if needsHotkeyRestart {
            startHotkeyListening()
        }
    }

    private func startup() async {
        do {
            try await pipeline.asrEngine.loadModel()
        } catch {
            logger.error("Model load failed: \(error)")
        }
        startHotkeyListening()
    }

    private func startHotkeyListening() {
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
        let frontmost = NSWorkspace.shared.frontmostApplication
        capturedSourceApp = frontmost?.localizedName
        capturedSourceAppBundleID = frontmost?.bundleIdentifier
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
                    if self.config.keepTranscriptHistory {
                        let entry = TranscriptEntry(
                            text: trimmed,
                            sourceApp: self.capturedSourceApp,
                            sourceAppBundleID: self.capturedSourceAppBundleID
                        )
                        self.transcriptHistory.add(entry: entry)
                    }
                }
            } catch {
                logger.error("Transcription error: \(error)")
            }
            state = .idle
        }
    }
}
