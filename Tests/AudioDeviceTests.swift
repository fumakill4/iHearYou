// iHearYou | Signature: i729
import XCTest
import CoreAudio
import AudioSafety
import AudioDSP
@testable import iHearYou

final class AudioDeviceTests: XCTestCase {
    func device(_ uid: String, transport: UInt32, inputs: Int = 1, alive: Bool = true) -> AudioDevice {
        AudioDevice(id: 1, uid: uid, name: uid, inputChannels: inputs, outputChannels: 2, transport: transport, isAlive: alive)
    }
    func testPhysicalMicrophonesRemainAvailableWhileLoopbacksAreExcluded() {
        let devices = [device("AirPods Pro 2", transport: kAudioDeviceTransportTypeBluetooth),
                       device("Built-in", transport: kAudioDeviceTransportTypeBuiltIn),
                       device("USB", transport: kAudioDeviceTransportTypeUSB),
                       device("Continuity", transport: kAudioDeviceTransportTypeContinuityCaptureWireless),
                       device("SoundVeil", transport: kAudioDeviceTransportTypeVirtual),
                       device("iHearYouMic_UID", transport: kAudioDeviceTransportTypeUSB),
                       device("Aggregate loopback", transport: kAudioDeviceTransportTypeAggregate),
                       device("Disconnected", transport: kAudioDeviceTransportTypeBluetooth, alive: false)]
        XCTAssertEqual(devices.inputCandidates.map(\.uid), ["AirPods Pro 2", "Built-in", "USB", "Continuity"])
        XCTAssertFalse(devices.outputCandidates.contains { $0.isVirtual || $0.isOurLoopback })
    }
    func testTransientAudioExceptionsBecomeRecoverableErrors() {
        var error: NSError?
        let result = IHPerformAudioOperation({
            NSException(name: .invalidArgumentException, reason: "Hardware sample rate changed", userInfo: nil).raise()
        }, &error)
        XCTAssertFalse(result)
        XCTAssertTrue(error?.localizedDescription.contains("sample rate") == true)
        XCTAssertTrue(IHPerformAudioOperation({}, &error))
    }
    func testQueuedCallbackKeepsProcessorAliveUntilItFinishes() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let model = root.appendingPathComponent("Vendor/DPDFNet/dpdfnet2_48khz_hr.onnx").path
        let vad = root.appendingPathComponent("Vendor/Silero/silero_vad.onnx").path
        var owner: DSPContext? = DSPContext(ih_create(48000, model, vad)!)
        weak var witness = owner
        let queue = DispatchQueue(label: "iHearYou.test.late-callback")
        let entered = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        let done = expectation(description: "Late render finished")
        queue.async { [captured = owner!] in
            entered.signal(); resume.wait()
            var samples = [Float](repeating: 1, count: 480)
            ih_render(captured.pointer, &samples, 480, 0)
            XCTAssertEqual(samples, [Float](repeating: 0, count: 480))
            done.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 3), .success)
        owner = nil
        XCTAssertNotNil(witness)
        resume.signal()
        wait(for: [done], timeout: 3)
        queue.sync {}
        XCTAssertNil(witness)
    }
}
