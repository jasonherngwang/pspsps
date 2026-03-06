# pspsps — Local Voice-to-Text macOS App
## Product Requirements Document

---

## 1. Overview

A native macOS menu bar application for real-time, privacy-first voice dictation. The app captures audio via push-to-talk (PTT), transcribes it locally using on-device ASR, optionally cleans the output with a local LLM, and pastes the result into the active text field. Designed specifically to handle whispered/low-volume speech from professional microphones (e.g. DJI Mic Mini).

The codebase must be **fully modular** — every processing stage (ASR engine, post-processor, audio input) conforms to a Swift protocol, so future models can be swapped with minimal code changes. The app supports two ASR engines: **WhisperKit** and **Parakeet**. Only the user's chosen engine model is downloaded — the other can be fetched later from Settings. On first launch, the user is guided through a brief interactive setup to choose which one to use, and model download is fully managed by the app.

---

## 2. Background & Motivation

Existing tools have critical gaps:

| Tool | Problem |
|---|---|
| **Handy** | Silero VAD gates out whispers before ASR ever runs. Hardcoded ~0.5 threshold. |
| **VoiceInk** | PTT only (no VAD) but no LLM cleanup; raw ASR output only. |
| **WisprFlow** | Cloud-based. Sends audio to AWS/Baseten. ~700ms but no privacy. |
| **SuperWhisper** | Works but closed source; not extensible. |

The root cause of whisper detection failure is always VAD, not the ASR model. This app eliminates VAD entirely (PTT design) and adds RMS gain normalization as a safety net.

---

## 3. Target Platform

- **OS:** macOS 14 Sonoma minimum, macOS 15 preferred
- **Hardware:** Apple Silicon (M1/M2/M3/M4). Intel is not supported — show a clear error on launch if detected (ANE-dependent).
- **RAM budget:** App + models must fit within 4GB active footprint on a 16GB system
- **Language:** Swift 5.9+, no Objective-C unless unavoidable
- **Distribution:** Notarized DMG (required for CGEvent tap / accessibility permissions)
- **Sandboxing:** Disabled (required for CGEvent tap and Accessibility API access)

---

## 4. Core Architecture

### 4.1 Processing Pipeline

```
[PTT Hotkey: CGEvent tap]
         |
[AVAudioEngine — raw PCM capture]
         |
[RMS Gain Normalization — target -20 dBFS]
         |
[ASREngine protocol — transcribe(audio:)]
         |
[PostProcessor protocol — clean(transcript:context:)]  <- optional
         |
[CGEvent Cmd+V paste -> active app]
```

Each stage is independently replaceable. The pipeline does not care what's inside each stage.

### 4.2 Protocol Definitions

These are the contracts everything else is built around. Do not deviate from these interfaces.

```swift
// MARK: - ASR Protocol
protocol ASREngine: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }           // false if model not downloaded
    func loadModel() async throws
    func unloadModel()
    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult
}

struct TranscriptionResult {
    let text: String
    let confidence: Float?                  // nil if model doesn't provide it
    let processingTimeMs: Double
    let language: String?                   // detected language code, if known
}

// MARK: - Post-Processor Protocol
protocol PostProcessor: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    func clean(
        transcript: String,
        context: PostProcessContext
    ) async throws -> String
}

struct PostProcessContext {
    let activeApp: String?                  // "Xcode", "Slack", "Safari"
    let activeAppBundleID: String?
    let previousTranscript: String?         // last N transcripts for continuity
    let timestamp: Date
}

// MARK: - Audio Input Protocol
protocol AudioInputSource: AnyObject {
    var name: String { get }
    var deviceID: AudioDeviceID { get }
    func startCapture() throws              // begins accumulating audio internally
    func stopCapture() -> AVAudioPCMBuffer  // stops and returns the full accumulated buffer
}
```

**Note on `AudioInputSource`:** `AVAudioEngine` capture is callback-based (install a tap, receive buffers asynchronously). The implementation must accumulate buffers internally during the PTT hold and concatenate them into a single `AVAudioPCMBuffer` on `stopCapture()`. The protocol intentionally hides this complexity.

### 4.3 Pipeline Composition

```swift
struct TranscriptionPipeline {
    let asr: ASREngine
    let postProcessor: PostProcessor?

    /// Currently in-flight transcription task, for cancellation.
    private var currentTask: Task<String, Error>?

    /// Cancel any in-flight transcription (e.g. when a new recording starts).
    mutating func cancelIfNeeded() {
        currentTask?.cancel()
        currentTask = nil
    }

    mutating func run(audio: AVAudioPCMBuffer) async throws -> String {
        cancelIfNeeded()

        let task = Task {
            let normalized = AudioProcessor.normalizeRMS(audio, targetDBFS: -20.0)
            let result = try await asr.transcribe(audio: normalized)
            try Task.checkCancellation()
            guard let pp = postProcessor else { return result.text }
            let ctx = PostProcessContext(
                activeApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                activeAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                previousTranscript: TranscriptHistory.shared.last,
                timestamp: Date()
            )
            return try await pp.clean(transcript: result.text, context: ctx)
        }
        currentTask = task
        return try await task.value
    }
}
```

