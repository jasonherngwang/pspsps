import AppKit
import OSLog

/// A service to decouple Hotkey listening from the AppCoordinator
@MainActor
final class ShortcutService: ObservableObject {
    private let hotkeyManager = HotkeyManager()
    private let logger = Logger(subsystem: "com.pspsps.pspsps", category: "ShortcutService")
    
    var onHotkeyEvent: ((HotkeyEvent) -> Void)? {
        get { hotkeyManager.onHotkeyEvent }
        set { hotkeyManager.onHotkeyEvent = newValue }
    }


    func startListening(config: AppConfig, onPermissionDenied: @escaping () -> Void) {
        do {
            try hotkeyManager.startListening(
                keyCode: config.hotkeyKeyCode,
                modifiers: CGEventFlags(rawValue: config.hotkeyModifiers),
                mode: config.hotkeyMode
            )
        } catch HotkeyManagerError.accessibilityNotGranted {
            logger.warning("Accessibility permission not granted — hotkey disabled")
            onPermissionDenied()
        } catch {
            logger.error("Hotkey listener failed to start: \(error)")
        }
    }
}
