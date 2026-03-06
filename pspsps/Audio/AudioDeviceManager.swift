import CoreAudio
import Foundation

struct AudioDeviceInfo: Sendable {
    let deviceID: AudioDeviceID
    let name: String
    let uid: String
}

struct AudioDeviceManager {

    /// All available audio input devices on the system.
    static func availableInputDevices() -> [AudioDeviceInfo] {
        getAllDeviceIDs().compactMap { id in
            guard hasInputChannels(id),
                  let name = getName(id),
                  let uid = getUID(id)
            else { return nil }
            return AudioDeviceInfo(deviceID: id, name: name, uid: uid)
        }
    }

    /// The system default input device ID.
    static func systemDefaultInputDeviceID() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    /// Returns the device ID matching the given UID, or the system default if not found.
    static func resolvedInputDeviceID(preferredUID: String?) -> AudioDeviceID {
        if let uid = preferredUID,
           let match = availableInputDevices().first(where: { $0.uid == uid }) {
            return match.deviceID
        }
        return systemDefaultInputDeviceID()
    }

    // MARK: - Private helpers

    private static func getAllDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0
        else { return false }

        let bufferList = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, bufferList) == noErr
        else { return false }

        let abl = bufferList.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeBufferPointer(
            start: &abl.pointee.mBuffers,
            count: Int(abl.pointee.mNumberBuffers))
        return buffers.contains(where: { $0.mNumberChannels > 0 })
    }

    private static func getName(_ id: AudioDeviceID) -> String? {
        cfStringProperty(id, selector: kAudioObjectPropertyName)
    }

    private static func getUID(_ id: AudioDeviceID) -> String? {
        cfStringProperty(id, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func cfStringProperty(
        _ id: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var cfStr: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfStr)
        return status == noErr ? (cfStr as String) : nil
    }
}