**Cancellation policy:** When a new recording starts while a previous transcription is still in flight, the previous task is cancelled. Only the most recent transcription is pasted.

---

## 5. ASR Engine Implementations

Two engines are supported. Both conform to `ASREngine`. Only the user's chosen model is downloaded — the other can be fetched later from Settings. Both engine **code** paths ship in the binary; only the **model weights** are downloaded on demand.

| | WhisperKit | Parakeet TDT v3 |
|---|---|---|
| Package | argmaxinc/WhisperKit | FluidInference/FluidAudio |
| Model size | ~600MB (compressed) | ~480MB |
| Latency (10s clip) | ~0.45s | ~0.19s |
| Training data | 680K hours (diverse, noisy) | ~65K hours (clean English) |
| Languages | 99+ | English + 25 European |
| Whisper/degraded audio | Excellent | Good, may struggle on edge cases |
| Best for | Whispered speech, accents, noise | Fast feedback, clear speech, long paragraphs |

### 5.1 WhisperKitEngine

- **Package:** `https://github.com/argmaxinc/WhisperKit` via Swift Package Manager
- **Model:** `openai_whisper-large-v3-turbo` (compressed, ~600MB on disk)
- **Model download:** WhisperKit manages its own model downloads internally. `ModelDownloadManager` wraps WhisperKit's download API and exposes progress via `@Published` state. Models are stored in WhisperKit's default cache directory under `~/Library/Application Support/pspsps/models/whisperkit/`.
- **Expected latency:** <500ms for utterances under 15 seconds

```swift
class WhisperKitEngine: ASREngine {
    let name = "WhisperKit (large-v3-turbo)"
    private var whisperKit: WhisperKit?

    var isAvailable: Bool { whisperKit != nil }

    func loadModel() async throws {
        whisperKit = try await WhisperKit(
            model: "openai_whisper-large-v3-turbo",
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )
        )
    }

    func unloadModel() {
        whisperKit = nil
    }

    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        let start = Date()
        guard let wk = whisperKit else { throw ASRError.modelNotLoaded }
        // toFloatArray() is a WhisperKit extension on AVAudioPCMBuffer
        let results = try await wk.transcribe(audioArray: audio.toFloatArray())
        return TranscriptionResult(
            text: results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces),
            confidence: nil,
            processingTimeMs: Date().timeIntervalSince(start) * 1000,
            language: results.first?.language
        )
    }
}
```

### 5.2 ParakeetEngine

- **Package:** `https://github.com/FluidInference/FluidAudio` via SPM
- **Model:** Parakeet TDT 0.6B v3 (CoreML, ~480MB)
- **Model download:** Managed by `ModelDownloadManager`. Stored in `~/Library/Application Support/pspsps/models/parakeet/`
- **Expected latency:** <200ms for utterances under 15 seconds

> **Dependency risk:** FluidAudio (`FluidInference/FluidAudio`) may be pre-release or have an unstable API as of March 2026. Verify the package exists and its API matches the code below before starting Phase 7. If unavailable, implement `ParakeetEngine` as a stub that sets `isAvailable = false` and shows "Coming soon" in the UI. The rest of the app must function with WhisperKit alone.

```swift
class ParakeetEngine: ASREngine {
    let name = "Parakeet TDT v3 (FluidAudio)"
    private var model: FluidAudioModel?

    var isAvailable: Bool { model != nil }

    func loadModel() async throws {
        model = try await FluidAudioModel.load(variant: .parakeetTDT_v3)
    }

    func unloadModel() {
        model = nil
    }

    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        let start = Date()
        guard let m = model else { throw ASRError.modelNotLoaded }
        let text = try await m.transcribe(audio)
        return TranscriptionResult(
            text: text,
            confidence: nil,
            processingTimeMs: Date().timeIntervalSince(start) * 1000,
            language: "en"
        )
    }
}
```

### 5.3 ModelDownloadManager

Responsible for downloading, verifying, and tracking model state. The UI (onboarding + settings) observes this manager's published state.

For **WhisperKit**, use WhisperKit's built-in download API (`WhisperKit.download(variant:)` or equivalent) and hook into its progress callbacks. Do not re-implement model downloading with raw `URLSession` for WhisperKit.

For **Parakeet**, use `URLSession` with progress delegate if FluidAudio does not provide its own download mechanism.

```swift
@MainActor
class ModelDownloadManager: ObservableObject {
    @Published var whisperKitState: ModelState = .notDownloaded
    @Published var parakeetState: ModelState = .notDownloaded

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)  // 0.0 to 1.0
        case downloaded
        case failed(String)                 // error description
    }

    func downloadWhisperKit() async { /* Use WhisperKit download API with progress */ }
    func downloadParakeet() async { /* URLSession with progress delegate */ }
    func isDownloaded(_ engine: ASREngineOption) -> Bool { /* check disk */ }
    func deleteModel(_ engine: ASREngineOption) { /* free disk space */ }
}
```

