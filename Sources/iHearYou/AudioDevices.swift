// iHearYou | Signature: i729
import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let transport: UInt32
    var isVirtual: Bool { transport == kAudioDeviceTransportTypeVirtual || name.lowercased().contains("ihearyou") }
    var isOurMic: Bool { uid == "iHearYouMic_UID" }
}

enum AudioDevices {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector), value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }
    static func number(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var a = address(selector), value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
        return value
    }
    static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    static func list() -> [AudioDevice] {
        var a = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { AudioDevice(id: $0, uid: string($0, kAudioDevicePropertyDeviceUID), name: string($0, kAudioObjectPropertyName),
                                    inputChannels: channels($0, kAudioDevicePropertyScopeInput), outputChannels: channels($0, kAudioDevicePropertyScopeOutput),
                                    transport: number($0, kAudioDevicePropertyTransportType)) }.filter { !$0.name.isEmpty }
    }
    static var defaultInput: AudioDeviceID { number(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) }
    static var defaultOutput: AudioDeviceID { number(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) }
    static func setDevice(_ unit: AudioUnit?, id: AudioDeviceID) throws {
        guard let unit else { throw AudioFailure.message("Audio unit tidak tersedia.") }
        var device = id
        let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard result == noErr else { throw AudioFailure.message("Perangkat audio tidak bisa dibuka (\(result)). Coba perangkat lain.") }
    }
}

enum AudioFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
