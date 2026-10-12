// iHearYou | Signature: i729
import Foundation
import AVFoundation

struct Recording: Identifiable {
    var id: URL { cleanURL }
    let cleanURL: URL
    let rawURL: URL
    let date: Date
    let duration: Double
    var title: String { cleanURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-clean", with: "") }
}

enum RecordingStore {
    static var folder: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("iHearYou", isDirectory: true)
    }
    static func list() throws -> [Recording] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
        return urls.filter { $0.lastPathComponent.hasSuffix("-clean.wav") }.compactMap { url in
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let raw = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: "-clean.wav", with: "-original.wav"))
            return Recording(cleanURL: url, rawURL: raw, date: date, duration: Double(file.length) / file.processingFormat.sampleRate)
        }.sorted { $0.date > $1.date }
    }
}

// Created, used, and closed on the same serial audio processing queue.
final class RecordingWriter {
    let cleanURL: URL
    private var clean: AVAudioFile?
    private var raw: AVAudioFile?
    private let buffer: AVAudioPCMBuffer
    private(set) var frames: Int64 = 0
    init() throws {
        try FileManager.default.createDirectory(at: RecordingStore.folder, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let prefix = "iHearYou-" + formatter.string(from: Date())
        cleanURL = RecordingStore.folder.appendingPathComponent(prefix + "-clean.wav")
        let rawURL = RecordingStore.folder.appendingPathComponent(prefix + "-original.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        clean = try AVAudioFile(forWriting: cleanURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        raw = try AVAudioFile(forWriting: rawURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        buffer.frameLength = 480
    }
    func write(original: UnsafePointer<Float>, processed: UnsafePointer<Float>) throws {
        buffer.floatChannelData![0].update(from: processed, count: 480)
        try clean?.write(from: buffer)
        buffer.floatChannelData![0].update(from: original, count: 480)
        try raw?.write(from: buffer)
        frames += 480
    }
    func close() { clean = nil; raw = nil }
}