Model files are validated by checking expected file count and approximate size on disk. If corrupt or incomplete, re-download is triggered automatically.

---

## 6. Post-Processor Implementations

### 6.1 OllamaPostProcessor (Default)

- **Dependency:** Ollama must be running at `http://localhost:11434`
- **Default model:** `qwen3.5:4b` (Q4_K_M quantization, ~2.5GB RAM)
- **Alternative model:** User can type any Ollama model name in settings (e.g. `llama3.2:3b`, `qwen2.5:7b`)
- **Latency:** ~500ms for short transcripts with a 3B model
- **Model name is a config string** — user can type any Ollama model name in settings

**System prompt:**
```
You are a transcription cleanup assistant. The user will give you a raw speech-to-text transcript.
Your job is to:
1. Fix obvious transcription errors (wrong homophones, clearly garbled words)
2. Fix punctuation and capitalization
3. Expand common abbreviations if context is clear
4. Remove filler words (um, uh, like) ONLY if they appear to be accidental
5. Correct technical terms, product names, and proper nouns based on context
6. If the active application is provided, use it to infer the appropriate register (formal for email, casual for Slack, code-aware for Xcode)

Do NOT:
- Rephrase or rewrite content
- Add words the speaker did not say
- Remove intentional repetition or emphasis
- Change the speaker's meaning in any way

Return ONLY the cleaned transcript. No explanations, no preamble.
```

**User message format:**
```
Active app: {context.activeApp ?? "unknown"}
Transcript: {rawTranscript}
```

```swift
class OllamaPostProcessor: PostProcessor {
    let model: String
    let host: String
    var name: String { "Ollama (\(model))" }
    var isAvailable: Bool { /* ping host/api/tags */ }

    init(model: String = "qwen3.5:4b", host: String = "http://localhost:11434") {
        self.model = model
        self.host = host
    }

    func clean(transcript: String, context: PostProcessContext) async throws -> String {
        // POST to {host}/api/chat
        // stream: false
        // parse response.message.content
        // If model not found (404 or error), throw PostProcessError.modelNotAvailable
    }
}
```

### 6.2 PassthroughPostProcessor

Returns raw transcript unchanged. Used when post-processing is disabled or unavailable.

```swift
class PassthroughPostProcessor: PostProcessor {
    let name = "None (raw transcript)"
    var isAvailable: Bool { true }
    func clean(transcript: String, context: PostProcessContext) async throws -> String {
        return transcript
    }
}
```

### 6.3 Future Post-Processors (Out of Scope)

- `LlamaCppPostProcessor` — on-device via llama.cpp Swift bindings (no Ollama required)
- `OpenAIPostProcessor` — cloud fallback (opt-in only, user provides API key)

---

## 7. Audio Processing

### 7.1 Capture Stack

- **Framework:** `AVAudioEngine` (Apple-native, lowest latency)
- **Format:** 16kHz, mono, 32-bit float PCM (required by Whisper/Parakeet)
- **Buffer strategy:** Accumulate frames during PTT hold, release full buffer on key-up
- **Max recording duration:** 30 seconds (configurable). Auto-stop and transcribe if exceeded. This prevents runaway memory accumulation and stays within ASR models' effective range.
- **No VAD.** PTT design eliminates the need for Voice Activity Detection entirely. This is intentional and non-negotiable — VAD is what breaks whisper detection in tools like Handy.

### 7.2 RMS Gain Normalization

Applied to every captured buffer before passing to ASR. Makes whispers acoustically identical to normal speech.

```swift
struct AudioProcessor {
    static func normalizeRMS(
        _ buffer: AVAudioPCMBuffer,
        targetDBFS: Float = -20.0
    ) -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData?[0] else { return buffer }
        let frameCount = Int(buffer.frameLength)

        // Compute RMS
        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            sumOfSquares += channelData[i] * channelData[i]
        }
        let rms = sqrt(sumOfSquares / Float(frameCount))
        guard rms > 1e-8 else { return buffer }  // pure silence, skip

        // Compute gain
        let currentDBFS = 20 * log10(rms)
        let gainDB = targetDBFS - currentDBFS
        let gainLinear = pow(10.0, gainDB / 20.0)
        let clampedGain = min(gainLinear, 20.0)  // cap at +26dB to prevent clipping

        // Apply gain to a new buffer (do not mutate the input)
        let format = buffer.format
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength)!
        output.frameLength = buffer.frameLength
        let outData = output.floatChannelData![0]
        for i in 0..<frameCount {
            outData[i] = channelData[i] * clampedGain
        }
        return output
    }
}
```

### 7.3 Audio Device Selection

- Default to system default input device
- Allow user to select from available input devices in Settings
- Persist selected device by UID (not name), re-validate on launch
- If saved device is unavailable, fall back to system default and notify user

---

## 8. Input Handling

### 8.1 Global Hotkey (CGEvent Tap)

CGEvent tap is the only reliable method for global hotkeys on macOS. Do not use `NSEvent.addGlobalMonitorForEvents` (cannot consume events) or Carbon hotkeys (deprecated).

