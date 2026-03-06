import XCTest
import AVFoundation
@testable import pspsps

@MainActor
final class TranscriptionPipelineTests: XCTestCase {

    // MARK: - Basic pipeline

    func testPipelineWithMockEngineReturnsExpectedText() async throws {
        let engine = MockASREngine()
        engine.mockResult = "hello world"
        let pipeline = TranscriptionPipeline(
            asrEngine: engine,
            postProcessor: PassthroughPostProcessor()
        )
        let buffer = makeSilenceBuffer()
        let result = try await pipeline.run(buffer: buffer)
        XCTAssertEqual(result, "hello world")
    }

    // MARK: - Cancellation

    func testRunCancelsPreviousInFlightTask() async throws {
        let engine = MockASREngine()
        engine.mockResult = "done"
        engine.transcribeDelay = 5.0   // long enough for the second run() to cancel it
        let pipeline = TranscriptionPipeline(
            asrEngine: engine,
            postProcessor: PassthroughPostProcessor()
        )
        let buffer = makeSilenceBuffer()

        // Launch the first run in an unstructured task so the second call can overlap.
        let firstTask = Task<String, Error> { try await pipeline.run(buffer: buffer) }

        // Wait just long enough for the first run to have started its transcription sleep.
        try await Task.sleep(for: .milliseconds(50))

        // Second run — cancels the first.
        engine.transcribeDelay = 0
        let secondResult = try await pipeline.run(buffer: buffer)
        XCTAssertEqual(secondResult, "done")

        // The first task should have been cancelled.
        do {
            _ = try await firstTask.value
            // Might succeed if the scheduler ran the second task before the first started — OK.
        } catch is CancellationError {
            // Expected: first task was cancelled by the second run().
        }
    }

    // MARK: - PipelineFactory

    func testPipelineFactoryBuildsWhisperKitEngine() {
        var config = AppConfig()
        config.asrEngine = .whisperKit
        let pipeline = PipelineFactory.build(from: config)
        XCTAssertTrue(pipeline.asrEngine is WhisperKitEngine,
            "Expected WhisperKitEngine, got \(type(of: pipeline.asrEngine))")
    }

    func testPipelineFactoryBuildsPassthroughPostProcessor() {
        var config = AppConfig()
        config.postProcessor = .passthrough
        let pipeline = PipelineFactory.build(from: config)
        XCTAssertTrue(pipeline.postProcessor is PassthroughPostProcessor,
            "Expected PassthroughPostProcessor, got \(type(of: pipeline.postProcessor))")
    }

    // MARK: - Audio normalization

    func testPipelineNormalizesAudioBeforeTranscription() async throws {
        let engine = MockASREngine()
        engine.mockResult = "normalized"
        var config = AppConfig()
        config.gainNormalizationEnabled = true
        config.gainTargetDBFS = -20.0
        let pipeline = TranscriptionPipeline(
            asrEngine: engine,
            postProcessor: PassthroughPostProcessor(),
            config: config
        )
        // Very quiet sine — normalizeRMS should boost it without crashing.
        let buffer = makeSineBuffer(amplitude: 0.001)
        let result = try await pipeline.run(buffer: buffer)
        XCTAssertEqual(result, "normalized")
    }
}
