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

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(coordinator: coordinator)
        recordingOverlay = RecordingOverlay(coordinator: coordinator)
    }
}
