# pspsps Implementation Plan

Reference: `docs/PRD.md`

---

**Issue 1**

Status: COMPLETE

Task: Create Xcode project `pspsps` (you are in the `pspsps` directory already) with a macOS app target (menu bar app, no main window) and a `pspspsTests` unit test target. Add WhisperKit SPM dependency (`https://github.com/argmaxinc/WhisperKit`, from `0.9.0`). Attempt to resolve FluidAudio (`https://github.com/FluidInference/FluidAudio`, branch `main`) — add if it resolves, skip and note in progress.txt if it does not. Configure: entitlements per PRD Section 12 (sandbox disabled, audio input enabled), Info.plist (NSMicrophoneUsageDescription, LSUIElement = true for menu bar app), deployment target macOS 14.0, Swift language version. Create a minimal `pspspsApp.swift` `@main` entry point that compiles.

Acceptance criteria:
- [x] `xcodebuild -scheme pspsps -destination 'platform=macOS' build` succeeds
- [x] Test target compiles: `xcodebuild -scheme pspsps -destination 'platform=macOS' build-for-testing` succeeds
- [x] App is configured as LSUIElement (no Dock icon)
- [x] Entitlements file disables sandbox and enables audio input
- [x] Info.plist contains NSMicrophoneUsageDescription
- [x] WhisperKit SPM dependency resolves successfully
- [x] FluidAudio status (available or unavailable) noted in progress.txt


**Issue 2**

Status: COMPLETE

Task: Create all protocol definitions and data models per PRD Sections 4.2 and 4.3. Files: `Core/Protocols/ASREngine.swift`, `Core/Protocols/PostProcessor.swift`, `Core/Protocols/AudioInputSource.swift`, `Core/Models/TranscriptionResult.swift`, `Core/Models/PostProcessContext.swift`. Create error types `ASRError` and `PostProcessError` (model not loaded, engine unavailable, transcription failed, post-processing failed). Create `PostProcessors/PassthroughPostProcessor.swift`. In the test target, create `Mocks/MockASREngine.swift` with configurable mock result.

Acceptance criteria:
- [x] `xcodebuild build` succeeds
- [x] ASREngine protocol has: name, isAvailable, loadModel() async throws, unloadModel(), transcribe(audio:) async throws -> TranscriptionResult
- [x] PostProcessor protocol has: name, isAvailable, clean(transcript:context:) async throws -> String
- [x] AudioInputSource protocol has: name, deviceID, startCapture() throws, stopCapture() -> AVAudioPCMBuffer
- [x] PassthroughPostProcessor.clean() returns input text unchanged
- [x] MockASREngine.transcribe() returns its configured mockResult string


**Issue 3**

Status: COMPLETE

Task: Implement `AppConfig` struct per PRD Section 9.1 with all fields and nested enums (`ASREngineOption`, `PostProcessorOption`, `HotkeyMode`). Implement UserDefaults persistence — encode entire struct as JSON data, store under a single key, decode on read. Provide a `static var current` accessor that loads from UserDefaults (or returns defaults). Write unit tests for encode/decode roundtrip.

Acceptance criteria:
- [x] `xcodebuild test` passes: AppConfig with non-default values encodes to UserDefaults and decodes back with all fields matching
- [x] All default values match PRD Section 9.1 (e.g. hotkeyKeyCode = 49, gainTargetDBFS = -20, maxRecordingDurationSeconds = 30, ollamaModel = "qwen3.5:4b")
- [x] All three enums are Codable and CaseIterable
- [x] `xcodebuild build` succeeds


**Issue 4**

Status: COMPLETE

Task: Implement `Audio/AudioProcessor.swift` with `normalizeRMS(_:targetDBFS:)` per PRD Section 7.2. Allocate a new output buffer manually (do NOT use `.copy()` — AVAudioPCMBuffer does not conform to NSCopying). In the test target, create `Helpers/SyntheticAudio.swift` with `makeSineBuffer(frequency:amplitude:duration:sampleRate:)` and `makeSilenceBuffer(duration:sampleRate:)` per PRD Section 18.2. Write unit tests.

Acceptance criteria:
- [x] `xcodebuild test` passes: sine buffer at -40 dBFS normalizes to -20 dBFS (within +/- 1 dB)
- [x] `xcodebuild test` passes: silence buffer (all zeros) returns buffer unchanged (no NaN, no crash)
- [x] `xcodebuild test` passes: gain clamps at +26 dB max (buffer at -50 dBFS does not exceed clamp)
- [x] `xcodebuild test` passes: output buffer has same format and frame count as input
- [x] Output buffer is a new allocation, not a reference to the input buffer


