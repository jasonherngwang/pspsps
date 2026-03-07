import AVFoundation
import FluidAudio

final class ParakeetEngine: ASREngine {
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

    /// Parakeet / FluidAudio requires at least 16,000 samples (1s at 16 kHz).
    /// Pad short buffers with silence so brief recordings still get processed.
    private static let minimumFrames: AVAudioFrameCount = 16_000

    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        let start = Date()
        guard let manager = asrManager, manager.isAvailable else {
            throw ASRError.modelNotLoaded
        }
        let paddedAudio = Self.padIfNeeded(audio)
        let result = try await manager.transcribe(paddedAudio, source: .microphone)
        return TranscriptionResult(
            text: result.text,
            confidence: result.confidence,
            processingTimeMs: Date().timeIntervalSince(start) * 1000,
            language: "en"
        )
    }

    private static func padIfNeeded(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard buffer.frameLength < minimumFrames else { return buffer }
        guard let padded = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: minimumFrames) else {
            return buffer
        }
        padded.frameLength = minimumFrames

        // Copy existing audio
        if let src = buffer.floatChannelData, let dst = padded.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                dst[ch].initialize(from: src[ch], count: Int(buffer.frameLength))
                // Zero-fill the rest (silence)
                dst[ch].advanced(by: Int(buffer.frameLength))
                    .initialize(repeating: 0, count: Int(minimumFrames - buffer.frameLength))
            }
        }
        return padded
    }
}
