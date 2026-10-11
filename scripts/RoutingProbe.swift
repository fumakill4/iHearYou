// iHearYou | Signature: i729
// Developer verification: read only the virtual input, report RMS and sample count.
import AVFoundation
import Foundation

@main struct RoutingProbe {
    static func main() {
        do { try run() }
        catch { fputs("ROUTING PROBE FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run() throws {
        guard let device = AudioDevices.list().first(where: { $0.isOurMic }) else {
            throw AudioFailure.message("iHearYou virtual driver is not loaded")
        }
        let engine = AVAudioEngine()
        try AudioDevices.setDevice(engine.inputNode.audioUnit, id: device.id)
        let format = engine.inputNode.outputFormat(forBus: 0)
        let lock = NSLock()
        var samples: UInt64 = 0, energy = 0.0, peak = 0.0
        engine.inputNode.installTap(onBus: 0, bufferSize: 960, format: format) { buffer, _ in
            guard let data = buffer.floatChannelData?[0] else { return }
            var blockEnergy = 0.0, blockPeak = 0.0
            for i in 0..<Int(buffer.frameLength) {
                let value = Double(data[i]); blockEnergy += value * value; blockPeak = max(blockPeak, abs(value))
            }
            lock.lock(); samples += UInt64(buffer.frameLength); energy += blockEnergy; peak = max(peak, blockPeak); lock.unlock()
        }
        try engine.start()
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        lock.lock()
        let total = samples, rms = sqrt(energy / Double(max(1, samples))), maxPeak = peak
        lock.unlock()
        print("Device: \(device.name) | UID: \(device.uid)")
        print("Rate: \(format.sampleRate) | Channels: \(format.channelCount)")
        print("Samples: \(total) | RMS dBFS: \(20 * log10(max(1e-12, rms))) | Peak: \(maxPeak)")
        fflush(stdout)
        guard total > 100000 else { throw AudioFailure.message("Virtual microphone did not deliver enough samples") }
        if CommandLine.arguments.contains("--expect-signal"), maxPeak < 0.00001 {
            throw AudioFailure.message("Virtual input was silent while bypass signal was expected")
        }
        print("ROUTING PROBE PASS")
    }
}
