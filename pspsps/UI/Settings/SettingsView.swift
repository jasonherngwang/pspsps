import AVFoundation
import AppKit
import Combine
import ServiceManagement
import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ASREngineSettingsTab()
                .tabItem { Label("ASR Engine", systemImage: "waveform") }
            PostProcessingSettingsTab()
                .tabItem { Label("Post-Processing", systemImage: "sparkles") }
            AudioSettingsTab()
                .tabItem { Label("Audio", systemImage: "mic") }
            HistorySettingsTab()
                .tabItem { Label("History", systemImage: "clock") }
        }
        .frame(minWidth: 540, minHeight: 440)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isRecordingHotkey = false
    @StateObject private var hotkeyMonitor = HotkeyEventMonitor()

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Shortcut") {
                    Button(isRecordingHotkey ? "Press any key…" : formattedHotkey) {
                        if isRecordingHotkey {
                            stopHotkeyRecording()
                        } else {
                            startHotkeyRecording()
                        }
                    }
                    .foregroundStyle(isRecordingHotkey ? .red : .primary)
                    .buttonStyle(.bordered)
                    .onDisappear { stopHotkeyRecording() }
                }
                Picker("Mode", selection: $coordinator.config.hotkeyMode) {
                    ForEach(AppConfig.HotkeyMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Behavior") {
                LaunchAtLoginToggle()
                Toggle("Sound feedback on recording start/stop",
                       isOn: $coordinator.config.soundFeedbackEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var formattedHotkey: String {
        formatHotkey(keyCode: coordinator.config.hotkeyKeyCode,
                     modifiers: coordinator.config.hotkeyModifiers)
    }

    private func startHotkeyRecording() {
        isRecordingHotkey = true
        hotkeyMonitor.start { keyCode, modifiers in
            coordinator.config.hotkeyKeyCode = keyCode
            coordinator.config.hotkeyModifiers = modifiers
            isRecordingHotkey = false
        }
    }

    private func stopHotkeyRecording() {
        hotkeyMonitor.stop()
        isRecordingHotkey = false
    }

    private func formatHotkey(keyCode: UInt16, modifiers: UInt64) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option)  { result += "⌥" }
        if flags.contains(.shift)   { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        result += keyCodeToString(keyCode)
        return result.isEmpty ? "None" : result
    }

    private func keyCodeToString(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",
            6: "Z",  7: "X",  8: "C",  9: "V", 11: "B", 12: "Q",
           13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O",
           32: "U", 34: "I", 37: "L", 38: "J", 40: "K", 45: "N",
           46: "M", 18: "1", 19: "2", 20: "3", 21: "4",
           23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        ]
        return map[code] ?? "Key \(code)"
    }
}

// MARK: - Hotkey Event Monitor

final class HotkeyEventMonitor: ObservableObject, @unchecked Sendable {
    private var monitor: Any?

    func start(onCapture: @escaping @MainActor (UInt16, UInt64) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let kc = event.keyCode
            let mods = UInt64(event.modifierFlags
                .intersection([.shift, .control, .option, .command]).rawValue)
            Task { @MainActor in
                onCapture(kc, mods)
            }
            return nil
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit { stop() }
}

// MARK: - Launch at Login

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $enabled)
            .onChange(of: enabled) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    enabled = !newValue
                }
            }
    }
}

// MARK: - ASR Engine Tab

struct ASREngineSettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var downloadManager: ModelDownloadManager

    var body: some View {
        Form {
            Section {
                engineRow(
                    engine: .whisperKit,
                    state: downloadManager.whisperKitState,
                    title: "WhisperKit (large-v3-turbo)",
                    subtitle: "~600 MB · ~0.45s latency · Best for whispers, accents, noise",
                    isRecommended: true
                )
                Divider()
                engineRow(
                    engine: .parakeet,
                    state: downloadManager.parakeetState,
                    title: "Parakeet TDT v3",
                    subtitle: "~480 MB · ~0.19s latency · Best for clear speech, speed",
                    isRecommended: false
                )
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func engineRow(
        engine: AppConfig.ASREngineOption,
        state: ModelDownloadManager.ModelState,
        title: String,
        subtitle: String,
        isRecommended: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    if engine == .parakeet {
                        Text("Coming soon")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.secondary.opacity(0.15))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                stateLabel(state: state)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if coordinator.config.asrEngine == engine {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                actionButtons(engine: engine, state: state)
            }
        }
        .padding(.vertical, 4)
        .opacity(engine == .parakeet ? 0.65 : 1.0)
    }

    @ViewBuilder
    private func stateLabel(state: ModelDownloadManager.ModelState) -> some View {
        switch state {
        case .notDownloaded:
            Text("Not downloaded").font(.caption).foregroundStyle(.secondary)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress).frame(maxWidth: 180)
                Text("\(Int(progress * 100))%").font(.caption2).foregroundStyle(.secondary)
            }
        case .downloaded:
            Text("Downloaded").font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Text("Failed: \(msg)").font(.caption).foregroundStyle(.red).lineLimit(2)
        }
    }

    @ViewBuilder
    private func actionButtons(
        engine: AppConfig.ASREngineOption,
        state: ModelDownloadManager.ModelState
    ) -> some View {
        switch state {
        case .notDownloaded, .failed:
            Button("Download") {
                Task {
                    switch engine {
                    case .whisperKit: await downloadManager.downloadWhisperKit()
                    case .parakeet:   await downloadManager.downloadParakeet()
                    }
                }
            }
            .disabled(engine == .parakeet)

        case .downloading:
            ProgressView().controlSize(.small)

        case .downloaded:
            HStack(spacing: 8) {
                if coordinator.config.asrEngine != engine {
                    Button("Switch") {
                        coordinator.config.asrEngine = engine
                    }
                }
                Button("Delete", role: .destructive) {
                    downloadManager.deleteModel(engine)
                    if coordinator.config.asrEngine == engine {
                        coordinator.config.asrEngine = .whisperKit
                    }
                }
            }
        }
    }
}

