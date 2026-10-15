// iHearYou | Signature: i729
import AVFoundation
import AudioDSP
import AudioSafety
import CoreAudio
import Foundation

struct AudioSnapshot {
    let stats: IHStats
    let recordingSeconds: Double
    let isRecording: Bool
    let recordingError: String?
}

// Each callback retains this owner until the audio unit/engine releases it.
// Cancelling a timer alone does not prove its last queued callback has finished.
final class DSPContext {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { ih_destroy(pointer) }
}

func guardedAudio(_ operation: () -> Void) throws {
    var failure: NSError?
    guard IHPerformAudioOperation(operation, &failure) else {
        throw failure ?? NSError(domain: "com.i729.iHearYou.audio", code: 1)
    }
}

final class AudioSession {
    private let queue = DispatchQueue(label: "com.i729.iHearYou.audio", qos: .userInteractive)
    private var queueContext: DSPContext?
    private var context: DSPContext?
    private var processor: OpaquePointer? { context?.pointer }
    private var hardwareCapture: HardwareCapture?
    private var captureEngine: AVAudioEngine?
    private var virtualOutput: VirtualOutput?
    private var monitorOutput: VirtualOutput?
    private var timer: DispatchSourceTimer?
    private var writer: RecordingWriter?
    private var finishing: [(writer: RecordingWriter, frames: Int)] = []
    private var recordingError: String?
    private var raw = [Float](repeating: 0, count: 480)
    private var clean = [Float](repeating: 0, count: 480)
    private var notifications: [NSObjectProtocol] = []
    var onDeviceFailure: ((String) -> Void)?
    // Processed mono PCM at 48 kHz, invoked on the bounded inference queue.
    // A receiver must copy into its own bounded mailbox and return promptly.
    var onProcessedAudio: (([Float]) -> Void)?

