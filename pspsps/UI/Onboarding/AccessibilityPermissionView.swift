import SwiftUI
import ApplicationServices

/// Step 2 of onboarding: asks the user to grant Accessibility permission.
/// Polls `AXIsProcessTrusted()` every 500 ms and auto-advances when granted.
struct AccessibilityPermissionView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Enable Accessibility")
                .font(.title2).bold()

            Text("pspsps needs Accessibility access to type transcribed text into other apps.\n\nOpen System Settings and add pspsps under Privacy & Security → Accessibility.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    // swiftlint:disable:next force_unwrapping
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Waiting for permission…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 480)
        .onReceive(
            Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
        ) { _ in
            if AXIsProcessTrusted() {
                onContinue()
            }
        }
    }
}