```swift
class HotkeyManager {
    private var eventTap: CFMachPort?

    func register(keyCode: CGKeyCode, modifiers: CGEventFlags, handler: @escaping (HotkeyEvent) -> Void) {
        // Create CGEvent tap for keyDown + keyUp
        // Must request Accessibility permission first
        // PTT: keyDown -> startRecording, keyUp -> stopRecording + transcribe
        // Toggle: keyDown -> toggleRecording
        //
        // IMPORTANT: The tap callback must return nil for matched hotkey events
        // to consume them and prevent the foreground app from receiving them.
        // For example, Option+Space would otherwise insert a non-breaking space
        // in many text editors.
    }
}
```

**Permission flow:**
1. On first launch, check `AXIsProcessTrusted()`
2. If not trusted, show onboarding sheet: "pspsps needs Accessibility access to detect your hotkey globally"
3. Open System Settings -> Privacy & Security -> Accessibility
4. Poll every 500ms until granted, then proceed

**Default hotkey:** `Option + Space` (configurable)
**Modes:** Push-to-talk (hold) or Toggle (tap to start/stop) — user setting

### 8.2 Text Output

Use CGEvent synthetic keystrokes to paste. More reliable than AppleScript.

```swift
class TextPaster {
    static func paste(_ text: String) {
        // 1. Save current pasteboard contents
        let previousContents = NSPasteboard.general.string(forType: .string)

        // 2. Write transcript to pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // 3. Synthesize Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // 4. Restore previous pasteboard after delay
        //    0.3s is conservative — Electron apps and heavy UIs need time to process Cmd+V.
        //    This is a known race condition; the delay is configurable in AppConfig.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let prev = previousContents {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prev, forType: .string)
            }
        }
    }
}
```

---

## 9. Configuration System

### 9.1 AppConfig

Persisted via **UserDefaults** using `Codable` encoding. Changes in Settings rebuild the pipeline — unload old model, load new model.

```swift
struct AppConfig: Codable {
    // ASR
    var asrEngine: ASREngineOption = .whisperKit
    var whisperKitModel: String = "openai_whisper-large-v3-turbo"
    var parakeetModel: String = "parakeet-tdt-0.6b-v3"

    // Post-processing (use .passthrough to disable)
    var postProcessor: PostProcessorOption = .ollama
    var ollamaModel: String = "qwen3.5:4b"
    var ollamaHost: String = "http://localhost:11434"

    // Audio
    var audioInputDeviceUID: String? = nil  // nil = system default
    var gainNormalizationEnabled: Bool = true
    var gainTargetDBFS: Float = -20.0
    var maxRecordingDurationSeconds: Double = 30.0

    // Hotkey
    var hotkeyKeyCode: UInt16 = 49   // Space
    var hotkeyModifiers: UInt64 = CGEventFlags.maskAlternate.rawValue
    var hotkeyMode: HotkeyMode = .pushToTalk

    // UI
    var showTranscriptInOverlay: Bool = true
    var overlayDurationSeconds: Double = 3.0
    var soundFeedbackEnabled: Bool = true
    var pasteboardRestoreDelaySeconds: Double = 0.3

    // History
    var keepTranscriptHistory: Bool = true
    var maxHistoryItems: Int = 100

    enum ASREngineOption: String, Codable, CaseIterable {
        case whisperKit = "WhisperKit"
        case parakeet   = "Parakeet"
    }

    enum PostProcessorOption: String, Codable, CaseIterable {
        case ollama      = "Ollama"
        case passthrough = "None"       // raw transcript, no LLM cleanup
    }

    enum HotkeyMode: String, Codable {
        case pushToTalk = "Push to Talk"
        case toggle     = "Toggle"
    }
}
```

### 9.2 PipelineFactory

```swift
class PipelineFactory {
    static func build(from config: AppConfig) async throws -> TranscriptionPipeline {
        let asr: ASREngine = switch config.asrEngine {
            case .whisperKit: WhisperKitEngine(model: config.whisperKitModel)
            case .parakeet:   ParakeetEngine(model: config.parakeetModel)
        }

        try await asr.loadModel()

        let pp: PostProcessor = switch config.postProcessor {
            case .ollama:      OllamaPostProcessor(model: config.ollamaModel, host: config.ollamaHost)
            case .passthrough: PassthroughPostProcessor()
        }

        return TranscriptionPipeline(asr: asr, postProcessor: pp)
    }
}
```

---

## 10. First-Launch Engine Picker

On first launch, before any other onboarding step, the user is shown a full-screen engine selection view. This is not skippable — the app cannot function without a downloaded model.

### 10.1 ASRPickerView Design

