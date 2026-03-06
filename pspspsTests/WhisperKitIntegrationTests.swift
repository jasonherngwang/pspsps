import XCTest
import AVFoundation
@testable import pspsps

// Integration tests — require WhisperKit model download (~600 MB on first run).
// Run with a generous timeout: xcodebuild test -scheme pspsps -destination 'platform=macOS' -testTimeout 300
final class WhisperKitIntegrationTests: XCTestCase {

    func testWhisperKitModelLoadsWithoutError() async throws {
        let engine = WhisperKitEngine()
        try await engine.loadModel()
        XCTAssertTrue(engine.isAvailable, "WhisperKit model should be available after loading")
    }

    func testWhisperKitTranscribesTestAudio() async throws {
        let engine = WhisperKitEngine()
        try await engine.loadModel()

        guard let wavURL = Bundle(for: type(of: self)).url(forResource: "test_speech", withExtension: "wav") else {
            XCTFail("test_speech.wav not found in test bundle")
            return
        }

        let audioFile = try AVAudioFile(forReading: wavURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Could not allocate audio buffer")
            return
        }
        try audioFile.read(into: buffer)

        let result = try await engine.transcribe(audio: buffer)
        XCTAssertFalse(result.text.isEmpty, "Transcription result should not be empty")

        let phraseWords = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog"]
        let lowered = result.text.lowercased()
        let matched = phraseWords.filter { lowered.contains($0) }
        XCTAssertGreaterThanOrEqual(
            matched.count, 3,
            "Expected ≥3 recognizable words from the test phrase. Got: \(result.text)"
        )
    }
}
