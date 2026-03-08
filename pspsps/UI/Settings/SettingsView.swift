import AVFoundation
import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeneralSection(vm: vm)
                Divider().padding(.vertical, 12)
                ASREngineSection(vm: vm)
                Divider().padding(.vertical, 12)
                PostProcessingSection(vm: vm)
                Divider().padding(.vertical, 12)
                AudioSection(vm: vm)
                Divider().padding(.vertical, 12)
                HistorySection(vm: vm)
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 480)
    }
}

// MARK: - General

private struct GeneralSection: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor = HotkeyEventMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General").font(.headline)

            HStack {
                Text("Shortcut")
                Spacer()
                Text(isRecordingHotkey ? "Press any key…" : formattedHotkey)
                    .foregroundStyle(isRecordingHotkey ? .red : .primary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isRecordingHotkey { stopHotkeyRecording() }
                        else { startHotkeyRecording() }
                    }
            }
            .onDisappear { stopHotkeyRecording() }

            HStack {
                Text("Mode")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(AppConfig.HotkeyMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                            .font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(vm.config.hotkeyMode == mode
                                ? Color.accentColor.opacity(0.2)
                                : Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                            .onTapGesture { vm.config.hotkeyMode = mode }
                    }
                }
            }

            LaunchAtLoginToggle()

            CheckRow(label: "Sound feedback on recording start/stop",
                     isOn: $vm.config.soundFeedbackEnabled)
        }
    }

    private var formattedHotkey: String {
        formatHotkey(keyCode: vm.config.hotkeyKeyCode,
                     modifiers: vm.config.hotkeyModifiers)
    }

    private func startHotkeyRecording() {
        isRecordingHotkey = true
        hotkeyMonitor.start { keyCode, modifiers in
            vm.config.hotkeyKeyCode = keyCode
            vm.config.hotkeyModifiers = modifiers
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

final class HotkeyEventMonitor {
    private var monitor: Any?

    func start(onCapture: @escaping (UInt16, UInt64) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let kc = event.keyCode
            let mods = UInt64(event.modifierFlags
                .intersection([.shift, .control, .option, .command]).rawValue)
            onCapture(kc, mods)
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

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        let binding = Binding<Bool>(
            get: { enabled },
            set: { newValue in
                enabled = newValue
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    Task { @MainActor in
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
            }
        )
        Toggle("Launch at login", isOn: binding)
    }
}

// MARK: - ASR Engine

private struct ASREngineSection: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ASR Engine").font(.headline)

            engineRow(
                engine: .parakeet,
                state: vm.parakeetState,
                title: "Parakeet TDT v3",
                subtitle: "~480 MB · ~0.19s latency · Best for clear speech, speed",
                isRecommended: true
            )
            engineRow(
                engine: .whisperKit,
                state: vm.whisperKitState,
                title: "WhisperKit (large-v3-turbo)",
                subtitle: "~600 MB · ~0.45s latency · Best for whispers, accents, noise",
                isRecommended: false
            )
        }
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline).bold()
                    if isRecommended {
                        Text("Recommended")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    if vm.config.asrEngine == engine {
                        Text("Active")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                stateLabel(state: state)
            }
            Spacer()
            actionButtons(engine: engine, state: state)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func stateLabel(state: ModelDownloadManager.ModelState) -> some View {
        switch state {
        case .notDownloaded:
            Text("Not downloaded").font(.caption).foregroundStyle(.secondary)
        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress).frame(maxWidth: 120)
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
            TapButton(title: "Download") {
                switch engine {
                case .whisperKit: vm.downloadWhisperKit()
                case .parakeet:   vm.downloadParakeet()
                }
            }
        case .downloading:
            ProgressView().controlSize(.small)
        case .downloaded:
            HStack(spacing: 12) {
                if vm.config.asrEngine != engine {
                    TapButton(title: "Switch") {
                        vm.config.asrEngine = engine
                    }
                }
                TapButton(title: "Delete", isDestructive: true) {
                    vm.deleteModel(engine)
                    if vm.config.asrEngine == engine {
                        vm.config.asrEngine = .whisperKit
                    }
                }
            }
        }
    }
}

// MARK: - Post-Processing

private enum OllamaConnectionStatus { case unknown, connected, failed }

