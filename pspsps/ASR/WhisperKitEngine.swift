import AVFoundation
import WhisperKit

class WhisperKitEngine: ASREngine {
    let name = "WhisperKit"
    private var whisperKit: WhisperKit?

    var isAvailable: Bool { whisperKit != nil }

    func loadModel() async throws {
        // model: nil → WhisperKit selects the recommended model for this device
        whisperKit = try await WhisperKit(
            model: nil,
            downloadBase: Self.modelDirectory,
            computeOptions: ModelComputeOptions(
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )
        )
    }

    func unloadModel() {
        whisperKit = nil
    }

    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        let start = Date()
        guard let wk = whisperKit else { throw ASRError.modelNotLoaded }
        let floatArray = Self.toFloatArray(audio)
        // Let Swift infer the return type to avoid name collision with our TranscriptionResult struct
        let results = try await wk.transcribe(audioArray: floatArray)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let language = results.first?.language
        return TranscriptionResult(
            text: text,
            confidence: nil,
            processingTimeMs: Date().timeIntervalSince(start) * 1000,
            language: language
        )
    }

    static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("pspsps/models/whisperkit", isDirectory: true)
    }

    private static func toFloatArray(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?.pointee else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
}