**Issue 5**

Status: COMPLETE

Task: Implement `Audio/AudioCaptureManager.swift` wrapping AVAudioEngine, conforming to `AudioInputSource`. On `startCapture()`, start the engine and install a tap on the input node — accumulate buffers internally in an array. On `stopCapture()`, remove the tap, stop the engine, concatenate all accumulated buffers into a single `AVAudioPCMBuffer`, and return it. Output format: 16kHz mono Float32. Implement max recording duration per PRD Section 7.1 — schedule a timer that auto-calls `stopCapture()` after `AppConfig.maxRecordingDurationSeconds`. Implement `Audio/AudioDeviceManager.swift` for CoreAudio device enumeration (list available input devices, select by UID, fall back to system default).

Acceptance criteria:
- [x] `xcodebuild build` succeeds
- [x] AudioCaptureManager conforms to AudioInputSource protocol
- [x] Capture format is 16kHz, mono, 32-bit float
- [x] Max duration timer exists and triggers auto-stop
- [x] AudioDeviceManager can enumerate system input devices (returns array of device info)
- [x] AudioDeviceManager falls back to system default when saved UID not found


**Issue 6**

Status: COMPLETE

Task: Implement `ASR/WhisperKitEngine.swift` conforming to `ASREngine` per PRD Section 5.1. Use WhisperKit's built-in model management — `loadModel()` calls WhisperKit init which downloads if needed. `unloadModel()` nils the reference. `transcribe()` uses `wk.transcribe(audioArray:)` — note that `toFloatArray()` is a WhisperKit extension on AVAudioPCMBuffer. Implement `ASR/ModelDownloadManager.swift` as `@MainActor ObservableObject` per PRD Section 5.3 — track `ModelState` enum (notDownloaded, downloading(progress), downloaded, failed). For WhisperKit, wrap its download API to expose progress. No separate `whisperKitProgress` property — progress lives inside the enum case.

Acceptance criteria:
- [x] `xcodebuild build` succeeds
- [x] WhisperKitEngine conforms to ASREngine with all required methods
- [x] unloadModel() sets internal WhisperKit reference to nil
- [x] ModelDownloadManager is @MainActor and ObservableObject
- [x] ModelDownloadManager.ModelState enum has exactly: notDownloaded, downloading(progress: Double), downloaded, failed(String)
- [x] No redundant progress properties outside the enum


**Issue 7**

Status: COMPLETE

Task: Generate a test audio fixture using macOS TTS per PRD Section 18.1. Run: `say -o <path>/test_speech.aiff "The quick brown fox jumps over the lazy dog"` then `afconvert <path>/test_speech.aiff -f WAVE -d LEI16@16000 -c 1 <path>/test_speech.wav` and remove the .aiff. Place the .wav in a `TestFixtures/` directory accessible to the test target. Write an integration test that loads the WhisperKit model and transcribes the test audio. The first run will download the model (~600 MB) — use a generous test timeout (300+ seconds).

Acceptance criteria:
- [x] `TestFixtures/test_speech.wav` exists, is 16kHz mono WAV
- [x] Integration test: WhisperKit model loads without error
- [x] Integration test: transcription of test_speech.wav returns non-empty string
- [x] Integration test: transcription result contains at least 3 recognizable words from the input phrase (case-insensitive fuzzy match)


**Issue 8**

Status: COMPLETE

Task: Implement `Input/HotkeyManager.swift` per PRD Section 8.1. Register a CGEvent tap for keyDown + keyUp events. Match against configured keyCode and modifiers. Consume matched events by returning nil from the tap callback (prevent foreground app from receiving the hotkey). Support two modes: push-to-talk (keyDown = start, keyUp = stop) and toggle (keyDown = toggle). Check `AXIsProcessTrusted()` before attempting registration — expose a method to check permission status. Expose a callback/closure `onHotkeyEvent: (HotkeyEvent) -> Void` where HotkeyEvent is `.started` or `.stopped`.

Acceptance criteria:
- [x] `xcodebuild build` succeeds
- [x] HotkeyManager compiles with CGEvent tap setup
- [x] Tap callback returns nil for matched events (consumes them)
- [x] Both PTT and Toggle modes are implemented
- [x] AXIsProcessTrusted() is checked before tap creation
- [x] HotkeyEvent enum has .started and .stopped cases