```
+---------------------------------------------+
|                                             |
|   Choose your transcription engine          |
|                                             |
|  +--------------------------------------+  |
|  |  WhisperKit              Recommended  |  |
|  |  large-v3-turbo  ~600 MB              |  |
|  |  ~0.45s latency                       |  |
|  |  Best for whispers, accents, noise    |  |
|  +--------------------------------------+  |
|                                             |
|  +--------------------------------------+  |
|  |  Parakeet TDT v3                      |  |
|  |  0.6B  ~480 MB                        |  |
|  |  ~0.19s latency                       |  |
|  |  Best for clear speech, speed         |  |
|  +--------------------------------------+  |
|                                             |
|  Not sure? Pick WhisperKit. You can         |
|  switch and download the other later.       |
|                                             |
|          [ Download & Continue ]            |
|                                             |
+---------------------------------------------+
```

- WhisperKit is pre-selected with a "Recommended" badge
- Both cards show: name, model variant, disk size, latency, one-line description
- Single "Download & Continue" button — triggers download for selected engine only
- Progress bar replaces the button during download, with MB/s speed and estimated time
- On completion, automatically advances to next onboarding step (microphone permission)
- The other engine can be downloaded later from Settings -> ASR Engine

### 10.2 Engine Switching (Post-Onboarding)

In Settings -> ASR Engine:
- Currently active engine shown with a checkmark
- Other engine shows "Download (~480 MB)" button if not downloaded, or "Switch" if already downloaded
- Switching engines: unloads current model from memory, loads new one. Takes ~2-3 seconds. Menu bar shows spinner during switch.
- "Delete model" available for downloaded-but-not-active engine to reclaim disk space

---

## 11. UI

### 11.1 Menu Bar

- NSStatusItem with microphone icon
- Icon states:
  - **Idle:** static mic icon (system default color)
  - **Recording:** animated pulse / red tint
  - **Processing:** spinner / activity indicator
  - **Error:** warning badge
- Click opens popover with: last transcript, quick settings toggle, history button
- Right-click opens context menu: Settings, History, Quit

### 11.2 Settings Window

SwiftUI `Settings` scene. Tabs:

**General**
- Hotkey recorder (click to set, press new combo)
- Hotkey mode: Push to Talk / Toggle
- Launch at login toggle
- Sound feedback toggle

**ASR Engine**
- Picker: WhisperKit / Parakeet
- Each option shows: model size, expected latency, brief description
- Download status per engine: "Not downloaded" / progress bar / "Ready" / "Delete (600MB)"
- Download button triggers `ModelDownloadManager` with inline progress bar
- Benchmark button: record 5s test clip, run through both downloaded engines, display latency side-by-side

**Post-Processing**
- Picker: Ollama / None (acts as enable/disable toggle)
- Ollama model name field (free text)
- Ollama host URL field
- Test connection button -> green/red status (also verifies the model name exists via `GET /api/tags`)

**Audio**
- Input device picker (populated from CoreAudio)
- Gain normalization toggle
- Target dBFS slider (-30 to -10, default -20)
- Max recording duration stepper (5-60s, default 30)
- Mic level meter (live VU meter while settings open)

**History**
- Toggle history on/off
- Clear history button
- Max items stepper

### 11.3 Recording Overlay

Small floating window (not in Dock, not in Mission Control) showing recording state:
- "Recording..." during PTT hold
- "Transcribing..." during ASR
- "[first 40 chars of transcript]" briefly after paste
- Dismisses automatically after `overlayDurationSeconds`
- Position: bottom-center of active screen

### 11.4 Transcript History

NSPopover or sheet from menu bar:
- List of past transcripts with timestamp and source app
- Click to re-paste
- Swipe-to-delete
- Search field

---

## 12. Permissions Required

| Permission | Purpose | When Requested |
|---|---|---|
| Accessibility (AXIsProcessTrusted) | Global CGEvent hotkey tap | First launch |
| Microphone (Privacy NSMicrophoneUsageDescription) | Audio capture | First recording attempt |

Both must be granted for the app to function. Show clear onboarding UI for each.

Add to `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>pspsps needs microphone access to transcribe your speech locally on your device.</string>
```

Entitlements file (`pspsps.entitlements`):
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

Sandboxing must be **disabled** (`false`). CGEvent tap does not work in a sandboxed app.

---

## 13. Error Handling

All errors must surface to the user in a non-blocking way (no modal dialogs during recording).

| Error | User-visible behavior |
|---|---|
| Model not loaded | Menu bar warning badge. Notification: "WhisperKit model not found — tap to download" |
| Ollama not running | Fall back to PassthroughPostProcessor silently. Show indicator in menu bar popover. |
| Ollama model not found | Notification: "Ollama model 'X' not found — check Settings". Fall back to Passthrough. |
| Accessibility not granted | Menu bar shows lock icon. Click -> opens onboarding. |
| Microphone permission denied | Notification with "Open System Settings" deeplink. |
| Transcription returned empty | Brief "Nothing detected" toast. Do not paste. |
| Paste failed | Write to clipboard anyway. Show "Copied to clipboard" toast. |
| Audio device disconnected mid-recording | Stop recording, notify user, fall back to system default. |
| Max recording duration exceeded | Auto-stop, transcribe what was captured. Brief "Max duration reached" toast. |
| Intel Mac detected | Show alert: "pspsps requires Apple Silicon (M1 or later)" and quit. |

---

## 14. Performance Requirements

