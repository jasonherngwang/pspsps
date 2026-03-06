import SwiftUI

@main
struct pspspsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Menu bar only — no main window.
        // AppCoordinator is started by AppDelegate on launch.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var menuBarController: MenuBarController?
    private var recordingOverlay: RecordingOverlay?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coord = AppCoordinator()
        coordinator = coord
        menuBarController = MenuBarController(coordinator: coord)
        recordingOverlay = RecordingOverlay(coordinator: coord)
    }
}
