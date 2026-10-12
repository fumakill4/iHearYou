// iHearYou | Signature: i729
import AudioToolbox
import AudioDSP
import Foundation

// AUHAL writes directly to our fixed-rate driver without changing system output.
final class VirtualOutput {
    private var unit: AudioUnit?
    private let processor: OpaquePointer
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 16384)
    init(device: AudioDevice, processor: OpaquePointer) throws {
        self.processor = processor
        scratch.initialize(repeating: 0, count: 16384)
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw AudioFailure.message(L("CoreAudio output unavailable.", "CoreAudio output tidak tersedia.")) }
        try check(AudioComponentInstanceNew(component, &unit))
        guard let unit else { throw AudioFailure.message(L("Virtual microphone output unavailable.", "Output mikrofon virtual tidak tersedia.")) }
        do {
            var enable: UInt32 = 1, disable: UInt32 = 0
            try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, 4))
            try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disable, 4))
            try AudioDevices.setDevice(unit, id: device.id)
            var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
                mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
            try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
            var callback = AURenderCallbackStruct(inputProc: { context, _, _, _, count, list in
                guard let list else { return kAudio_ParamError }
                let output = Unmanaged<VirtualOutput>.fromOpaque(context).takeUnretainedValue()
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                guard count <= 16384 else {
                    for buffer in buffers { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
                    return kAudio_ParamError
                }
                ih_render(output.processor, output.scratch, count, 0)
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let channels = Int(buffer.mNumberChannels)
                    for i in 0..<Int(count) {
                        for channel in 0..<channels { data[i * channels + channel] = output.scratch[i] }
                    }
                }
                return noErr
            }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            try check(AudioUnitInitialize(unit))
            try check(AudioOutputUnitStart(unit))
        } catch { stop(); throw error }
    }
    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioFailure.message(L("Virtual microphone output failed (\(status)). Refresh Devices and try again.", "Output mikrofon virtual gagal (\(status)). Muat ulang perangkat lalu coba lagi.")) }
    }
    func stop() {
        if let unit { AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }
        unit = nil
    }
    deinit { stop(); scratch.deinitialize(count: 16384); scratch.deallocate() }
}
