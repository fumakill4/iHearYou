// iHearYou | Signature: i729
import XCTest
import AudioDSP

final class AudioDSPTests: XCTestCase {
    let modelPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/DPDFNet/dpdfnet2_48khz_hr.onnx").path
    let vadPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/Silero/silero_vad.onnx").path
    let headsetPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/GTCRN/gtcrn_simple.onnx").path
    let narrowbandPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/DPDFNet/dpdfnet2.onnx").path
    func run(_ input: [Float], rate: Double = 48000, enabled: Bool = true, gain: Float = 0, headset: Bool = false) -> (raw: [Float], clean: [Float]) {
        let processor = (headset ? ih_create_headset(rate, narrowbandPath, headsetPath, vadPath) : ih_create(rate, modelPath, vadPath))!
        defer { ih_destroy(processor) }
        ih_settings(processor, enabled ? 1 : 0, 1, gain, 0)
        var raw = [Float](repeating: 0, count: 480), clean = raw, originals: [Float] = [], results: [Float] = []
        // Exercise input blocks unrelated to the model's frame size.
        for offset in stride(from: 0, to: input.count, by: 317) {
            let block = Array(input[offset..<min(input.count, offset + 317)])
            ih_capture(processor, block, UInt32(block.count))
            while ih_next_frame(processor, &raw, &clean) != 0 { originals += raw; results += clean }
        }
        return (originals, results)
    }
    func testSilenceIsFiniteAndSilent() {
        let output = run([Float](repeating: 0, count: 24000))
        XCTAssertGreaterThan(output.clean.count, 23000)
        XCTAssertTrue(output.clean.allSatisfy { $0.isFinite && abs($0) < 0.000001 })
    }
    func testBypassPreservesSamplesAfterDocumentedDelay() {
        let input = (0..<12000).map { Float(sin(Double($0) * .pi * 2 * 220 / 48000)) * 0.1 }
        let output = run(input, enabled: false)
        XCTAssertEqual(Array(output.clean.prefix(Int(ih_delay_samples()))), [Float](repeating: 0, count: Int(ih_delay_samples())))
        for i in Int(ih_delay_samples())..<output.clean.count { XCTAssertEqual(output.clean[i], input[i - Int(ih_delay_samples())], accuracy: 0.000001) }
        XCTAssertEqual(output.raw, output.clean)
    }
    func testStationaryNoiseIsReducedByRealModel() {
        var seed: UInt32 = 12345
        let input = (0..<96000).map { _ -> Float in
            seed = 1664525 &* seed &+ 1013904223
            return (Float(seed >> 8) / Float(0xFFFFFF) * 2 - 1) * 0.035
        }
        let output = run(input)
        let rawEnergy = output.raw.dropFirst(24000).reduce(0.0) { $0 + Double($1 * $1) }
        let cleanEnergy = output.clean.dropFirst(24000).reduce(0.0) { $0 + Double($1 * $1) }
        let reduction = 10 * log10(rawEnergy / max(cleanEnergy, 1e-16))
        print("Synthetic stationary-noise attenuation: \(reduction) dB")
        XCTAssertGreaterThan(reduction, 12, "DPDFNet2 should substantially suppress stationary noise")
    }
    func testDifferentHardwareRatesProduce48kFrames() {
        for rate in [8000.0, 16000.0, 24000.0, 32000.0, 44100.0, 48000.0, 96000.0, 192000.0] {
            let output = run([Float](repeating: 0.03, count: Int(rate)), rate: rate)
            XCTAssertGreaterThanOrEqual(output.clean.count, 47520)
            XCTAssertLessThanOrEqual(output.clean.count, 48000)
        }
    }
    func testHeadsetBypassPreservesLowBandVoiceAndTiming() {
        let input = (0..<96000).map { Float(sin(Double($0) * .pi * 2 * 180 / 48000)) * 0.12 }
        let output = run(input, enabled: false, headset: true)
        XCTAssertEqual(output.raw, output.clean)
        for index in Int(ih_delay_samples())..<output.clean.count {
            XCTAssertEqual(output.clean[index], input[index - Int(ih_delay_samples())], accuracy: 0.000001)
        }
    }
    func testHeadsetDenoiserReducesNoiseWithoutBlockSchedulingErrors() {
        let p = ih_create_headset(48000, narrowbandPath, headsetPath, vadPath)!
        defer { ih_destroy(p) }
        ih_settings(p, 1, 1, 0, 0)
        var seed: UInt32 = 54321
        var raw = [Float](repeating: 0, count: 480), clean = raw
        var inputEnergy = 0.0, outputEnergy = 0.0
        for block in 0..<600 {
            let input = (0..<480).map { _ -> Float in
                seed = 1664525 &* seed &+ 1013904223
                return (Float(seed >> 8) / Float(0xFFFFFF) * 2 - 1) * 0.05
            }
            ih_capture(p, input, 480)
            while ih_next_frame(p, &raw, &clean) != 0 {
                if block > 100 {
                    inputEnergy += raw.reduce(0) { $0 + Double($1 * $1) }
                    outputEnergy += clean.reduce(0) { $0 + Double($1 * $1) }
                }
                XCTAssertTrue(clean.allSatisfy { $0.isFinite && abs($0) <= 0.99 })
            }
        }
        XCTAssertGreaterThan(10 * log10(inputEnergy / max(outputEnergy, 1e-16)), 12)
        XCTAssertEqual(ih_stats(p).processing_errors, 0)
        XCTAssertEqual(ih_stats(p).input_drops, 0)
    }
    func testMonitoringResamples48kOutputForBluetoothRates() {
        for rate in [8000.0, 16000.0, 24000.0, 32000.0, 44100.0, 96000.0] {
            let p = ih_create(48000, modelPath, vadPath)!
            defer { ih_destroy(p) }
            let frame = [Float](repeating: 0.25, count: 480)
            for _ in 0..<8 { ih_publish(p, frame, 0, 1) }
            var output = [Float](repeating: -1, count: Int(rate * 0.04))
            ih_render_rate(p, &output, UInt32(output.count), 1, rate)
            XCTAssertTrue(output.allSatisfy { abs($0 - 0.25) < 0.000001 })
            XCTAssertEqual(ih_stats(p).output_underruns, 0)
        }
    }
    func testRecordingTailCanBeDrainedAfterCaptureStops() {
        let p = ih_create(48000, modelPath, vadPath)!
        defer { ih_destroy(p) }
        ih_settings(p, 0, 1, 0, 1)
        var input = [Float](repeating: 0.1, count: 9600)
        input[input.count - 1] = 0.42
        var raw = [Float](repeating: 0, count: 480), clean = raw, output: [Float] = []
        for offset in stride(from: 0, to: input.count, by: 480) {
            ih_capture(p, Array(input[offset..<offset+480]), 480)
            while ih_next_frame(p, &raw, &clean) != 0 { output += clean }
        }
        for _ in 0..<Int((ih_delay_samples() + 479) / 480) + 2 {
            ih_pad_silence(p)
            while ih_next_frame(p, &raw, &clean) != 0 { output += clean }
        }
        let delay = Int(ih_delay_samples())
        XCTAssertGreaterThanOrEqual(output.count, delay + input.count)
        for index in input.indices { XCTAssertEqual(output[delay + index], input[index], accuracy: 0.000001) }
    }
    func testRoutingLanesAreIndependentAndUnderrunsAreSilent() {
        let processor = ih_create(48000, modelPath, vadPath)!
        defer { ih_destroy(processor) }
        let input = (0..<480).map { Float($0) / 1000 }
        ih_publish(processor, input, 1, 1)
        var a = [Float](repeating: -1, count: 480), b = a
        ih_render(processor, &a, 480, 0)
        ih_render(processor, &b, 480, 1)
        XCTAssertEqual(a, input); XCTAssertEqual(b, input)
        ih_render(processor, &a, 480, 0)
        XCTAssertEqual(a, [Float](repeating: 0, count: 480))
        XCTAssertEqual(ih_stats(processor).output_underruns, 1)
    }
    func testInvalidSamplesAndClippingAreBounded() {
        var input = [Float](repeating: 2, count: 8000)
        input[10] = .nan; input[20] = .infinity
        let output = run(input, enabled: false, gain: 12)
        XCTAssertTrue(output.clean.allSatisfy { $0.isFinite && abs($0) <= 0.99 })
        XCTAssertNil(ih_create(0, modelPath, vadPath)); XCTAssertNil(ih_create(.nan, modelPath, vadPath))
    }
    func testCaptureOverflowNeverExceedsCapacity() {
        let processor = ih_create(48000, modelPath, vadPath)!
        defer { ih_destroy(processor) }
        let input = [Float](repeating: 0, count: 40000)
        ih_capture(processor, input, 40000)
        XCTAssertEqual(ih_queued_input(processor), 32768)
        XCTAssertEqual(ih_stats(processor).input_drops, 7232)
        var raw = [Float](repeating: 0, count: 480), clean = raw
        while ih_next_frame(processor, &raw, &clean) != 0 {}
        XCTAssertLessThan(ih_queued_input(processor), 480)
    }
    func testLiveModeChangesAndBypassRemainHealthy() {
        let processor = ih_create(48000, modelPath, vadPath)!
        defer { ih_destroy(processor) }
        var raw = [Float](repeating: 0, count: 480), clean = raw
        var frames = 0
        for block in 0..<160 {
            let bypass = block >= 100
            ih_settings(processor, bypass ? 0 : 1, block < 50 ? 0.65 : 1, 0, block >= 50 ? 1 : 0)
            let input = (0..<480).map { Float(sin(Double(block * 480 + $0) * .pi * 2 * 180 / 48000)) * 0.15 }
            ih_capture(processor, input, 480)
            while ih_next_frame(processor, &raw, &clean) != 0 {
                frames += 1
                XCTAssertTrue(clean.allSatisfy { $0.isFinite && abs($0) <= 0.99 })
                if bypass { XCTAssertEqual(raw, clean) }
            }
        }
        XCTAssertGreaterThan(frames, 150)
        XCTAssertEqual(ih_stats(processor).processing_errors, 0)
        XCTAssertEqual(ih_stats(processor).input_drops, 0)
    }
}