| Metric | Target | Notes |
|---|---|---|
| Hotkey -> recording start | < 50ms | CGEvent tap + AVAudioEngine start |
| ASR latency (10s clip, WhisperKit) | < 700ms | ANE-accelerated |
| ASR latency (10s clip, Parakeet) | < 300ms | FluidAudio CoreML |
| Post-processing latency (Ollama 3B) | < 600ms | Local inference |
| End-to-end (PTT release -> paste) | < 1500ms | WhisperKit + Ollama 3B |
| RAM footprint (idle, model loaded) | < 1.5GB | WhisperKit large-v3-turbo |
| RAM footprint (with Ollama) | < 4GB total | App + WhisperKit + Ollama process |
| CPU during idle | < 0.5% | No polling, event-driven |

---

## 15. Project Structure

```
pspsps/
├── pspsps.xcodeproj
├── pspsps/
│   ├── App/
│   │   ├── pspspsApp.swift                  # @main, AppDelegate
│   │   └── AppConfig.swift                  # Codable config + UserDefaults
│   ├── Core/
│   │   ├── Protocols/
│   │   │   ├── ASREngine.swift
│   │   │   ├── PostProcessor.swift
│   │   │   └── AudioInputSource.swift
│   │   ├── Pipeline/
│   │   │   ├── TranscriptionPipeline.swift
│   │   │   └── PipelineFactory.swift
│   │   └── Models/
│   │       ├── TranscriptionResult.swift
│   │       └── PostProcessContext.swift
│   ├── ASR/
│   │   ├── WhisperKitEngine.swift
│   │   ├── ParakeetEngine.swift
│   │   └── ModelDownloadManager.swift       # download, progress, state for both models
│   ├── PostProcessors/
│   │   ├── OllamaPostProcessor.swift
│   │   └── PassthroughPostProcessor.swift
│   ├── Audio/
│   │   ├── AudioCaptureManager.swift        # AVAudioEngine wrapper (implements AudioInputSource)
│   │   ├── AudioProcessor.swift             # RMS normalization
│   │   └── AudioDeviceManager.swift         # CoreAudio device enumeration
│   ├── Input/
│   │   ├── HotkeyManager.swift              # CGEvent tap
│   │   └── TextPaster.swift                 # CGEvent Cmd+V
│   ├── History/
│   │   ├── TranscriptHistory.swift
│   │   └── TranscriptEntry.swift
│   └── UI/
│       ├── MenuBarController.swift          # NSStatusItem
│       ├── RecordingOverlay.swift           # Floating status window
│       ├── Settings/
│       │   ├── SettingsView.swift
│       │   ├── GeneralSettingsView.swift
│       │   ├── ASRSettingsView.swift
│       │   ├── PostProcessingSettingsView.swift
│       │   └── AudioSettingsView.swift
│       └── Onboarding/
│           ├── OnboardingView.swift
│           ├── ASRPickerView.swift           # engine selection + download during onboarding
│           ├── AccessibilityPermissionView.swift
│           └── MicrophonePermissionView.swift
├── pspspsTests/
│   ├── AudioProcessorTests.swift            # RMS normalization with synthetic buffers
│   ├── AppConfigTests.swift                 # Codable roundtrip
│   ├── PipelineTests.swift                  # Pipeline with mock ASR engine
│   ├── OllamaPostProcessorTests.swift       # HTTP request format, mock responses
│   └── TranscriptHistoryTests.swift         # Persistence roundtrip
└── Package.swift (or via Xcode SPM)
```

---

## 16. Swift Package Dependencies

```swift
dependencies: [
    // ASR — WhisperKit (primary)
    .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),

    // ASR — FluidAudio (Parakeet)
    // NOTE: Verify this package exists and has a stable release before adding.
    // If unavailable, omit and stub ParakeetEngine with isAvailable = false.
    .package(url: "https://github.com/FluidInference/FluidAudio", branch: "main"),

    // No other third-party dependencies required
    // Ollama is a separate process, communicated via HTTP
    // CGEvent, AVAudioEngine, AppKit/SwiftUI are all Apple frameworks
]
```

---

## 17. Build & Distribution

- **Signing:** Developer ID Application certificate (required for notarization)
- **Notarization:** Required. CGEvent tap requires Accessibility entitlement, which triggers notarization review.
- **Hardened runtime:** Enabled, with exception for `com.apple.security.cs.allow-jit` if needed by WhisperKit
- **Distribution:** GitHub Releases as `.dmg` with drag-to-Applications installer
- **Auto-update:** Sparkle framework (optional, add later)

---

## 18. Testing Strategy

All automated tests must use **synthetic audio and mocks** — no real microphone or Accessibility permissions required. This enables fully unattended CI and AI-driven builds.

### 18.1 Test Audio Generation

Use macOS built-in TTS to generate deterministic test audio files:

```bash
# Generate speech audio file
say -o TestFixtures/test_speech.aiff "The quick brown fox jumps over the lazy dog"
# Convert to 16kHz mono WAV (format expected by ASR engines)
afconvert TestFixtures/test_speech.aiff -f WAVE -d LEI16@16000 -c 1 TestFixtures/test_speech.wav
rm TestFixtures/test_speech.aiff
```

