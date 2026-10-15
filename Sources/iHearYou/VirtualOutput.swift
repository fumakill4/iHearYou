// iHearYou | Signature: i729
import AudioToolbox
import AudioDSP
import Foundation
import CoreAudio

// AUHAL writes directly to our fixed-rate driver without changing system output.
final class VirtualOutput {
    private var unit: AudioUnit?
    private var deviceID: AudioDeviceID = 0
    private var listener: AudioObjectPropertyListenerBlock?
    private var sampleRate = 48000.0
    private var monitorLane = false
    var onConfigurationChange: (() -> Void)?
    private let context: DSPContext
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 16384)
    init(device: AudioDevice, context: DSPContext, monitor: Bool = false) throws {
        self.context = context
        deviceID = device.id; monitorLane = monitor
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
            var native = AudioStreamBasicDescription(), bytes = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &native, &bytes))
            sampleRate = monitor ? native.mSampleRate : 48000
            guard sampleRate.isFinite, sampleRate >= 8000, sampleRate <= 192000 else {
                throw AudioFailure.message(L("Speaker format unavailable. Reconnect your headphones.", "Format speaker tidak tersedia. Sambungkan ulang headphone."))
            }
            let channels: UInt32 = monitor ? min(2, max(1, native.mChannelsPerFrame)) : 2
            var format = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked, mBytesPerPacket: channels * 4, mFramesPerPacket: 1,
                mBytesPerFrame: channels * 4, mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
            try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
            var maxFrames: UInt32 = 16384
            try check(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, 4))
            var callback = AURenderCallbackStruct(inputProc: { context, _, _, _, count, list in
                guard let list else { return kAudio_ParamError }
                let output = Unmanaged<VirtualOutput>.fromOpaque(context).takeUnretainedValue()
                let buffers = UnsafeMutableAudioBufferListPointer(list)
                guard count <= 16384 else {
                    for buffer in buffers { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
                    return kAudio_ParamError
                }
                ih_render_rate(output.context.pointer, output.scratch, count, output.monitorLane ? 1 : 0, output.sampleRate)
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let channels = Int(buffer.mNumberChannels)
                    guard UInt64(count) * UInt64(channels) * 4 <= UInt64(buffer.mDataByteSize) else {
                        memset(data, 0, Int(buffer.mDataByteSize)); continue
                    }
                    for i in 0..<Int(count) {
                        for channel in 0..<channels { data[i * channels + channel] = output.scratch[i] }
                    }
                }
                return noErr
            }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            try check(AudioUnitInitialize(unit))
            try check(AudioOutputUnitStart(unit))
            if monitor {
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.onConfigurationChange?() }
                }
                self.listener = listener
                for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                    var address = AudioDevices.address(selector)
                    AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, listener)
                }
            }
        } catch { stop(); throw error }
    }
    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioFailure.message(L("Virtual microphone output failed (\(status)). Refresh Devices and try again.", "Output mikrofon virtual gagal (\(status)). Muat ulang perangkat lalu coba lagi.")) }
    }
    func stop() {
        if let listener {
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                var address = AudioDevices.address(selector)
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, listener)
            }
        }
        listener = nil
        if let unit { AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }
        unit = nil
    }
    deinit { stop(); scratch.deinitialize(count: 16384); scratch.deallocate() }
}
