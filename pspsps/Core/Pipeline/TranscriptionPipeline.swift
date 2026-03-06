import AVFoundation

@MainActor
final class TranscriptionPipeline {

    let asrEngine: any ASREngine
    let postProcessor: any PostProcessor
    private let config: AppConfig
    private var currentTask: Task<String, Error>?

    init(
        asrEngine: any ASREngine,
        postProcessor: any PostProcessor,
        config: AppConfig = .current
    ) {
        self.asrEngine = asrEngine
        self.postProcessor = postProcessor
        self.config = config
    }

    /// Cancels any in-flight transcription, then normalizes the audio, transcribes,
    /// and post-processes, returning the cleaned transcript text.
    func run(buffer: AVAudioPCMBuffer) async throws -> String {
        currentTask?.cancel()

        let task = Task { [asrEngine, postProcessor, config, buffer] in
            let normalized: AVAudioPCMBuffer
            if config.gainNormalizationEnabled {
                normalized = AudioProcessor.normalizeRMS(buffer, targetDBFS: config.gainTargetDBFS)
            } else {
                normalized = buffer
            }

            try Task.checkCancellation()

            let result = try await asrEngine.transcribe(audio: normalized)

            try Task.checkCancellation()

            let context = PostProcessContext(
                activeApp: nil,
                activeAppBundleID: nil,
                previousTranscript: nil,
                timestamp: Date()
            )
            return try await postProcessor.clean(transcript: result.text, context: context)
        }

        currentTask = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
