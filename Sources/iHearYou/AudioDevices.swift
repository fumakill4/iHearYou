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
    let isAlive: Bool
    var isVirtual: Bool { transport == kAudioDeviceTransportTypeVirtual }
    var isOurMic: Bool { uid == "iHearYouMic_UID" }
    var isOurLoopback: Bool { ["iHearYouMic_UID", "iHearYouMic_2_UID"].contains(uid) }
    var connectionLabel: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "Bawaan Mac"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeContinuityCaptureWired: return "iPhone · USB"
        case kAudioDeviceTransportTypeContinuityCaptureWireless: return "iPhone · Nirkabel"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        default: return ""
        }
    }
    var selectionLabel: String { connectionLabel.isEmpty ? name : "\(name) · \(connectionLabel)" }
}

extension Array where Element == AudioDevice {
    // A driver can expose real hardware through a software transport. Channel
    // capability and liveness determine usability; never feed our own output back in.
    var inputCandidates: [AudioDevice] { filter { $0.isAlive && $0.inputChannels > 0 && !$0.isOurLoopback } }
    var outputCandidates: [AudioDevice] { filter { $0.isAlive && $0.outputChannels > 0 && !$0.isOurLoopback } }
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
    static func isPrivateAggregate(_ id: AudioDeviceID) -> Bool {
        guard number(id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeAggregate else { return false }
        var a = address(kAudioAggregateDevicePropertyComposition), value: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let value else { return false }
        let composition = value.takeRetainedValue() as NSDictionary
        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue == true
    }
    static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope), size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 {
            let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { memory.deallocate() }
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, memory) == noErr {
                let count = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
                    .reduce(0) { $0 + Int($1.mNumberChannels) }
                if count > 0 { return count }
            }
        }
        // Some external devices advertise streams before configuring their idle
        // buffers. Read actual stream formats; an absent output remains absent.
        a = address(kAudioDevicePropertyStreams, scope); size = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &streams) == noErr else { return 0 }
        return streams.reduce(0) { total, stream in
            var property = address(kAudioStreamPropertyVirtualFormat)
            var format = AudioStreamBasicDescription(), bytes = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            guard AudioObjectGetPropertyData(stream, &property, 0, nil, &bytes, &format) == noErr else { return total }
            return total + Int(format.mChannelsPerFrame)
        }
    }
    static func list() -> [AudioDevice] {
        var a = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        // AVAudioEngine creates private clock-management aggregates. They are
        // implementation devices, not extra microphones for the user to select.
        return ids.filter { number($0, kAudioDevicePropertyIsHidden) == 0 && !isPrivateAggregate($0) }
            .map { AudioDevice(id: $0, uid: string($0, kAudioDevicePropertyDeviceUID), name: string($0, kAudioObjectPropertyName),
                                    inputChannels: channels($0, kAudioDevicePropertyScopeInput), outputChannels: channels($0, kAudioDevicePropertyScopeOutput),
                                    transport: number($0, kAudioDevicePropertyTransportType),
                                    isAlive: number($0, kAudioDevicePropertyDeviceIsAlive) != 0) }.filter { !$0.name.isEmpty }
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
