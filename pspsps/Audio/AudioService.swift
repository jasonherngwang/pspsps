import AppKit
import AVFoundation
import OSLog

/// A service to decouple Audio Input responsibilities from the AppCoordinator
@MainActor
final class AudioService: ObservableObject {
    private let captureManager = AudioCaptureManager()
    private let logger = Logger(subsystem: "com.pspsps.pspsps", category: "AudioService")
    
    var onAutoStop: ((AVAudioPCMBuffer) -> Void)? {
        get { captureManager.onAutoStop }
        set { captureManager.onAutoStop = newValue }
    }
    
    var onDeviceDisconnected: (() -> Void)? {
        get { captureManager.onDeviceDisconnected }
        set { captureManager.onDeviceDisconnected = newValue }
    }

    /// Synchronous variant for use from an already-detached context.
    nonisolated func startCaptureDirect() throws {
        try captureManager.startCapture()
    }
    
    func stopCapture() -> AVAudioPCMBuffer {
        return captureManager.stopCapture()
    }
    
    func checkMicrophonePermission(onDenied: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            logger.warning("Microphone access denied — recording will not work")
            onDenied()
        default:
            break
        }
    }
}