    func start(input: AudioDevice, virtual: AudioDevice?, monitor: AudioDevice?, enabled: Bool, strength: Float, gain: Float, gate: Bool) throws {
        stop()
        let bluetooth = input.transport == kAudioDeviceTransportTypeBluetooth || input.transport == kAudioDeviceTransportTypeBluetoothLE
        let hardware = bluetooth ? try HardwareCapture(device: input) : nil
        let engine = bluetooth ? nil : AVAudioEngine()
        var hardwareFormat: AVAudioFormat? = hardware?.format
        if let engine {
            var inputUnit: AudioUnit?
            try guardedAudio { inputUnit = engine.inputNode.audioUnit }
            try AudioDevices.setDevice(inputUnit, id: input.id)
            // macOS voice processing cancels acoustic speaker echo. Do not force
            // a second headset profile switch or AGC on Bluetooth microphones.
            if enabled && input.transport == kAudioDeviceTransportTypeBuiltIn {
                let output = AudioDevices.list().outputCandidates.first { $0.id == AudioDevices.defaultOutput }
                if let output, !output.isVirtual,
                   output.transport != kAudioDeviceTransportTypeBluetooth,
                   output.transport != kAudioDeviceTransportTypeBluetoothLE {
                    var voiceError: Error?
                    try guardedAudio {
                        do { try engine.inputNode.setVoiceProcessingEnabled(true) }
                        catch { voiceError = error }
                    }
                    if let voiceError { throw voiceError }
                    engine.inputNode.isVoiceProcessingAGCEnabled = false
                }
            }
            try guardedAudio { hardwareFormat = engine.inputNode.outputFormat(forBus: 0) }
        }
        guard let format = hardwareFormat else {
            throw AudioFailure.message(L("Microphone format unavailable. Reconnect the device.", "Format mikrofon belum tersedia. Sambungkan ulang perangkat."))
        }
        guard let modelURL = Bundle.main.url(forResource: bluetooth ? "dpdfnet2" : "dpdfnet2_48khz_hr", withExtension: "onnx") else {
            throw AudioFailure.message(L("Noise reduction model missing. Open iHearYou from the complete app bundle.", "Model peredaman tidak ditemukan. Jalankan iHearYou dari bundle aplikasi lengkap."))
        }
        guard let vadURL = Bundle.main.url(forResource: "silero_vad", withExtension: "onnx") else {
            throw AudioFailure.message(L("Speech detection model missing. Reinstall the complete iHearYou app.", "Model deteksi ucapan tidak ditemukan. Pasang ulang aplikasi iHearYou lengkap."))
        }
        let headsetModel = Bundle.main.url(forResource: "gtcrn_simple", withExtension: "onnx")
        guard !bluetooth || headsetModel != nil else {
            throw AudioFailure.message(L("Headset model missing. Reinstall iHearYou.", "Model headset tidak ditemukan. Pasang ulang iHearYou."))
        }
        guard format.sampleRate.isFinite, format.sampleRate >= 8000, format.sampleRate <= 192000,
              format.channelCount > 0, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              let p = bluetooth ? ih_create_headset(format.sampleRate, modelURL.path, headsetModel!.path, vadURL.path)
                                : ih_create(format.sampleRate, modelURL.path, vadURL.path) else {
            throw AudioFailure.message(L("Unsupported microphone format. Select another microphone.", "Format mikrofon tidak didukung. Pilih mikrofon lain."))
        }
        let owner = DSPContext(p)
        context = owner
        queue.sync { queueContext = owner }
        ih_settings(p, enabled ? 1 : 0, strength, gain, gate ? 1 : 0)
        captureEngine = engine; hardwareCapture = hardware
        do {
            if let virtual { virtualOutput = try VirtualOutput(device: virtual, context: owner) }
            if let monitor {
                guard !monitor.isOurLoopback else { throw AudioFailure.message(L("Select an output other than the iHearYou virtual microphone to avoid feedback.", "Pilih output selain mikrofon virtual iHearYou agar tidak terjadi feedback.")) }
                monitorOutput = try VirtualOutput(device: monitor, context: owner, monitor: true)
                monitorOutput?.onConfigurationChange = { [weak self, weak owner] in
                    guard let self, let owner, self.context === owner else { return }
                    self.onDeviceFailure?(L("Headphone audio format changed. Reconnecting…", "Format audio headphone berubah. Menyambungkan ulang…"))
                }
            }
            if let hardware {
                hardware.onConfigurationChange = { [weak self, weak owner] in
                    guard let self, let owner, self.context === owner else { return }
                    self.onDeviceFailure?(L("Bluetooth audio format changed. Reconnecting…", "Format audio Bluetooth berubah. Menyambungkan ulang…"))
                }
                try hardware.start(context: owner)
            } else if let engine {
                try guardedAudio {
                    engine.inputNode.installTap(onBus: 0, bufferSize: 960, format: nil) { [owner] buffer, _ in
                        guard let samples = buffer.floatChannelData?[0] else { return }
                        ih_capture(owner.pointer, samples, buffer.frameLength)
                    }
                    engine.prepare()
                }
                var startError: Error?
                try guardedAudio { do { try engine.start() } catch { startError = error } }
                if let startError { throw startError }
                let negotiated = engine.inputNode.outputFormat(forBus: 0)
                guard negotiated.sampleRate == format.sampleRate, negotiated.channelCount == format.channelCount else {
                    throw AudioFailure.message(L("Microphone format is settling. Try starting again.", "Format mikrofon sedang disesuaikan. Coba aktifkan kembali."))
                }
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            let virtualEnabled = virtual != nil, monitorEnabled = monitor != nil
            timer.setEventHandler { [weak self, owner] in
                guard let self, self.queueContext === owner else { return }
                self.process(owner.pointer, virtualEnabled: virtualEnabled, monitorEnabled: monitorEnabled)
            }
            timer.resume()
            for observed in [captureEngine].compactMap({ $0 }) {
                notifications.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: observed, queue: .main) { [weak self, weak owner] _ in
                    Task { @MainActor [weak self, weak owner] in
                        guard let self, let owner, self.context === owner else { return }
                        self.onDeviceFailure?(L("Audio device format changed. Reconnecting microphone…", "Format perangkat audio berubah. Menyambungkan ulang mikrofon…"))
                    }
                })
            }
        } catch { stop(); throw error }
    }

    private func process(_ p: OpaquePointer, virtualEnabled: Bool, monitorEnabled: Bool) {
        // Bound each event so meter reads and stop requests cannot starve during overload.
        for _ in 0..<8 {
            guard ih_next_frame(p, &raw, &clean) != 0 else { break }
            ih_publish(p, &clean, virtualEnabled ? 1 : 0, monitorEnabled ? 1 : 0)
            onProcessedAudio?(clean)
            if let writer {
                do { try writer.write(original: raw, processed: clean) }
                catch {
                    writer.close(); self.writer = nil
                    recordingError = L("Recording stopped: \(error.localizedDescription)", "Rekaman dihentikan: \(error.localizedDescription)")
                }
            }
            for index in finishing.indices.reversed() {
                do { try finishing[index].writer.write(original: raw, processed: clean) }
                catch { recordingError = error.localizedDescription; finishing[index].frames = 1 }
                finishing[index].frames -= 1
                if finishing[index].frames <= 0 { finishing[index].writer.close(); finishing.remove(at: index) }
            }
        }
    }
    func configure(enabled: Bool, strength: Float, gain: Float, gate: Bool) {
        if let processor { ih_settings(processor, enabled ? 1 : 0, strength, gain, gate ? 1 : 0) }
        try? guardedAudio {
            if let input = captureEngine?.inputNode, input.isVoiceProcessingEnabled {
                input.isVoiceProcessingBypassed = !enabled
            }
        }
    }
    func snapshot() -> AudioSnapshot? {
        guard let processor else { return nil }
        let stats = ih_stats(processor)
        return queue.sync { AudioSnapshot(stats: stats, recordingSeconds: Double(writer?.frames ?? 0) / 48000,
                                          isRecording: writer != nil, recordingError: recordingError) }
    }
    func startRecording() throws {
        guard processor != nil else { throw AudioFailure.message(L("Start the microphone before recording.", "Aktifkan mikrofon sebelum merekam.")) }
        try queue.sync { recordingError = nil; writer = try RecordingWriter() }
    }
    @discardableResult func stopRecording() -> URL? {
        queue.sync {
            guard let writer else { return nil }
            // Keep the last word: processed audio trails the physical input.
            finishing.append((writer, Int((ih_delay_samples() + 479) / 480) + 1))
            if finishing.count > 4 { finishing.removeFirst().writer.close() }
            self.writer = nil
            return writer.cleanURL
        }
    }
    func stop() {
        notifications.forEach(NotificationCenter.default.removeObserver); notifications = []
        hardwareCapture?.stop()
        try? guardedAudio {
            captureEngine?.stop()
            captureEngine?.inputNode.removeTap(onBus: 0)
        }
        // Retained DSPContext owners also protect queued/in-flight callbacks.
        virtualOutput?.stop(); monitorOutput?.stop()
        timer?.setEventHandler {}; timer?.cancel(); timer = nil
        queue.sync {
            queueContext = nil
            if let processor, writer != nil || !finishing.isEmpty {
                // Producers are stopped, so drain their backlog and the model /
                // pre-roll delay before closing WAV headers. No render-thread I/O.
                for _ in 0..<4 { process(processor, virtualEnabled: false, monitorEnabled: false) }
                for _ in 0..<Int((ih_delay_samples() + 479) / 480) + 2 {
                    ih_pad_silence(processor)
                    process(processor, virtualEnabled: false, monitorEnabled: false)
                }
            }
            writer?.close(); writer = nil
            finishing.forEach { $0.writer.close() }; finishing.removeAll()
        }
        hardwareCapture = nil; captureEngine = nil; virtualOutput = nil; monitorOutput = nil
        context = nil; recordingError = nil
    }
    deinit { stop() }
}