// MARK: - Post-Processing Tab

enum OllamaConnectionStatus { case unknown, connected, failed }

struct PostProcessingSettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var connectionStatus: OllamaConnectionStatus = .unknown
    @State private var testing = false

    var body: some View {
        Form {
            Section("Post-Processor") {
                Picker("Engine", selection: $coordinator.config.postProcessor) {
                    Text("None (raw transcript)").tag(AppConfig.PostProcessorOption.passthrough)
                    Text("Ollama (local LLM)").tag(AppConfig.PostProcessorOption.ollama)
                }
                .pickerStyle(.radioGroup)
            }

            if coordinator.config.postProcessor == .ollama {
                Section("Ollama Configuration") {
                    LabeledContent("Model") {
                        TextField("e.g. qwen3.5:4b", text: $coordinator.config.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }
                    LabeledContent("Host URL") {
                        TextField("http://localhost:11434",
                                  text: $coordinator.config.ollamaHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }
                    HStack(spacing: 12) {
                        Button("Test Connection") {
                            Task { await testConnection() }
                        }
                        .disabled(testing)

                        switch connectionStatus {
                        case .unknown:   EmptyView()
                        case .connected: Label("Connected", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                        case .failed:    Label("Failed", systemImage: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: coordinator.config.postProcessor) { _, _ in
            connectionStatus = .unknown
        }
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        let host = coordinator.config.ollamaHost
        guard let url = URL(string: host + "/api/tags") else {
            connectionStatus = .failed
            return
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            connectionStatus = (response as? HTTPURLResponse)?.statusCode == 200 ? .connected : .failed
        } catch {
            connectionStatus = .failed
        }
    }
}

// MARK: - Audio Tab

struct AudioSettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var levelMonitor = MicLevelMonitor()
    @State private var devices: [AudioDeviceInfo] = []

    var body: some View {
        Form {
            Section("Input Device") {
                Picker("Device", selection: $coordinator.config.audioInputDeviceUID) {
                    Text("System Default").tag(Optional<String>(nil))
                    ForEach(devices, id: \.uid) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
            }

            Section("Gain Normalization") {
                Toggle("Normalize recording level",
                       isOn: $coordinator.config.gainNormalizationEnabled)
                if coordinator.config.gainNormalizationEnabled {
                    LabeledContent("Target level") {
                        HStack {
                            Slider(value: $coordinator.config.gainTargetDBFS,
                                   in: -30.0 ... -10.0, step: 1.0)
                                .frame(maxWidth: 160)
                            Text("\(Int(coordinator.config.gainTargetDBFS)) dBFS")
                                .monospacedDigit()
                                .frame(width: 65, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Recording Limits") {
                LabeledContent("Max duration") {
                    Stepper(
                        "\(Int(coordinator.config.maxRecordingDurationSeconds)) seconds",
                        value: $coordinator.config.maxRecordingDurationSeconds,
                        in: 5.0 ... 60.0,
                        step: 5.0
                    )
                }
            }

            Section("Mic Level") {
                MicLevelMeterView(level: levelMonitor.level)
                    .frame(height: 18)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            devices = AudioDeviceManager.availableInputDevices()
            levelMonitor.start()
        }
        .onDisappear {
            levelMonitor.stop()
        }
    }
}

// MARK: - Mic Level Monitor

@MainActor
final class MicLevelMonitor: ObservableObject {
    @Published var level: Float = 0
    private var engine: AVAudioEngine?

    func start() {
        let eng = AVAudioEngine()
        engine = eng
        let inputNode = eng.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var sum: Float = 0
            for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
            let rms = sqrt(sum / Float(frameCount))
            let db = 20.0 * log10(max(rms, 1e-8))
            let normalized = Float(max(0.0, min(1.0, (db + 60.0) / 60.0)))
            Task { @MainActor [weak self] in
                self?.level = normalized
            }
        }
        try? eng.start()
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0
    }
}

// MARK: - Mic Level Meter View

struct MicLevelMeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(meterColor)
                    .frame(width: geo.size.width * CGFloat(max(0, level)))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }

    private var meterColor: Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }
}

// MARK: - History Tab

struct HistorySettingsTab: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section {
                Toggle("Keep transcript history",
                       isOn: $coordinator.config.keepTranscriptHistory)
                LabeledContent("Max entries") {
                    Stepper(
                        "\(coordinator.config.maxHistoryItems)",
                        value: $coordinator.config.maxHistoryItems,
                        in: 10 ... 1000,
                        step: 10
                    )
                }
            }
            Section {
                Button("Clear History", role: .destructive) {
                    // Implemented in Issue 18
                }
                .disabled(true)
            }
        }
        .formStyle(.grouped)
    }
}
