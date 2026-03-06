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

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
    }
}
