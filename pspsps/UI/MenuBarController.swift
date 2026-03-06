import AppKit
import Combine
import SwiftUI

/// Manages the NSStatusItem in the system menu bar and syncs its icon to AppCoordinator state.
@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
        setupPopover()
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

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView()
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

        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")

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

    // MARK: - State Observation

    private func observeState(coordinator: AppCoordinator) {
        coordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: AppCoordinator.AppState) {
        guard let button = statusItem.button else { return }
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

// MARK: - Popover Content (placeholder)

private struct MenuBarPopoverView: View {
    var body: some View {
        VStack(spacing: 10) {
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
        .padding()
        .frame(width: 260, height: 140)
    }
}