This produces a known-content audio file for ASR integration tests without requiring a microphone. Generate this file once during project setup and commit it to the repo.

### 18.2 Synthetic PCM Buffers

For unit tests that don't need real speech (e.g. RMS normalization), create `AVAudioPCMBuffer` programmatically:

```swift
func makeSineBuffer(frequency: Float = 440, amplitude: Float = 0.1, duration: Float = 1.0, sampleRate: Double = 16000) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * Double(duration))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        data[i] = amplitude * sin(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
    }
    return buffer
}
```

### 18.3 Mock ASR Engine

For testing the pipeline without loading a real model:

```swift
class MockASREngine: ASREngine {
    let name = "Mock"
    var isAvailable: Bool { true }
    var mockResult: String = "mock transcript"
    func loadModel() async throws {}
    func unloadModel() {}
    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(text: mockResult, confidence: 1.0, processingTimeMs: 1.0, language: "en")
    }
}
```

---

## 19. Implementation Order

Build in this exact order. Each phase is independently testable before moving on. All acceptance criteria are **automated** — no human interaction required until the final integration test.

### Phase 1 — Xcode Project + Protocols + Core Types
- Create Xcode project with app target and test target
- All protocol definitions: `ASREngine`, `PostProcessor`, `AudioInputSource`
- Data models: `TranscriptionResult`, `PostProcessContext`
- `AppConfig` struct with `Codable` conformance
- `PassthroughPostProcessor` (trivial implementation)
- `MockASREngine` in test target
- **Accept:** `xcodebuild build` succeeds. `AppConfig` encode/decode roundtrip test passes.

### Phase 2 — Audio Capture + Gain Normalization
- `AudioProcessor.normalizeRMS()` — pure function, no hardware needed
- `AudioCaptureManager` wrapping `AVAudioEngine` (implements `AudioInputSource`)
- `AudioDeviceManager` for device enumeration
- Synthetic buffer test helpers (`makeSineBuffer`, `makeSilenceBuffer`)
- **Accept:** Unit tests pass:
  - Sine wave buffer at -40 dBFS normalizes to -20 dBFS (+/- 1dB)
  - Silence buffer (all zeros) returns unchanged
  - Gain clamps at +26dB max (buffer at -50 dBFS does not exceed clamp)
  - Output buffer has correct format and frame count