private struct PostProcessingSection: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var connectionStatus: OllamaConnectionStatus = .unknown
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Post-Processing").font(.headline)

            HStack {
                Text("Engine")
                Spacer()
                HStack(spacing: 4) {
                    optionChip(label: "None", value: AppConfig.PostProcessorOption.passthrough,
                               selection: vm.config.postProcessor) {
                        vm.config.postProcessor = .passthrough
                    }
                    optionChip(label: "Ollama", value: AppConfig.PostProcessorOption.ollama,
                               selection: vm.config.postProcessor) {
                        vm.config.postProcessor = .ollama
                    }
                }
            }

            if vm.config.postProcessor == .ollama {
                HStack {
                    Text("Model")
                    Spacer()
                    TextField("e.g. qwen3.5:4b", text: $vm.config.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                HStack {
                    Text("Host URL")
                    Spacer()
                    TextField("http://localhost:11434", text: $vm.config.ollamaHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                HStack(spacing: 12) {
                    Text(testing ? "Testing…" : "Test Connection")
                        .foregroundStyle(testing ? .secondary : Color.accentColor)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !testing else { return }
                            Task { await testConnection() }
                        }
                    switch connectionStatus {
                    case .unknown:   EmptyView()
                    case .connected: Text("Connected").foregroundStyle(.green)
                    case .failed:    Text("Failed").foregroundStyle(.red)
                    }
                }
            }
        }
        .onChange(of: vm.config.postProcessor) { _, _ in connectionStatus = .unknown }
    }

    private func optionChip<T: Equatable>(
        label: String,
        value: T,
        selection: T,
        action: @escaping () -> Void
    ) -> some View {
        Text(label)
            .font(.subheadline)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(selection == value
                ? Color.accentColor.opacity(0.2)
                : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private func testConnection() async {
        testing = true
        defer { testing = false }
        guard let url = URL(string: vm.config.ollamaHost + "/api/tags") else {
            connectionStatus = .failed; return
        }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            connectionStatus = (response as? HTTPURLResponse)?.statusCode == 200 ? .connected : .failed
        } catch {
            connectionStatus = .failed
        }
    }
}

// MARK: - Audio

private struct AudioSection: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var devices: [AudioDeviceInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Input device")
                VStack(alignment: .leading, spacing: 3) {
                    deviceChip(label: "System Default", uid: nil)
                    ForEach(devices, id: \.uid) { device in
                        deviceChip(label: device.name, uid: device.uid)
                    }
                }
                .padding(.leading, 8)
            }

            CheckRow(label: "Normalize recording level",
                     isOn: $vm.config.gainNormalizationEnabled)

            if vm.config.gainNormalizationEnabled {
                HStack {
                    Text("Target level")
                    Spacer()
                    Slider(value: $vm.config.gainTargetDBFS, in: -30.0 ... -10.0, step: 1.0)
                        .frame(maxWidth: 140)
                    Text("\(Int(vm.config.gainTargetDBFS)) dBFS")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }

            HStack {
                Text("Max duration")
                Spacer()
                Stepper(
                    "\(Int(vm.config.maxRecordingDurationSeconds))s",
                    value: $vm.config.maxRecordingDurationSeconds,
                    in: 5.0 ... 60.0, step: 5.0
                )
            }
        }
        .onAppear { devices = AudioDeviceManager.availableInputDevices() }
    }

    private func deviceChip(label: String, uid: String?) -> some View {
        let isSelected = uid == nil
            ? vm.config.audioInputDeviceUID == nil
            : vm.config.audioInputDeviceUID == uid
        return Text(label)
            .font(.subheadline)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(isSelected
                ? Color.accentColor.opacity(0.2)
                : Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { vm.config.audioInputDeviceUID = uid }
    }
}

// MARK: - History

private struct HistorySection: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").font(.headline)

            CheckRow(label: "Keep transcript history",
                     isOn: $vm.config.keepTranscriptHistory)

            HStack {
                Text("Max entries")
                Spacer()
                Stepper(
                    "\(vm.config.maxHistoryItems)",
                    value: $vm.config.maxHistoryItems,
                    in: 10 ... 1000, step: 10
                )
            }

            TapButton(title: "Clear History", isDestructive: true) {
                vm.clearHistory()
            }
        }
    }
}

// MARK: - Gesture-based helpers
// These replace SwiftUI Button/Toggle/Picker which trigger DesignLibrary
// executor checks on macOS 26 (Tahoe) and crash when re-rendered.

/// Replaces SwiftUI Toggle.
private struct CheckRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(isOn ? "✓" : "")
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, alignment: .center)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// Replaces SwiftUI Button.
private struct TapButton: View {
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Text(title)
            .foregroundStyle(isDestructive ? .red : Color.accentColor)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
