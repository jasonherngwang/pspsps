import AVFoundation
import OSLog

@MainActor
final class TranscriptionPipeline {

    let asrEngine: any ASREngine
    let postProcessor: any PostProcessor
    private let config: AppConfig
    private var currentTask: Task<String, Error>?
    private static let logger = Logger(subsystem: "com.pspsps.pspsps", category: "Pipeline")

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
    func run(
        buffer: AVAudioPCMBuffer,
        activeApp: String? = nil,
        activeAppBundleID: String? = nil
    ) async throws -> String {
        currentTask?.cancel()

        let task = Task { [asrEngine, postProcessor, config, buffer] in
            let t0 = CFAbsoluteTimeGetCurrent()

            let normalized: AVAudioPCMBuffer
            if config.gainNormalizationEnabled {
                normalized = AudioProcessor.normalizeRMS(buffer, targetDBFS: config.gainTargetDBFS)
            } else {
                normalized = buffer
            }

            try Task.checkCancellation()

            let t1 = CFAbsoluteTimeGetCurrent()
            let result = try await asrEngine.transcribe(audio: normalized)
            let t2 = CFAbsoluteTimeGetCurrent()

            try Task.checkCancellation()

            let context = PostProcessContext(
                activeApp: activeApp,
                activeAppBundleID: activeAppBundleID,
                previousTranscript: nil,
                timestamp: Date()
            )
            let cleaned = try await postProcessor.clean(transcript: result.text, context: context)
            let t3 = CFAbsoluteTimeGetCurrent()

            Self.logger.info("Pipeline: normalize=\(Int((t1-t0)*1000))ms asr=\(Int((t2-t1)*1000))ms post=\(Int((t3-t2)*1000))ms total=\(Int((t3-t0)*1000))ms")

            return cleaned
        }

        currentTask = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
