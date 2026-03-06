import SwiftUI

@main
struct pspspsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Menu bar only — no main window.
        // AppCoordinator is created immediately in AppDelegate (before applicationDidFinishLaunching)
        // so it is safe to inject as an environment object here.
        Settings {
            SettingsView()
                .environmentObject(delegate.coordinator)
                .environmentObject(delegate.coordinator.downloadManager)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // coordinator is a `let` so it is ready before applicationDidFinishLaunching.
    let coordinator = AppCoordinator()
    private var menuBarController: MenuBarController?
    private var recordingOverlay: RecordingOverlay?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(coordinator: coordinator)
        recordingOverlay = RecordingOverlay(coordinator: coordinator)

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindow()
        }
    }

    private func showOnboardingWindow() {
        let view = OnboardingView(onComplete: { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
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
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}
