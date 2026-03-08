@preconcurrency import Cocoa
import ApplicationServices
import OSLog

enum HotkeyEvent: Sendable {
    case started
    case stopped
}

private let logger = Logger(subsystem: "com.pspsps.pspsps", category: "HotkeyManager")

/// Manages a CGEvent tap for global hotkey detection.
///
/// Not @MainActor — uses nonisolated(unsafe) storage so the C callback can access
/// state directly without MainActor.assumeIsolated (which can crash on macOS 26
/// due to null-executor dereference in swift_task_isCurrentExecutorWithFlagsImpl).
/// All mutations happen on the main thread; the C callback runs on the main RunLoop.
final class HotkeyManager: @unchecked Sendable {

    nonisolated(unsafe) var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    nonisolated(unsafe) private var configKeyCode: UInt16 = 0
    nonisolated(unsafe) private var configModifiers: CGEventFlags = []
    nonisolated(unsafe) private var configMode: AppConfig.HotkeyMode = .pushToTalk
    nonisolated(unsafe) private var isToggleActive = false

    nonisolated(unsafe) private var eventTap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var tapContext: TapContext?
    /// Backup keyUp monitor — catches releases the CGEvent tap misses when
    /// the system temporarily disables it (tapDisabledByTimeout).
    /// When the tap is active it consumes matched events (returns nil),
    /// so this monitor never fires in the normal case.
    nonisolated(unsafe) private var globalKeyUpMonitor: Any?
    nonisolated(unsafe) private var localKeyUpMonitor: Any?

    // MARK: - Public API

    func startListening(
        keyCode: UInt16,
        modifiers: CGEventFlags,
        mode: AppConfig.HotkeyMode
    ) throws {
        stopListening()

        configKeyCode = keyCode
        configModifiers = modifiers
        configMode = mode
        isToggleActive = false

        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility not granted")
            throw HotkeyManagerError.accessibilityNotGranted
        }

        let context = TapContext(manager: self)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyManagerEventTapCallback,
            userInfo: contextPtr
        ) else {
            Unmanaged<TapContext>.fromOpaque(contextPtr).release()
            logger.error("CGEvent tap creation failed")
            throw HotkeyManagerError.tapCreationFailed
        }

        tapContext = context
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Backup keyUp monitors — when the CGEvent tap is disabled by the system,
        // events pass through untouched. The global monitor catches keyUp going to
        // other apps; the local monitor catches keyUp if our app happens to be frontmost
        // (e.g. briefly during launch). handleHotkeyStopped() is idempotent so
        // double-firing from tap + monitor is harmless.
        if mode == .pushToTalk {
            globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] nsEvent in
                guard let self else { return }
                guard nsEvent.keyCode == self.configKeyCode else { return }
                logger.debug("Global monitor caught keyUp for hotkey")
                self.onHotkeyEvent?(.stopped)
            }
            localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] nsEvent in
                guard let self else { return nsEvent }
                guard nsEvent.keyCode == self.configKeyCode else { return nsEvent }
                logger.debug("Local monitor caught keyUp for hotkey")
                self.onHotkeyEvent?(.stopped)
                return nsEvent
            }
        }

        logger.notice("Hotkey listening started: keyCode=\(keyCode), modifiers=\(modifiers.rawValue)")
    }

    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        tapContext = nil
        if let monitor = globalKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyUpMonitor = nil
        }
        if let monitor = localKeyUpMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyUpMonitor = nil
        }
    }

    // MARK: - CGEvent Handling (called directly from C callback, no actor context needed)

    fileprivate func handleRawEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("CGEvent tap was disabled (type=\(type.rawValue)), re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == configKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let maskedEvent = event.flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        let maskedConfig = configModifiers.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        guard maskedEvent == maskedConfig else {
            return Unmanaged.passUnretained(event)
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch configMode {
        case .pushToTalk:
            if type == .keyDown && !isRepeat {
                logger.debug("Tap: keyDown for hotkey")
                onHotkeyEvent?(.started)
            } else if type == .keyUp {
                logger.debug("Tap: keyUp for hotkey")
                onHotkeyEvent?(.stopped)
            }
        case .toggle:
            if type == .keyDown && !isRepeat {
                isToggleActive.toggle()
                onHotkeyEvent?(isToggleActive ? .started : .stopped)
            }
        }

        return nil
    }
}

// MARK: - Error

enum HotkeyManagerError: Error {
    case accessibilityNotGranted
    case tapCreationFailed
}

// MARK: - Safe ref wrapper for C callback

private final class TapContext {
    weak var manager: HotkeyManager?
    init(manager: HotkeyManager) { self.manager = manager }
}

// MARK: - C callback (runs on main thread via CFRunLoopGetMain)
// Does NOT use MainActor.assumeIsolated — that can crash on macOS 26 (Tahoe)
// when swift_task_isCurrentExecutorWithFlagsImpl dereferences a null executor.
// Instead, onHotkeyEvent dispatches @MainActor work via Task.

private let hotkeyManagerEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue()
    guard let manager = context.manager else { return Unmanaged.passUnretained(event) }
    return manager.handleRawEvent(type: type, event: event)
}