**Issue 9**

Status: COMPLETE

Task: Implement `Input/TextPaster.swift` per PRD Section 8.2. Save current pasteboard string, write new text, synthesize Cmd+V via CGEvent (virtual key 0x09 with .maskCommand), restore previous pasteboard after configurable delay (`AppConfig.pasteboardRestoreDelaySeconds`, default 0.3s). Write unit test verifying pasteboard write and restore behavior.

Acceptance criteria:
- [x] `xcodebuild build` succeeds
- [x] `xcodebuild test` passes: text written to pasteboard matches input
- [x] `xcodebuild test` passes: previous pasteboard contents restored after delay
- [x] Restore delay reads from AppConfig (default 0.3s)
- [x] CGEvent Cmd+V uses correct virtual key code (0x09) and maskCommand flag


**Issue 10**

Status: READY

Task: Implement `Core/Pipeline/TranscriptionPipeline.swift` per PRD Section 4.3 with cancellation support — hold a reference to the current `Task`, cancel it when a new `run()` starts. Apply `AudioProcessor.normalizeRMS()` before transcription. Implement `Core/Pipeline/PipelineFactory.swift` per PRD Section 9.2 — build pipeline from `AppConfig`, instantiating the correct ASREngine and PostProcessor. Write unit tests using MockASREngine and PassthroughPostProcessor.

Acceptance criteria:
- [ ] `xcodebuild test` passes: pipeline with MockASREngine + PassthroughPostProcessor returns expected text
- [ ] `xcodebuild test` passes: calling run() cancels any in-flight previous task
- [ ] `xcodebuild test` passes: PipelineFactory builds WhisperKitEngine when config.asrEngine == .whisperKit
- [ ] `xcodebuild test` passes: PipelineFactory builds PassthroughPostProcessor when config.postProcessor == .passthrough
- [ ] Pipeline calls AudioProcessor.normalizeRMS() before ASREngine.transcribe()


**Issue 11**

Status: BLOCKED by Issue 10

Task: Wire the complete end-to-end flow in an app coordinator / controller class. On hotkey start → `AudioCaptureManager.startCapture()`. On hotkey stop → `stopCapture()` → `pipeline.run(buffer)` → `TextPaster.paste(result)`. Implement a state machine: `idle → recording → transcribing → idle`. Catch all pipeline errors (log them, do not crash). Connect to the app entry point so the flow is active at launch (with a loaded model).

Acceptance criteria:
- [ ] `xcodebuild build` succeeds
- [ ] State machine has three states: idle, recording, transcribing
- [ ] Transitions: idle → recording (hotkey start), recording → transcribing (hotkey stop), transcribing → idle (paste complete or error)
- [ ] Pipeline errors are caught and logged, not thrown to caller
- [ ] App coordinator holds references to HotkeyManager, AudioCaptureManager, TranscriptionPipeline, TextPaster


**Issue 12**

Status: BLOCKED by Issue 11

Task: Implement `UI/MenuBarController.swift` per PRD Section 11.1. Create NSStatusItem with a microphone SF Symbol icon. Icon state machine synced to the app coordinator's state: idle (default color), recording (red tint or highlighted), processing/transcribing (activity indicator or alternate icon), error (warning badge overlay). Left-click opens a popover (placeholder for now). Right-click context menu with: Settings (opens Settings window), History (placeholder), Quit (NSApp.terminate). Remove any main window — app is menu-bar-only.

Acceptance criteria:
- [ ] `xcodebuild build` succeeds
- [ ] App launches with no main window, only a menu bar status item
- [ ] Status item icon changes based on state (idle, recording, processing, error)
- [ ] Right-click context menu has Settings, History, and Quit items
- [ ] Quit menu item terminates the app


**Issue 13**

Status: BLOCKED by Issue 12

Task: Implement `UI/RecordingOverlay.swift` per PRD Section 11.3 as a floating NSPanel — `styleMask: [.nonactivatingPanel]`, `level: .floating`, `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]` (not in Dock, not in Mission Control). Show "Recording..." during PTT hold, "Transcribing..." during ASR, truncated result (first 40 chars) after paste. Auto-dismiss after `AppConfig.overlayDurationSeconds`. Position at bottom-center of active screen. Also implement the menu bar left-click popover showing the last transcript text and a "Copy" button to re-paste.