### Phase 3 — WhisperKit Integration
- Add WhisperKit SPM dependency
- `WhisperKitEngine` conforming to `ASREngine` (with `loadModel`, `unloadModel`, `transcribe`)
- `ModelDownloadManager` (WhisperKit portion only — use WhisperKit's download API)
- Generate `test_speech.wav` via `say` + `afconvert` (commit to repo)
- **Accept:**
  - `xcodebuild build` succeeds with WhisperKit dependency
  - Integration test: load model, transcribe `test_speech.wav`, result contains recognizable words from the known phrase (fuzzy match — TTS audio may not transcribe perfectly)

### Phase 4 — Hotkey + Text Paste
- `HotkeyManager` (CGEvent tap registration, event consumption)
- `TextPaster` (CGEvent Cmd+V with pasteboard save/restore)
- **Accept:**
  - `xcodebuild build` succeeds
  - Unit test: `TextPaster` writes to pasteboard, verifies content, restores previous content after delay
  - (CGEvent tap registration cannot be tested without Accessibility permission — build-only verification)

### Phase 5 — Pipeline + Wiring
- `TranscriptionPipeline` with cancellation support
- `PipelineFactory` builds pipeline from `AppConfig`
- Wire end-to-end: hotkey -> capture -> normalize -> transcribe -> paste
- **Accept:**
  - Unit test: pipeline with `MockASREngine` + `PassthroughPostProcessor` returns expected text
  - Unit test: pipeline cancellation — start task, cancel, verify `CancellationError`
  - Integration test: pipeline with WhisperKit + `test_speech.wav` returns non-empty text

### Phase 6 — Menu Bar UI + Recording Overlay
- `MenuBarController` with `NSStatusItem` and icon state machine
- `RecordingOverlay` floating window (NSPanel, non-activating)
- Basic popover showing last transcript
- **Accept:**
  - `xcodebuild build` succeeds
  - App launches as menu bar app (no Dock icon, status item visible)
  - Manual smoke test: overlay view hierarchy renders in SwiftUI preview

### Phase 7 — Settings + Config Persistence
- `AppConfig` persistence via `UserDefaults`
- Full Settings window with all tabs (General, ASR Engine, Post-Processing, Audio, History)
- `PipelineFactory` rebuilds pipeline on config change (unload old model, load new)
- Hotkey recorder UI
- **Accept:**
  - Unit test: save config to UserDefaults, read back, all fields match
  - `xcodebuild build` succeeds
  - Settings window opens without crash (SwiftUI previews compile)

### Phase 8 — Ollama Post-Processor
- `OllamaPostProcessor` with system prompt and HTTP client
- Connection + model verification in Settings (`GET /api/tags`)
- Graceful fallback: if Ollama unreachable or model not found, switch to `PassthroughPostProcessor` and show indicator
- **Accept:**
  - Unit test: HTTP request body matches expected JSON format (model, messages, stream:false)
  - Unit test: system prompt includes all required instructions
  - Unit test: fallback to Passthrough when HTTP request fails (mock URLProtocol)
  - (Live Ollama test is optional — only if Ollama is running during build)

### Phase 9 — Parakeet + Engine Picker + Model Manager
- Verify FluidAudio package availability. If unavailable: `ParakeetEngine` stub with `isAvailable = false`
- If available: full `ParakeetEngine` implementation via FluidAudio
- `ModelDownloadManager` complete (both engines)
- `ASRPickerView` — shown during onboarding and accessible from ASR settings tab
- Engine switching: unload current, load new
- Benchmark button: run both downloaded engines on `test_speech.wav`, display latency
- **Accept:**
  - `xcodebuild build` succeeds (with real or stubbed Parakeet)
  - Unit test: `ModelDownloadManager` state machine transitions (notDownloaded -> downloading -> downloaded)
  - If FluidAudio available: integration test with `test_speech.wav` returns non-empty text

### Phase 10 — History + Onboarding + Polish
- `TranscriptHistory` persistence (simple JSON file in Application Support)
- `TranscriptEntry` model with timestamp, text, source app
- History panel in menu bar popover (search, re-paste, swipe-to-delete)
- Onboarding flow: engine picker -> accessibility permission -> microphone permission
- All error handling from Section 13
- Intel detection check on launch
- **Accept:**
  - Unit test: save 5 entries to history, reload, entries match
  - Unit test: search filters correctly
  - Unit test: history respects `maxHistoryItems` limit
  - `xcodebuild build` succeeds
  - App launches through onboarding flow without crash

---

## 20. Key Decisions & Rationale (for implementor context)

| Decision | Rationale |
|---|---|
| PTT instead of VAD | VAD is the root cause of whisper detection failure. All VAD systems (Silero, WebRTC, etc.) are trained on normal speech volumes and gate out quiet speech. PTT is more reliable and adds privacy (only records when intentional). |
| RMS normalization over mic gain boost | Mic gain boost clips the signal and affects all apps. RMS normalization is per-buffer, non-destructive, and scoped to this app only. |
| WhisperKit over whisper.cpp | WhisperKit is pure Swift SPM with ANE optimization and compressed models (~600MB vs 1.6GB). No C++ bridging required. Maintained by Argmax who benchmark it against Apple hardware specifically. |
| Ollama over embedded llama.cpp | Ollama runs as a separate process — app memory footprint stays clean. Model management is Ollama's problem. Swapping LLM models is a one-line config change. |
| CGEvent tap over other hotkey methods | Only method that works reliably across all apps including fullscreen games, other Electron apps, and Terminal. Requires Accessibility permission but there is no alternative. |
| CGEvent paste over AppleScript | AppleScript `tell application` paste is unreliable across apps and slow. CGEvent Cmd+V works in every app that accepts keyboard input. |
| Swift over Electron/Tauri | Native memory footprint, ANE access, CoreAudio, CGEvent tap. Tauri/Electron cannot access Accessibility API for global hotkeys. |
| UserDefaults for config | Simple flat `Codable` struct. No need for JSON file management or migration logic. UserDefaults handles atomic writes and is fast for small payloads. |
| Download only selected model | Only the user's chosen ASR model (~500-600MB) is downloaded. Both engine code paths ship in the binary (negligible size). The other model can be fetched later from Settings. |

---

## 21. Out of Scope (v1)

- Speaker diarization (who said what) — future version using SpeakerKit
- Streaming/real-time transcription (word-by-word) — batch PTT only
- Wake word detection ("Hey Dictate")
- Custom vocabulary / domain word lists
- Translation (transcribe in language X, output in language Y)
- iOS/iPadOS version
- Sync across devices
- Cloud ASR fallback

---

## 22. Pre-Flight Checklist (Unattended Build)

Before starting an unattended AI build, ensure:

1. **Xcode CLI tools installed:** `xcode-select --install`
2. **Xcode available:** `xcodebuild -version` returns 15.0+
3. **Internet access:** Required for SPM package resolution and model downloads
4. **Disk space:** ~3GB free (SPM cache + model downloads + build artifacts)
5. **No permissions needed for build/test** — all tests use synthetic audio and mocks
6. **Ollama (optional):** If installed and running with the configured model pulled, Phase 8 can run live integration tests. Not required — mock tests cover the critical paths.

Runtime permissions (Accessibility, Microphone) are only needed when the user launches the finished app for the first time.

---

*Document version: 2.0 — March 2026*
*Built from architecture research session covering Handy VAD root cause analysis, WhisperKit/Parakeet model comparison, Open ASR Leaderboard results (NVIDIA Canary-Qwen #1, Parakeet CTC #23), and modular Swift protocol design.*
