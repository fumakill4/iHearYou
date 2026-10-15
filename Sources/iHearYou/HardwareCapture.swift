// iHearYou | Signature: i729
import AVFoundation
import AudioToolbox
import CoreAudio
import AudioDSP

// Input-only AUHAL for Bluetooth. AVAudioEngine can retain an output graph at
// 48 kHz while AirPods negotiate their headset profile at another rate.
final class HardwareCapture {
    private var unit: AudioUnit?
    private var context: DSPContext?
    private let device: AudioDeviceID
    let format: AVAudioFormat
    private let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 16384)
    private var listener: AudioObjectPropertyListenerBlock?
    var onConfigurationChange: (() -> Void)?

    init(device: AudioDevice) throws {
        self.device = device.id
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            scratch.deallocate()
            throw AudioFailure.message(L("Microphone capture unavailable.", "Perekaman mikrofon tidak tersedia."))
        }
        var created: AudioUnit?
        let status = AudioComponentInstanceNew(component, &created)
        guard status == noErr, let created else {
            scratch.deallocate()
            throw AudioFailure.message("Microphone initialization failed (\(status)).")
        }
        var native = AudioStreamBasicDescription()
        do {
            var on: UInt32 = 1, off: UInt32 = 0
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4))
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, 4))
            try AudioDevices.setDevice(created, id: device.id)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(AudioUnitGetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &native, &size))
            guard native.mSampleRate.isFinite, native.mSampleRate >= 8000, native.mSampleRate <= 192000,
                  native.mChannelsPerFrame > 0 else { throw AudioFailure.message(L("Bluetooth microphone is still connecting. Try again.", "Mikrofon Bluetooth masih tersambung. Coba lagi.")) }
            var client = AudioStreamBasicDescription(mSampleRate: native.mSampleRate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
            try Self.check(AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, size))
            var channel: Int32 = 0
            try Self.check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1, &channel, 4))
            var maxFrames: UInt32 = 16384
            try Self.check(AudioUnitSetProperty(created, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, 4))
        } catch {
            AudioComponentInstanceDispose(created); scratch.deallocate(); throw error
        }
        format = AVAudioFormat(standardFormatWithSampleRate: native.mSampleRate, channels: 1)!
        unit = created
        scratch.initialize(repeating: 0, count: 16384)
    }
    func start(context: DSPContext) throws {
        guard let unit else { return }
        self.context = context
        var callback = AURenderCallbackStruct(inputProc: { raw, flags, timestamp, _, count, _ in
            let capture = Unmanaged<HardwareCapture>.fromOpaque(raw).takeUnretainedValue()
            guard count <= 16384, let unit = capture.unit, let context = capture.context else { return kAudio_ParamError }
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1,
                mDataByteSize: count * 4, mData: capture.scratch))
            let result = AudioUnitRender(unit, flags, timestamp, 1, count, &list)
            if result == noErr { ih_capture(context.pointer, capture.scratch, count) }
            return result
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try Self.check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
            &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
        try Self.check(AudioUnitInitialize(unit))
        try Self.check(AudioOutputUnitStart(unit))
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.onConfigurationChange?() }
        }
        self.listener = listener
        for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
            var address = AudioDevices.address(selector)
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
    }
    func stop() {
        if let listener {
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                var address = AudioDevices.address(selector)
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            }
        }
        listener = nil
        if let unit { AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }
        unit = nil; context = nil
    }
    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw AudioFailure.message(L("Bluetooth microphone setup failed (\(status)). Reconnect the headset and try again.", "Mikrofon Bluetooth gagal disiapkan (\(status)). Sambungkan ulang headset lalu coba lagi."))
        }
    }
    deinit { stop(); scratch.deinitialize(count: 16384); scratch.deallocate() }
}
