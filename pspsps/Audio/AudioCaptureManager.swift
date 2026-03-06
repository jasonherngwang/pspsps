import AVFoundation
import CoreAudio

final class AudioCaptureManager: AudioInputSource {

    let name = "System Audio Input"

    var deviceID: AudioDeviceID {
        AudioDeviceManager.resolvedInputDeviceID(preferredUID: AppConfig.current.audioInputDeviceUID)
    }

    private let engine = AVAudioEngine()
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []
    private let lock = NSLock()
    private var maxDurationTimer: Timer?
    private var isCapturing = false

    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Called when recording auto-stops due to max duration being reached.
    var onAutoStop: ((AVAudioPCMBuffer) -> Void)?

    func startCapture() throws {
        guard !isCapturing else { return }
        isCapturing = true

        lock.lock()
        accumulatedBuffers = []
        lock.unlock()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if let converted = self.convert(buffer, to: self.outputFormat) {
                self.lock.lock()
                self.accumulatedBuffers.append(converted)
                self.lock.unlock()
            }
        }

        try engine.start()

        let maxDuration = AppConfig.current.maxRecordingDurationSeconds
        let timer = Timer(timeInterval: maxDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            let buffer = self.stopCapture()
            self.onAutoStop?(buffer)
        }
        RunLoop.main.add(timer, forMode: .common)
        maxDurationTimer = timer
    }

    @discardableResult
    func stopCapture() -> AVAudioPCMBuffer {
        guard isCapturing else {
            return AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 0)!
        }
        isCapturing = false

        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let buffers = accumulatedBuffers
        accumulatedBuffers = []
        lock.unlock()

        return concatenate(buffers)
    }

    // MARK: - Private

    private func convert(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputConsumed = true
            return buffer
        }
        return error == nil ? output : nil
    }

    private func concatenate(_ buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer {
        let totalFrames = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard totalFrames > 0,
              let combined = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: totalFrames)
        else {
            return AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 0)!
        }
        combined.frameLength = totalFrames

        guard let dst = combined.floatChannelData?[0] else { return combined }
        var offset = 0
        for buf in buffers {
            guard let src = buf.floatChannelData?[0] else { continue }
            dst.advanced(by: offset).initialize(from: src, count: Int(buf.frameLength))
            offset += Int(buf.frameLength)
        }
        return combined
    }
}
