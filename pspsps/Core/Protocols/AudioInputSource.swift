import AVFoundation
import CoreAudio

protocol AudioInputSource: AnyObject {
    var name: String { get }
    var deviceID: AudioDeviceID { get }
    func startCapture() throws
    func stopCapture() -> AVAudioPCMBuffer
}
