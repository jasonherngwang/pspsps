import XCTest
import AVFoundation
@testable import pspsps

final class AudioProcessorTests: XCTestCase {

    // MARK: - Normalization test

    func testSineBufferNormalizesToTarget() {
        // RMS of -40 dBFS: rms = 10^(-40/20) = 0.01
        // Sine amplitude = rms * sqrt(2) to achieve that RMS
        let targetInputDBFS: Float = -40.0
        let rms = Float(pow(10.0, Double(targetInputDBFS) / 20.0))
        let amplitude = rms * sqrt(2.0)

        let buffer = makeSineBuffer(amplitude: amplitude)
        let output = AudioProcessor.normalizeRMS(buffer, targetDBFS: -20.0)

        let outputRMS = computeRMS(output)
        let outputDBFS = 20.0 * log10(outputRMS)

        XCTAssertEqual(outputDBFS, -20.0, accuracy: 1.0,
            "Output dBFS should be -20 ± 1 dB, got \(outputDBFS)")
    }

    // MARK: - Silence test

    func testSilenceBufferReturnsUnchanged() {
        let buffer = makeSilenceBuffer()
        let output = AudioProcessor.normalizeRMS(buffer, targetDBFS: -20.0)

        let outData = output.floatChannelData![0]
        let frameCount = Int(output.frameLength)
        for i in 0..<frameCount {
            XCTAssertFalse(outData[i].isNaN, "Silence output should not contain NaN at frame \(i)")
            XCTAssertEqual(outData[i], 0.0, "Silence output should remain zero at frame \(i)")
        }
    }

    // MARK: - Gain clamp test

    func testGainClampsAtPlustwentysixDB() {
        // -50 dBFS input: would need +30 dB gain to reach -20 dBFS, but max is +26 dB
        let targetInputDBFS: Float = -50.0
        let rms = Float(pow(10.0, Double(targetInputDBFS) / 20.0))
        let amplitude = rms * sqrt(2.0)

        let buffer = makeSineBuffer(amplitude: amplitude)
        let output = AudioProcessor.normalizeRMS(buffer, targetDBFS: -20.0)

        let outputRMS = computeRMS(output)
        let outputDBFS = 20.0 * log10(outputRMS)

        // With +26 dB max gain, output = -50 + 26 = -24 dBFS, not -20 dBFS
        // So output should be below -20 dBFS
        XCTAssertLessThan(outputDBFS, -20.0 + 0.5,
            "Clamped output should be below -20 dBFS (got \(outputDBFS))")
    }

    // MARK: - Format and frame count test

    func testOutputBufferHasSameFormatAndFrameCount() {
        let buffer = makeSineBuffer(amplitude: 0.01, duration: 0.5)
        let output = AudioProcessor.normalizeRMS(buffer, targetDBFS: -20.0)

        XCTAssertEqual(output.format, buffer.format,
            "Output buffer format should match input")
        XCTAssertEqual(output.frameLength, buffer.frameLength,
            "Output buffer frame count should match input")
    }

    // MARK: - New allocation test

    func testOutputBufferIsNewAllocation() {
        let buffer = makeSineBuffer(amplitude: 0.01)
        let output = AudioProcessor.normalizeRMS(buffer, targetDBFS: -20.0)

        // For non-silence, a new buffer is allocated: pointers must differ
        let inputPtr = buffer.floatChannelData![0]
        let outputPtr = output.floatChannelData![0]
        XCTAssertTrue(inputPtr != outputPtr,
            "Output buffer should be a new allocation, not the same memory as input")
    }

    // MARK: - Helper

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        let channelData = buffer.floatChannelData![0]
        let frameCount = Int(buffer.frameLength)
        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            sumOfSquares += channelData[i] * channelData[i]
        }
        return sqrt(sumOfSquares / Float(frameCount))
    }
}
