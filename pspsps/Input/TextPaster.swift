import Cocoa
import CoreGraphics

final class TextPaster: @unchecked Sendable {

    /// Writes `text` to the general pasteboard, synthesizes a Cmd+V keystroke,
    /// then restores the previous pasteboard contents after `restoreDelay` seconds.
    func paste(_ text: String, restoreDelay: Double? = nil) {
        let delay = restoreDelay ?? AppConfig.current.pasteboardRestoreDelaySeconds
        let pasteboard = NSPasteboard.general

        // Save current pasteboard string so we can restore it afterward.
        let savedString = pasteboard.string(forType: .string)

        // Write the new text.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Synthesize Cmd+V so the frontmost app pastes.
        synthesizeCmdV()

        // After the delay, restore the previous pasteboard contents.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            pasteboard.clearContents()
            if let saved = savedString {
                pasteboard.setString(saved, forType: .string)
            }
        }
    }

    // MARK: - Private

    private func synthesizeCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Virtual key 0x09 = 'v' on US keyboard layout
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
