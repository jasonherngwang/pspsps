import Foundation

@MainActor
struct PipelineFactory {

    static func build(from config: AppConfig = .current) -> TranscriptionPipeline {
        let asrEngine: any ASREngine
        switch config.asrEngine {
        case .whisperKit:
            asrEngine = WhisperKitEngine()
        case .parakeet:
            // ParakeetEngine will be implemented in Issue 16
            asrEngine = WhisperKitEngine()
        }

        let postProcessor: any PostProcessor
        switch config.postProcessor {
        case .passthrough:
            postProcessor = PassthroughPostProcessor()
        case .ollama:
            // OllamaPostProcessor will be implemented in Issue 15
            postProcessor = PassthroughPostProcessor()
        }

        return TranscriptionPipeline(asrEngine: asrEngine, postProcessor: postProcessor, config: config)
    }
}
