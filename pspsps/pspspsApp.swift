import SwiftUI

/// Current settings window. Recreated on each open to avoid stale state after crashes.
nonisolated(unsafe) var _settingsWindow: NSWindow?

/// Pre-created history window, set during applicationDidFinishLaunching.
nonisolated(unsafe) var _historyWindow: NSWindow?

@main
struct pspspsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    let coordinator = AppCoordinator()
    lazy var settingsVM = SettingsViewModel(coordinator: coordinator)
    private var menuBarController: MenuBarController?
    private var recordingOverlay: RecordingOverlay?
    private var onboardingWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        if NSClassFromString("XCTestCase") != nil { return }

        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app")
        ProcessInfo.processInfo.disableSuddenTermination()

        #if !arch(arm64)
        let alert = NSAlert()
        alert.messageText = "pspsps requires Apple Silicon (M1 or later)"
        alert.informativeText = "This app uses on-device AI models optimized for Apple Silicon. Please run on a Mac with an M1 chip or later."
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
        return
        #endif

        menuBarController = MenuBarController(coordinator: coordinator)
        recordingOverlay = RecordingOverlay(coordinator: coordinator)
        setupHistoryWindow()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindow()
        }
    }

    @objc nonisolated func menuOpenSettings() {
        (self as NSObject).perform(#selector(_openSettingsDeferred), with: nil, afterDelay: 0)
    }

    /// Called from a RunLoop timer (main thread). Safe to use MainActor.assumeIsolated.
    @objc nonisolated func _openSettingsDeferred() {
        MainActor.assumeIsolated {
            // Always recreate to avoid stale window state after crashes.
            let view = SettingsView(vm: AppDelegate.shared.settingsVM)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Settings"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            _settingsWindow = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    @objc nonisolated func menuShowHistory() {
        _historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func setupHistoryWindow() {
        let view = HistoryPopoverView(
            history: coordinator.transcriptHistory,
            textPaster: coordinator.textPaster
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcript History"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        _historyWindow = window
    }

    private func showOnboardingWindow() {
        let view = OnboardingView(onComplete: {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            AppDelegate.shared?.onboardingWindow?.close()
            AppDelegate.shared?.onboardingWindow = nil
        })
        .environmentObject(coordinator)
        .environmentObject(coordinator.downloadManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to pspsps"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        onboardingWindow = window
    }
}