Acceptance criteria:
- [ ] `xcodebuild build` succeeds
- [ ] Overlay is a non-activating floating panel (does not steal focus)
- [ ] Overlay displays correct text per state (recording, transcribing, result)
- [ ] Overlay auto-dismisses after configured duration
- [ ] Overlay positioned at bottom-center of screen
- [ ] Menu bar popover shows last transcript text


**Issue 14**

Status: BLOCKED by Issue 12

Task: Implement `UI/Settings/SettingsView.swift` and all tab views per PRD Section 11.2 as a SwiftUI Settings scene. General tab: hotkey recorder (click-to-record new combo), hotkey mode picker (PTT/Toggle), launch at login toggle (via SMAppService), sound feedback toggle. ASR Engine tab: engine picker with download status per engine from ModelDownloadManager, download/delete buttons with progress bar. Post-Processing tab: Ollama/None picker, model name text field, host URL field, test connection button (stub action for now). Audio tab: input device picker from AudioDeviceManager, gain normalization toggle, target dBFS slider (-30 to -10), max recording duration stepper (5-60s), live mic level meter. History tab: on/off toggle, clear button, max items stepper. All values bind to AppConfig and persist. ASR engine or post-processor change triggers pipeline rebuild.

Acceptance criteria:
- [ ] `xcodebuild build` succeeds
- [ ] Settings window opens from menu bar context menu
- [ ] All five tabs render without crash
- [ ] Config changes write to UserDefaults immediately
- [ ] Changing ASR engine triggers model unload + reload


**Issue 15**

Status: BLOCKED by Issue 10

Task: Implement `PostProcessors/OllamaPostProcessor.swift` per PRD Section 6.1. HTTP POST to `{host}/api/chat` with `stream: false`, system prompt (all 6 cleanup rules + all 4 "Do NOT" rules from PRD), and user message format `"Active app: {app}\nTranscript: {text}"`. Parse `response.message.content`. Implement `isAvailable` check via `GET {host}/api/tags` — also verify the configured model name exists in the tags list. On any failure (connection refused, model not found, timeout), fall back to `PassthroughPostProcessor` and log the reason. Write unit tests using a mock `URLProtocol` subclass to intercept HTTP requests.

Acceptance criteria:
- [ ] `xcodebuild test` passes: request body JSON has correct structure (model, messages array with system + user, stream: false)
- [ ] `xcodebuild test` passes: system prompt text contains all required cleanup rules from PRD Section 6.1
- [ ] `xcodebuild test` passes: successful mock response parses message.content correctly
- [ ] `xcodebuild test` passes: connection failure returns raw transcript (fallback behavior)
- [ ] `xcodebuild test` passes: model-not-found response returns raw transcript (fallback behavior)
- [ ] isAvailable checks both host reachability and model existence


**Issue 16**

Status: READY

Task: Implement `ASR/ParakeetEngine.swift`. If FluidAudio SPM resolved in Issue 1: implement full engine per PRD Section 5.2 — `loadModel()` via `FluidAudioModel.load(variant:)`, `unloadModel()` nils the reference, `transcribe()` returns result with language "en". If FluidAudio did NOT resolve: implement a stub where `isAvailable` returns false, `loadModel()` throws `ASRError.engineUnavailable` with message "Parakeet engine not yet available", and `transcribe()` throws the same error. Add Parakeet state tracking to ModelDownloadManager (parakeetState property).

Acceptance criteria:
- [ ] `xcodebuild build` succeeds
- [ ] ParakeetEngine conforms to ASREngine protocol
- [ ] If FluidAudio available: loadModel and transcribe compile against real API
- [ ] If FluidAudio unavailable: isAvailable returns false, loadModel throws descriptive error
- [ ] ModelDownloadManager has parakeetState: ModelState property
- [ ] unloadModel() sets internal model reference to nil


**Issue 17**

Status: BLOCKED by Issue 16

Task: Implement `UI/Onboarding/ASRPickerView.swift` per PRD Section 10.1. Two engine cards: WhisperKit (pre-selected, "Recommended" badge, "~600 MB", "~0.45s latency", "Best for whispers, accents, noise") and Parakeet ("~480 MB", "~0.19s latency", "Best for clear speech, speed"). If Parakeet is unavailable (stub), show its card as disabled/grayed with "Coming soon". Single "Download & Continue" button triggers ModelDownloadManager download for the selected engine. Progress bar replaces button during download. Implement engine switching in ASR Settings tab: "Switch" button if already downloaded, unloads current model and loads new one. Menu bar spinner during switch.

