import ApplicationServices
import Cocoa
import CoreGraphics

final class TextPaster {

    /// Writes `text` to the general pasteboard, then synthesizes a Cmd+V keystroke
    /// if Accessibility permission is granted.
    ///
    /// Returns `true` if the paste keystroke was synthesized, `false` if Accessibility
    /// permission was not granted (text is still written to the clipboard in that case).
    @discardableResult
    func paste(_ text: String, restoreDelay: Double? = nil) -> Bool {
        let delay = restoreDelay ?? AppConfig.current.pasteboardRestoreDelaySeconds
        let pasteboard = NSPasteboard.general

        // Save current pasteboard string so we can restore it afterward.
        let savedString = pasteboard.string(forType: .string)

        // Write the new text.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Only synthesize the keystroke if Accessibility is trusted.
        let pasted = AXIsProcessTrusted()
        if pasted {
            synthesizeCmdV()
        }

        // After the delay, restore the previous pasteboard contents.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            pasteboard.clearContents()
            if let saved = savedString {
                pasteboard.setString(saved, forType: .string)
            }
        }

        return pasted
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
