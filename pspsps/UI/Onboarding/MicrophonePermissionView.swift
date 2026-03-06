import SwiftUI
import AVFoundation

/// Step 3 of onboarding: requests microphone access via AVCaptureDevice.
/// Advances immediately if permission is already granted.
struct MicrophonePermissionView: View {
    let onComplete: () -> Void

    @State private var requesting = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Enable Microphone")
                .font(.title2).bold()

            Text("pspsps needs microphone access to capture your voice for transcription.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Allow Microphone Access") {
                requesting = true
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        requesting = false
                        if granted { onComplete() }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(requesting)
        }
        .padding(40)
        .frame(minWidth: 480)
        .onAppear {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                onComplete()
            }
        }
    }
}
