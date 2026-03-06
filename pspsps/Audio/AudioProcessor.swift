import AVFoundation

struct AudioProcessor {
    static func normalizeRMS(
        _ buffer: AVAudioPCMBuffer,
        targetDBFS: Float = -20.0
    ) -> AVAudioPCMBuffer {
        guard let channelData = buffer.floatChannelData?[0] else { return buffer }
        let frameCount = Int(buffer.frameLength)

        // Compute RMS
        var sumOfSquares: Float = 0
        for i in 0..<frameCount {
            sumOfSquares += channelData[i] * channelData[i]
        }
        let rms = sqrt(sumOfSquares / Float(frameCount))
        guard rms > 1e-8 else { return buffer }  // pure silence, skip

        // Compute gain
        let currentDBFS = 20 * log10(rms)
        let gainDB = targetDBFS - currentDBFS
        let gainLinear = pow(10.0, gainDB / 20.0)
        let clampedGain = min(gainLinear, 20.0)  // cap at +26dB to prevent clipping

        // Apply gain to a new buffer (do not mutate the input)
        let format = buffer.format
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength)!
        output.frameLength = buffer.frameLength
        let outData = output.floatChannelData![0]
        for i in 0..<frameCount {
            outData[i] = channelData[i] * clampedGain
        }
        return output
    }
}
