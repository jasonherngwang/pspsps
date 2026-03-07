import AppKit
import Combine

/// Manages the NSStatusItem in the system menu bar and syncs its icon to AppCoordinator state.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AppCoordinator) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        setupMenu()
        observeState(coordinator: coordinator)
    }

    // MARK: - Setup

    private func setupMenu() {
        guard let button = statusItem.button else { return }
        button.image = makeIcon(systemName: "waveform", template: true)

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(AppDelegate.menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = AppDelegate.shared

        let historyItem = NSMenuItem(title: "History", action: #selector(AppDelegate.menuShowHistory), keyEquivalent: "")
        historyItem.target = AppDelegate.shared

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.addItem(settingsItem)
        menu.addItem(historyItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - State Observation

    private func observeState(coordinator: AppCoordinator) {
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
            button.image = makeIcon(systemName: "lock.fill", template: true)
            button.contentTintColor = nil
            return
        }

        if modelNotLoaded {
            button.image = makeIcon(systemName: "exclamationmark.triangle.fill", template: false)
            button.contentTintColor = .systemYellow
            return
        }

        switch state {
        case .idle:
            button.image = makeIcon(systemName: "waveform", template: true)
            button.contentTintColor = nil
        case .recording:
            button.image = makeIcon(systemName: "waveform", template: false)
            button.contentTintColor = .systemRed
        case .transcribing:
            button.image = makeIcon(systemName: "waveform", template: false)
            button.contentTintColor = .systemOrange
        }
    }

    private func makeIcon(systemName: String, template: Bool) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: "pspsps")
        image?.isTemplate = template
        return image
    }
}
