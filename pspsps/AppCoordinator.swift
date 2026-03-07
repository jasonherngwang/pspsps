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

    /// Fires with a brief overlay message (non-empty) or empty string to dismiss.
    let showToast = PassthroughSubject<String, Never>()

    /// True when the ASR model failed to load (shows warning badge in menu bar).
    @Published private(set) var modelNotLoaded: Bool = false

    /// True when Accessibility permission has not been granted (shows lock icon in menu bar).
    @Published private(set) var accessibilityNotGranted: Bool = false

    /// Live-bound app configuration. Saving to UserDefaults on every change.
    @Published var config: AppConfig = .current {
        didSet { config.save() }
    }

    let audioService: AudioService
    let shortcutService: ShortcutService
    let textPaster: TextPaster
    let downloadManager: ModelDownloadManager
    let transcriptHistory: TranscriptHistory
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

        self.audioService = AudioService()
        self.shortcutService = ShortcutService()
        self.textPaster = TextPaster()
        self.downloadManager = ModelDownloadManager()
        self.transcriptHistory = TranscriptHistory()
        self.pipeline = PipelineFactory.build(from: initialConfig)

        setupCallbacks()
        observeConfigChanges()
        if NSClassFromString("XCTestCase") == nil {
            Task { await self.startup() }
        }
    }

    // MARK: - Pipeline Rebuild

    func rebuildPipeline() {
        let oldEngine = pipeline.asrEngine
        pipeline = PipelineFactory.build(from: config)
        oldEngine.unloadModel()
        modelNotLoaded = false
        Task {
            do {
                try await self.pipeline.asrEngine.loadModel()
                self.modelNotLoaded = false
            } catch {
                self.logger.error("Model reload failed: \(error)")
                self.modelNotLoaded = true
            }
        }
    }

    // MARK: - Private

    private func observeConfigChanges() {
        $config
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newConfig in
                self?.handleConfigChange(to: newConfig)
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
        audioService.checkMicrophonePermission(onDenied: { [weak self] in
            self?.showToast.send("Microphone access denied — open System Settings")
        })
        do {
            try await pipeline.asrEngine.loadModel()
            modelNotLoaded = false
        } catch {
            logger.error("Model load failed: \(error)")
            modelNotLoaded = true
        }
        startHotkeyListening()
    }

    private func startHotkeyListening() {
        shortcutService.startListening(config: config, onPermissionDenied: { [weak self] in
            self?.accessibilityNotGranted = true
        })
        accessibilityNotGranted = false
    }

    private func setupCallbacks() {
        shortcutService.onHotkeyEvent = { [weak self] event in
            // Dispatch via Task so @MainActor code runs with proper executor context.
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case .started: self.handleHotkeyStarted()
                case .stopped: self.handleHotkeyStopped()
                }
            }
        }

        audioService.onAutoStop = { [weak self] buffer in
            guard let self else { return }
            self.showToast.send("Max duration reached")
            self.runTranscription(buffer: buffer)
        }

        audioService.onDeviceDisconnected = { [weak self] in
            guard let self else { return }
            if self.state == .recording {
                self.showToast.send("Audio device disconnected")
                self.state = .idle
            }
        }
    }

    private var captureTask: Task<Void, Never>?
    private var stopContinuation: CheckedContinuation<Void, Never>?

    private func handleHotkeyStarted() {
        guard state == .idle else { return }
        state = .recording
        let frontmost = NSWorkspace.shared.frontmostApplication
        capturedSourceApp = frontmost?.localizedName
        capturedSourceAppBundleID = frontmost?.bundleIdentifier
        
        captureTask = Task {
            do {
                // Start capture synchronously on a background thread
                try await Task.detached {
                    try self.audioService.startCaptureDirect()
                }.value
                
                // Wait for the user to release the hotkey
                await withCheckedContinuation { continuation in
                    self.stopContinuation = continuation
                }
                
                // Stop capture and transcribe (engine is guaranteed running)
                let buffer = self.audioService.stopCapture()
                self.logger.info("stopCapture returned buffer with \(buffer.frameLength) frames")
                self.runTranscription(buffer: buffer)
            } catch {
                logger.error("Audio capture failed to start: \(error)")
                if let ae = error as? AudioCaptureError, ae == .invalidInputFormat {
                    showToast.send("Invalid audio format")
                } else {
                    showToast.send("Capture error")
                }
                state = .idle
            }
        }
    }

    private func handleHotkeyStopped() {
        guard state == .recording else { return }
        stopContinuation?.resume()
        stopContinuation = nil
    }

    private func runTranscription(buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else {
            state = .idle
            return
        }
        state = .transcribing
        Task {
            do {
                let text = try await pipeline.run(buffer: buffer)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    showToast.send("Nothing detected")
                } else {
                    lastTranscript = trimmed
                    let pasted = textPaster.paste(trimmed)
                    if pasted {
                        showToast.send(String(trimmed.prefix(40)))
                    } else {
                        showToast.send("Copied to clipboard")
                    }
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
                showToast.send("")
            }
            state = .idle
        }
    }

    // MARK: - Sound Feedback

    private func playFeedbackSound(_ name: String) {
        guard config.soundFeedbackEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
