import AVFoundation
@testable import pspsps

final class MockASREngine: ASREngine {
    let name = "Mock"
    var isAvailable = true
    var mockResult: String = ""

    func loadModel() async throws {}

    func unloadModel() {}

    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        return TranscriptionResult(
            text: mockResult,
            confidence: nil,
            processingTimeMs: 0,
            language: nil
        )
    }
}
