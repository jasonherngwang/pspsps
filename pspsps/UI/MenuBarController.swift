import AppKit
import Combine
import SwiftUI

/// Manages the NSStatusItem in the system menu bar and syncs its icon to AppCoordinator state.
@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let historyPopover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
        setupPopover(coordinator: coordinator)
        setupHistoryPopover(coordinator: coordinator)
        observeState(coordinator: coordinator)
    }

    // MARK: - Setup

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = makeIcon(systemName: "mic", template: true)
        button.action = #selector(handleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover(coordinator: AppCoordinator) {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(coordinator: coordinator)
        )
    }

    private func setupHistoryPopover(coordinator: AppCoordinator) {
        historyPopover.behavior = .transient
        historyPopover.contentViewController = NSHostingController(
            rootView: HistoryPopoverView(
                history: coordinator.transcriptHistory,
                textPaster: coordinator.textPaster
            )
        )
    }

    // MARK: - Click Handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let historyItem = NSMenuItem(title: "History", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.addItem(settingsItem)
        menu.addItem(historyItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        // Temporarily assign menu to show it, then clear so left-click still shows the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showHistory() {
        // Dispatch so the context menu has time to dismiss before showing the popover.
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            if self.historyPopover.isShown {
                self.historyPopover.performClose(nil)
            } else {
                self.popover.performClose(nil)
                self.historyPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    // MARK: - State Observation

    private func observeState(coordinator: AppCoordinator) {
        // Re-render icon whenever any of the relevant published properties change.
        coordinator.$state
            .combineLatest(coordinator.$modelNotLoaded, coordinator.$accessibilityNotGranted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, modelNotLoaded, accessibilityNotGranted in
                self?.updateIcon(
                    state: state,
                    modelNotLoaded: modelNotLoaded,
                    accessibilityNotGranted: accessibilityNotGranted
                )
            }
            .store(in: &cancellables)
    }

    private func updateIcon(
        state: AppCoordinator.AppState,
        modelNotLoaded: Bool,
        accessibilityNotGranted: Bool
    ) {
        guard let button = statusItem.button else { return }

        if accessibilityNotGranted {
            // Lock icon: accessibility must be granted for hotkey to work.
            button.image = makeIcon(systemName: "lock.fill", template: true)
            button.contentTintColor = nil
            return
        }

        if modelNotLoaded {
            // Warning badge: model failed to load.
            button.image = makeIcon(systemName: "exclamationmark.triangle.fill", template: false)
            button.contentTintColor = .systemYellow
            return
        }

        switch state {
        case .idle:
            button.image = makeIcon(systemName: "mic", template: true)
            button.contentTintColor = nil
        case .recording:
            button.image = makeIcon(systemName: "mic.fill", template: false)
            button.contentTintColor = .systemRed
        case .transcribing:
            button.image = makeIcon(systemName: "waveform", template: true)
            button.contentTintColor = nil
        }
    }

    private func makeIcon(systemName: String, template: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: "pspsps")
        image?.isTemplate = template
        return image
    }
}

// MARK: - Popover Content

private struct MenuBarPopoverView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if coordinator.lastTranscript.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("pspsps")
                        .font(.headline)
                    Text("Press the hotkey to start recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Last transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(coordinator.lastTranscript)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                Button("Copy & Paste") {
                    coordinator.textPaster.paste(coordinator.lastTranscript)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(width: 260)
    }
}
