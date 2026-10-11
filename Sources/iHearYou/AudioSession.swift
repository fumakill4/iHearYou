// iHearYou | Signature: i729
import AVFoundation
import AudioDSP
import Foundation

struct AudioSnapshot {
    let stats: IHStats
    let recordingSeconds: Double
    let isRecording: Bool
    let recordingError: String?
}

final class AudioSession {
    private let queue = DispatchQueue(label: "com.i729.iHearYou.audio", qos: .userInteractive)
    private var processor: OpaquePointer?
    private var captureEngine: AVAudioEngine?
    private var virtualOutput: VirtualOutput?
    private var monitorEngine: AVAudioEngine?
    private var timer: DispatchSourceTimer?
    private var writer: RecordingWriter?
    private var recordingError: String?
    private var raw = [Float](repeating: 0, count: 480)
    private var clean = [Float](repeating: 0, count: 480)
    private var notifications: [NSObjectProtocol] = []
    var onDeviceFailure: ((String) -> Void)?

    func start(input: AudioDevice, virtual: AudioDevice?, monitor: AudioDevice?, enabled: Bool, strength: Float, gain: Float, gate: Bool) throws {
        stop()
        let engine = AVAudioEngine()
        try AudioDevices.setDevice(engine.inputNode.audioUnit, id: input.id)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard let modelURL = Bundle.main.url(forResource: "dpdfnet2_48khz_hr", withExtension: "onnx") else {
            throw AudioFailure.message("Model peredaman tidak ditemukan. Jalankan iHearYou dari bundle aplikasi lengkap.")
        }
        guard format.channelCount > 0, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              let p = ih_create(format.sampleRate, modelURL.path) else {
            throw AudioFailure.message("Format mikrofon tidak didukung. Pilih mikrofon lain.")
        }
        processor = p
        ih_settings(p, enabled ? 1 : 0, strength, gain, gate ? 1 : 0)
        captureEngine = engine
        do {
            if let virtual { virtualOutput = try VirtualOutput(device: virtual, processor: p) }
            if let monitor {
                guard !monitor.isVirtual else { throw AudioFailure.message("Untuk dengar langsung, pilih headphone fisik.") }
                monitorEngine = try outputEngine(device: monitor, processor: p, monitor: true)
            }
            // Capture only channel one. Do not average stereo channels that may be out of phase.
            engine.inputNode.installTap(onBus: 0, bufferSize: 960, format: format) { buffer, _ in
                guard let samples = buffer.floatChannelData?[0] else { return }
                ih_capture(p, samples, buffer.frameLength)
            }
            engine.prepare()
            try engine.start()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            self.timer = timer
            timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.process(p) }
            timer.resume()
            for observed in [captureEngine, monitorEngine].compactMap({ $0 }) {
                notifications.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: observed, queue: .main) { [weak self] _ in
                    guard let self,
                          self.captureEngine === observed || self.monitorEngine === observed,
                          !observed.isRunning else { return }
                    self.onDeviceFailure?("Konfigurasi audio berubah. Proses dihentikan; pilih perangkat lalu aktifkan lagi.")
                })
            }
        } catch { stop(); throw error }
    }

    private func outputEngine(device: AudioDevice, processor p: OpaquePointer, monitor: Bool) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        try AudioDevices.setDevice(engine.outputNode.audioUnit, id: device.id)
        let mono = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let source = AVAudioSourceNode(format: mono) { _, _, frameCount, list -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            if let first = buffers.first, let data = first.mData {
                ih_render(p, data.assumingMemoryBound(to: Float.self), frameCount, monitor ? 1 : 0)
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
        engine.prepare()
        try engine.start()
        return engine
    }
    private func process(_ p: OpaquePointer) {
        // Bound each event so meter reads and stop requests cannot starve during overload.
        for _ in 0..<8 {
            guard ih_next_frame(p, &raw, &clean) != 0 else { break }
            ih_publish(p, &clean, virtualOutput != nil ? 1 : 0, monitorEngine != nil ? 1 : 0)
            if let writer {
                do { try writer.write(original: raw, processed: clean) }
                catch {
                    writer.close(); self.writer = nil
                    recordingError = "Rekaman dihentikan: \(error.localizedDescription)"
                }
            }
        }
    }
    func configure(enabled: Bool, strength: Float, gain: Float, gate: Bool) {
        if let processor { ih_settings(processor, enabled ? 1 : 0, strength, gain, gate ? 1 : 0) }
    }
    func snapshot() -> AudioSnapshot? {
        guard let processor else { return nil }
        let stats = ih_stats(processor)
        return queue.sync { AudioSnapshot(stats: stats, recordingSeconds: Double(writer?.frames ?? 0) / 48000,
                                          isRecording: writer != nil, recordingError: recordingError) }
    }
    func startRecording() throws {
        guard processor != nil else { throw AudioFailure.message("Aktifkan mikrofon sebelum merekam.") }
        try queue.sync { recordingError = nil; writer = try RecordingWriter() }
    }
    @discardableResult func stopRecording() -> URL? {
        queue.sync { let url = writer?.cleanURL; writer?.close(); writer = nil; return url }
    }
    func stop() {
        notifications.forEach(NotificationCenter.default.removeObserver); notifications = []
        captureEngine?.stop()
        if captureEngine != nil { captureEngine?.inputNode.removeTap(onBus: 0) }
        // AVAudioEngine.stop waits for render callbacks before releasing the processor.
        virtualOutput?.stop(); monitorEngine?.stop()
        timer?.cancel(); timer = nil
        queue.sync { writer?.close(); writer = nil }
        captureEngine = nil; virtualOutput = nil; monitorEngine = nil
        if let processor { ih_destroy(processor) }
        processor = nil; recordingError = nil
    }
    deinit { stop() }
}
