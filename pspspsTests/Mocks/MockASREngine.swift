import AVFoundation
@testable import pspsps

final class MockASREngine: ASREngine, @unchecked Sendable {
    let name = "Mock"
    var isAvailable = true
    var mockResult: String = ""
    /// If > 0, transcribe() sleeps for this duration (supports cooperative cancellation).
    var transcribeDelay: TimeInterval = 0

    func loadModel() async throws {}

    func unloadModel() {}

    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        if transcribeDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(transcribeDelay * 1_000_000_000))
        }
        return TranscriptionResult(
            text: mockResult,
            confidence: nil,
            processingTimeMs: 0,
            language: nil
        )
    }
}
