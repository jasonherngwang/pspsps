import Cocoa
import ApplicationServices

enum HotkeyEvent: Sendable {
    case started
    case stopped
}

enum HotkeyManagerError: Error {
    case accessibilityNotGranted
    case tapCreationFailed
}

final class HotkeyManager: @unchecked Sendable {

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?

    private var configKeyCode: UInt16 = 0
    private var configModifiers: CGEventFlags = []
    private var configMode: AppConfig.HotkeyMode = .pushToTalk
    private var isToggleActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private static let relevantModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]

    deinit {
        stopListening()
    }

    // MARK: - Public API

    func isPermissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func startListening(
        keyCode: UInt16,
        modifiers: CGEventFlags,
        mode: AppConfig.HotkeyMode
    ) throws {
        guard AXIsProcessTrusted() else {
            throw HotkeyManagerError.accessibilityNotGranted
        }

        stopListening()

        configKeyCode = keyCode
        configModifiers = modifiers.intersection(HotkeyManager.relevantModifiers)
        configMode = mode
        isToggleActive = false

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyManagerEventTapCallback,
            userInfo: selfPtr
        ) else {
            throw HotkeyManagerError.tapCreationFailed
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
    }

    // MARK: - Event handling (called from the C callback on the main runloop)

    fileprivate func handleRawEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable the tap if macOS disabled it due to timeout or user input.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        // Match key code.
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == configKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        // Match modifiers (only the modifier keys we care about).
        let eventModifiers = event.flags.intersection(HotkeyManager.relevantModifiers)
        guard eventModifiers == configModifiers else {
            return Unmanaged.passUnretained(event)
        }

        // Ignore key-repeat events so PTT/toggle don't fire repeatedly while held.
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch configMode {
        case .pushToTalk:
            if type == .keyDown && !isRepeat {
                onHotkeyEvent?(.started)
            } else if type == .keyUp {
                onHotkeyEvent?(.stopped)
            }
        case .toggle:
            if type == .keyDown && !isRepeat {
                isToggleActive.toggle()
                onHotkeyEvent?(isToggleActive ? .started : .stopped)
            }
        }

        // Return nil to consume the event (prevent the foreground app from seeing it).
        return nil
    }
}

// MARK: - C callback (free function required by CGEvent.tapCreate)

private let hotkeyManagerEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleRawEvent(type: type, event: event)
}
