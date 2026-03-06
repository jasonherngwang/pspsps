import AVFoundation
import FluidAudio

final class ParakeetEngine: ASREngine, @unchecked Sendable {
    let name = "Parakeet"
    private var asrManager: AsrManager?

    var isAvailable: Bool { asrManager?.isAvailable ?? false }

    static var modelDirectory: URL {
        AsrModels.defaultCacheDirectory()
    }

    func loadModel() async throws {
        let models = try await AsrModels.loadFromCache()
        let manager = AsrManager()
        try await manager.initialize(models: models)
        asrManager = manager
    }

    func unloadModel() {
        asrManager?.cleanup()
        asrManager = nil
    }

    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        let start = Date()
        guard let manager = asrManager, manager.isAvailable else {
            throw ASRError.modelNotLoaded
        }
        let result = try await manager.transcribe(audio, source: .microphone)
        return TranscriptionResult(
            text: result.text,
            confidence: result.confidence,
            processingTimeMs: Date().timeIntervalSince(start) * 1000,
            language: "en"
        )
    }
}
