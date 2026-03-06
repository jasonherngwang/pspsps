import AVFoundation

func makeSineBuffer(
    frequency: Float = 440,
    amplitude: Float = 0.1,
    duration: Float = 1.0,
    sampleRate: Double = 16000
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * Double(duration))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    let data = buffer.floatChannelData![0]
    for i in 0..<Int(frameCount) {
        data[i] = amplitude * sin(2.0 * .pi * frequency * Float(i) / Float(sampleRate))
    }
    return buffer
}

func makeSilenceBuffer(
    duration: Float = 1.0,
    sampleRate: Double = 16000
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCount = AVAudioFrameCount(sampleRate * Double(duration))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    // floatChannelData is already zeroed on allocation
    return buffer
}
