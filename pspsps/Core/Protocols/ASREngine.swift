import AVFoundation

protocol ASREngine: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    func loadModel() async throws
    func unloadModel()
    func transcribe(audio: AVAudioPCMBuffer) async throws -> TranscriptionResult
}