Acceptance criteria:
- [ ] `xcodebuild build` succeeds
- [ ] ASRPickerView shows two engine cards with correct metadata
- [ ] WhisperKit card has "Recommended" badge and is pre-selected
- [ ] If Parakeet unavailable: card is disabled with "Coming soon" label
- [ ] Download button triggers ModelDownloadManager and shows progress
- [ ] Engine switch calls unloadModel() on current, loadModel() on new


**Issue 18**

Status: READY

Task: Implement `History/TranscriptEntry.swift` (Codable struct: id UUID, text, timestamp Date, sourceApp String?, sourceAppBundleID String?) and `History/TranscriptHistory.swift` (persist as JSON array to `~/Library/Application Support/pspsps/history.json`). Provide: `add(entry:)` (prepend, trim to maxHistoryItems), `delete(id:)`, `search(query:) -> [TranscriptEntry]` (case-insensitive substring match on text), `clear()`, `var entries: [TranscriptEntry]`. Create Application Support directory if needed. Load on init, save after mutations. Implement history UI as NSPopover content from menu bar: list with timestamp + preview, click to re-paste via TextPaster, swipe-to-delete, search field. Wire "History" menu item to show this popover. Write unit tests.

Acceptance criteria:
- [ ] `xcodebuild test` passes: save 5 entries, create new instance, loaded entries match originals
- [ ] `xcodebuild test` passes: search("fox") returns only entries containing "fox" (case-insensitive)
- [ ] `xcodebuild test` passes: adding entries beyond maxHistoryItems drops oldest
- [ ] `xcodebuild test` passes: delete(id:) removes specific entry
- [ ] History popover renders entry list without crash
- [ ] Click on entry calls TextPaster.paste() with entry text


**Issue 19**

Status: BLOCKED by Issue 17

Task: Implement full onboarding flow per PRD Section 10: `UI/Onboarding/OnboardingView.swift` orchestrates three steps. Step 1: ASRPickerView (from Issue 17) — must complete download before advancing. Step 2: `AccessibilityPermissionView.swift` — explain why Accessibility is needed, button to open System Settings (`Privacy & Security > Accessibility`), poll `AXIsProcessTrusted()` every 500ms, auto-advance when granted. Step 3: `MicrophonePermissionView.swift` — request microphone permission via `AVCaptureDevice.requestAccess(for: .audio)`, advance on grant. Store `hasCompletedOnboarding` in UserDefaults. Show onboarding on first launch only. On subsequent launches, skip directly to menu bar.

Acceptance criteria:
- [ ] `xcodebuild build` succeeds
- [ ] Onboarding appears when hasCompletedOnboarding is false
- [ ] Onboarding is skipped when hasCompletedOnboarding is true
- [ ] Step 1 blocks advancement until model download completes
- [ ] Step 2 polls AXIsProcessTrusted() on a timer and auto-advances
- [ ] Step 3 requests microphone access and advances on grant
- [ ] hasCompletedOnboarding set to true after final step


**Issue 20**

Status: BLOCKED by Issue 19

Task: Implement all remaining error handling from PRD Section 13. Intel architecture check on launch: if `ProcessInfo.processInfo.processorArchitecture` is not arm64 (check `#if !arch(arm64)`), show alert "pspsps requires Apple Silicon (M1 or later)" and call `NSApp.terminate(nil)`. Empty transcription: show "Nothing detected" overlay toast, do not call TextPaster. Paste failure: write to clipboard, show "Copied to clipboard" toast. Audio device disconnect: stop recording, notify via overlay, fall back to system default. Model not loaded: menu bar warning badge, notification with download action. Accessibility not granted: menu bar lock icon, click opens onboarding. Microphone denied: notification with System Settings deeplink. Max duration exceeded: auto-stop with "Max duration reached" toast. Ollama model not found: notification, fall back to Passthrough. Add sound feedback: play system sounds on recording start/stop when `AppConfig.soundFeedbackEnabled` is true. Run full test suite to verify no regressions.

Acceptance criteria:
- [ ] `xcodebuild build` succeeds with zero errors
- [ ] `xcodebuild test` passes all existing unit and integration tests
- [ ] Intel check: `#if !arch(arm64)` block shows alert and terminates
- [ ] Empty transcription does not trigger paste
- [ ] Ollama failure falls back to Passthrough (does not block transcription)
- [ ] Sound feedback plays on recording start/stop when enabled
- [ ] All error states surface via overlay toast or menu bar badge (no modal dialogs during recording)
