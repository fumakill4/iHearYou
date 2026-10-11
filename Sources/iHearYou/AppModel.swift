// iHearYou | Signature: i729
import SwiftUI
import AVFoundation
import AppKit
import CoreAudio

enum Screen: String, CaseIterable { case microphone = "Mikrofon", recordings = "Rekaman", guide = "Panduan" }
enum SuppressionMode: String, CaseIterable {
    case natural = "Natural", balanced = "Seimbang", strong = "Kuat"
    var strength: Float { switch self { case .natural: return 0.65; case .balanced, .strong: return 1 } }
    var explanation: String {
        switch self {
        case .natural: return "Peredaman hingga 20 dB untuk menjaga karakter suara."
        case .balanced: return "DPDFNet2 dengan batas peredaman 30 dB."
        case .strong: return "DPDFNet2 48 kHz dengan peredaman penuh."
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var screen = Screen.microphone
    @Published var devices: [AudioDevice] = []
    @Published var inputUID: String { didSet { UserDefaults.standard.set(inputUID, forKey: "inputUID") } }
    @Published var monitorUID: String { didSet { UserDefaults.standard.set(monitorUID, forKey: "monitorUID") } }
    @Published var suppression: Bool { didSet { saveSettings() } }
    @Published var mode: SuppressionMode { didSet { saveSettings() } }
    @Published var gain: Double { didSet { saveSettings() } }
    @Published var monitoring = false
    @Published var phoneSpeakerEnabled = false
    @Published var phoneSpeakerURLs: [URL] = []
    @Published var phoneSpeakerConnected = false
    @Published var active = false
    @Published var starting = false
    @Published var recording = false
    @Published var seconds = 0.0
    @Published var sessionSeconds = 0.0
    @Published var showFloating: Bool { didSet { UserDefaults.standard.set(showFloating, forKey: "showFloating") } }
    @Published var appearance: AppAppearance { didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") } }
    var onShowControls: (() -> Void)?
    var onShowSettings: (() -> Void)?
    @Published var inputDB: Float = -90
    @Published var outputDB: Float = -90
    @Published var voice: Float = 0
    @Published var originalHistory = [Float](repeating: 0, count: 72)
    @Published var cleanHistory = [Float](repeating: 0, count: 72)
    @Published var error: String?
    @Published var notice: String?
    @Published var recordings: [Recording] = []
    @Published var playingURL: URL?
    @Published var inputDrops: UInt64 = 0
    private let session = AudioSession()
    private let browserRecorder = BrowserRecorderServer()
    private let phoneSpeaker = PhoneSpeakerServer()
    private var sessionStarted: Date?
    private var runningInputID: AudioDeviceID?
    private var runningMonitorID: AudioDeviceID?
    private var timer: Timer?
    private var lastDeviceRefresh = Date()
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var player: AVAudioPlayer?
    var microphones: [AudioDevice] { devices.inputCandidates }
    var headphones: [AudioDevice] { devices.outputCandidates }
    var virtualMic: AudioDevice? { devices.first { $0.isOurMic && $0.outputChannels > 0 } }
    var selectedInput: AudioDevice? { microphones.first { $0.uid == inputUID } }
    var selectedMonitor: AudioDevice? { headphones.first { $0.uid == monitorUID } }
    var canStart: Bool { selectedInput != nil && !starting }
    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    var elapsed: String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    var sessionElapsed: String { String(format: "%02d:%02d", Int(sessionSeconds) / 60, Int(sessionSeconds) % 60) }
    var permissionDenied: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .denied || AVCaptureDevice.authorizationStatus(for: .audio) == .restricted }

    private init() {
        let defaults = UserDefaults.standard
        inputUID = defaults.string(forKey: "inputUID") ?? ""
        monitorUID = defaults.string(forKey: "monitorUID") ?? ""
        suppression = defaults.object(forKey: "suppression") as? Bool ?? true
        mode = SuppressionMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .strong
        gain = defaults.object(forKey: "gain") as? Double ?? 0
        showFloating = defaults.object(forKey: "showFloating") as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        refreshDevices(); refreshRecordings()
        let receiver = phoneSpeaker
        session.onProcessedAudio = { samples in receiver.publish(samples) }
        receiver.onState = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phoneSpeakerURLs = state.urls
                self.phoneSpeakerConnected = state.connected
                if let message = state.error { self.error = message }
            }
        }
        session.onDeviceFailure = { [weak self] message in
            guard let self, self.active else { return }
            self.stop(); self.error = message; self.refreshDevices()
        }
        let meterTimer = Timer(timeInterval: 0.07, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMeters() }
        }
        timer = meterTimer
        RunLoop.main.add(meterTimer, forMode: .common)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshDevices()
            }
        }
        deviceListener = listener
        var a = AudioDevices.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, listener)
    }
    func refreshDevices() {
        devices = AudioDevices.list()
        let inputLost = selectedInput == nil || selectedInput?.id != runningInputID
        let monitorLost = selectedMonitor == nil || selectedMonitor?.id != runningMonitorID
        if active && (inputLost || (monitoring && monitorLost)) {
            let hadRecording = recording
            stop()
            error = (inputLost ? "Mikrofon terputus." : "Perangkat dengar langsung terputus.")
                + (hadRecording ? " Rekaman sudah disimpan." : "")
                + " Pilih perangkat lalu aktifkan kembali mikrofon."
        }
        // Keep the device identities used by a running session. A missing unused
        // monitor stays selected until the user changes it or the session stops.
        guard !active && !starting else { return }
        if !microphones.contains(where: { $0.uid == inputUID }) {
            inputUID = (microphones.first { $0.id == AudioDevices.defaultInput } ?? microphones.first)?.uid ?? ""
        }
        if !headphones.contains(where: { $0.uid == monitorUID }) {
            monitorUID = (headphones.first { $0.id == AudioDevices.defaultOutput } ?? headphones.first)?.uid ?? ""
        }
    }
    func selectInput(_ uid: String) {
        guard !starting, uid != inputUID else { return }
        guard let device = microphones.first(where: { $0.uid == uid }) else {
            error = "Mikrofon tidak tersedia. Muat ulang perangkat lalu pilih kembali."; return
        }
        let usesContinuity = device.transport == kAudioDeviceTransportTypeContinuityCaptureWired
            || device.transport == kAudioDeviceTransportTypeContinuityCaptureWireless
        let receiverStopped = phoneSpeakerEnabled && usesContinuity
        if receiverStopped { setPhoneSpeakerEnabled(false) }
        changeHardware(description: "Mikrofon diganti ke \(device.name)." + (receiverStopped ? " Penerima Safari dimatikan agar iPhone dapat dipakai sebagai mikrofon." : "")) { inputUID = uid }
    }
    func selectMonitor(_ uid: String) {
        guard !starting, uid != monitorUID else { return }
        guard let device = headphones.first(where: { $0.uid == uid }) else {
            error = "Output tidak tersedia. Muat ulang perangkat lalu pilih kembali."; return
        }
        changeHardware(description: "Speaker diganti ke \(device.name).") { monitorUID = uid }
    }
    func setMonitoring(_ enabled: Bool) {
        guard !starting, enabled != monitoring else { return }
        guard !enabled || selectedMonitor != nil else {
            error = "Pilih speaker atau headphone yang tersedia sebelum mengaktifkan dengar langsung."; return
        }
        changeHardware(description: enabled ? "Dengar langsung diaktifkan." : "Dengar langsung dimatikan.") { monitoring = enabled }
    }
    func setPhoneSpeakerEnabled(_ enabled: Bool) {
        guard enabled != phoneSpeakerEnabled else { return }
        error = nil
        if enabled {
            guard selectedInput?.transport != kAudioDeviceTransportTypeContinuityCaptureWired,
                  selectedInput?.transport != kAudioDeviceTransportTypeContinuityCaptureWireless else {
                error = "Untuk Safari pada iPhone yang sama, pilih mikrofon Mac/USB/Bluetooth dahulu. Membuka Safari menjeda mikrofon Continuity iPhone."; return
            }
            do {
                try phoneSpeaker.start()
                phoneSpeakerEnabled = true
                notice = "Buka tautan speaker di Safari iPhone pada Wi-Fi yang sama, lalu ketuk Dengarkan."
            } catch { self.error = error.localizedDescription }
        } else {
            phoneSpeakerEnabled = false; phoneSpeakerURLs = []; phoneSpeakerConnected = false
            phoneSpeaker.stop()
        }
    }
    func copyPhoneSpeakerURL() {
        guard let url = phoneSpeakerURLs.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        notice = "Tautan speaker disalin. Buka di Safari iPhone pada Wi-Fi yang sama."
    }
    func openPhoneSpeakerPreview() {
        guard let url = phoneSpeakerURLs.first else { return }
        NSWorkspace.shared.open(url)
    }
    private func changeHardware(description: String, apply: () -> Void) {
        let resumeSession = active
        let resumeRecording = recording
        if resumeSession { stop() }
        apply()
        error = nil
        guard resumeSession else { return }
        // Lock selectors immediately, before the asynchronous restart can yield.
        starting = true
        Task { @MainActor [self] in
            defer { starting = false }
            await startSession()
            guard active else {
                if resumeRecording { notice = "Rekaman sebelumnya sudah disimpan. Mikrofon belum berhasil diaktifkan kembali." }
                return
            }
            if resumeRecording {
                toggleRecording()
                notice = recording
                    ? description + " Rekaman sebelumnya disimpan; perekaman berlanjut di file baru."
                    : description + " Rekaman sebelumnya disimpan. Rekaman baru belum dimulai."
            } else {
                notice = description + (virtualMic == nil ? " Pasang driver untuk memakai output di browser." : "")
            }
        }
    }
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(suppression, forKey: "suppression"); defaults.set(mode.rawValue, forKey: "mode"); defaults.set(gain, forKey: "gain")
        session.configure(enabled: suppression, strength: mode.strength, gain: Float(gain), gate: mode == .strong)
    }
    func toggle() { if active { stop() } else { Task { await start() } } }
    func start() async {
        guard !starting && !active else { return }
        starting = true; error = nil; notice = nil
        defer { starting = false }
        await startSession()
    }
    private func startSession() async {
        error = nil; notice = nil
        stopPlayback()
        let permitted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: permitted = true
        case .notDetermined: permitted = await AVCaptureDevice.requestAccess(for: .audio)
        default: permitted = false
        }
        guard permitted else {
            error = "Akses mikrofon belum diizinkan. Buka Pengaturan Privasi, aktifkan iHearYou, lalu coba lagi."
            return
        }
        refreshDevices()
        guard let input = selectedInput else { error = "Mikrofon terpilih tidak tersedia. Sambungkan mikrofon lalu tekan Muat ulang perangkat."; return }
        do {
            let monitor = monitoring ? selectedMonitor : nil
            if monitoring && monitor == nil { throw AudioFailure.message("Pilih headphone untuk dengar langsung.") }
            try session.start(input: input, virtual: virtualMic, monitor: monitor, enabled: suppression, strength: mode.strength, gain: Float(gain), gate: mode == .strong)
            runningInputID = input.id; runningMonitorID = monitor?.id
            active = true
            sessionStarted = Date(); sessionSeconds = 0
            if virtualMic == nil { notice = "Mode rekaman siap. Pasang driver untuk memakai iHearYou di aplikasi meeting." }
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        let wasRecording = recording
        session.stop(); active = false; recording = false; seconds = 0
        runningInputID = nil; runningMonitorID = nil
        sessionStarted = nil; sessionSeconds = 0
        inputDB = -90; outputDB = -90; voice = 0
        originalHistory = [Float](repeating: 0, count: 72); cleanHistory = originalHistory
        if wasRecording { refreshRecordings(); notice = "Rekaman disimpan di Musik/iHearYou." }
    }
    func toggleRecording() {
        error = nil
        if recording {
            session.stopRecording(); recording = false; seconds = 0; refreshRecordings()
            notice = "Rekaman bersih dan suara asli sudah disimpan."
        } else {
            do { try session.startRecording(); recording = true; seconds = 0; notice = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    private func updateMeters() {
        if Date().timeIntervalSince(lastDeviceRefresh) >= 2 {
            lastDeviceRefresh = Date()
            refreshDevices()
        }
        if let sessionStarted { sessionSeconds = Date().timeIntervalSince(sessionStarted) }
        if active, let snapshot = session.snapshot() {
            inputDB = snapshot.stats.input_db; outputDB = snapshot.stats.output_db; voice = snapshot.stats.voice_probability
            inputDrops = snapshot.stats.input_drops; seconds = snapshot.recordingSeconds
            if snapshot.stats.processing_errors > 0 {
                stop(); error = "Mesin peredaman gagal memproses audio. Aktifkan kembali mikrofon."; return
            }
            originalHistory.removeFirst(); originalHistory.append(level(inputDB))
            cleanHistory.removeFirst(); cleanHistory.append(level(outputDB))
            if recording && !snapshot.isRecording { recording = false; refreshRecordings() }
            if let message = snapshot.recordingError { error = message }
        }
        if playingURL != nil && player?.isPlaying != true { playingURL = nil; player = nil }
    }
    func level(_ db: Float) -> Float { max(0, min(1, (db + 60) / 60)) }
    func refreshRecordings() { recordings = RecordingStore.list() }
    func play(_ url: URL) {
        if playingURL == url { stopPlayback(); return }
        stopPlayback()
        guard !active else { error = "Hentikan mikrofon sebelum memutar rekaman agar suara playback tidak tertangkap."; return }
        do { player = try AVAudioPlayer(contentsOf: url); player?.play(); playingURL = url }
        catch { self.error = "Rekaman tidak bisa diputar: \(error.localizedDescription)" }
    }
    func stopPlayback() { player?.stop(); player = nil; playingURL = nil }
    func revealRecordings() {
        do {
            try FileManager.default.createDirectory(at: RecordingStore.folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(RecordingStore.folder)
        } catch { self.error = error.localizedDescription }
    }
    func export(_ recording: Recording) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.nameFieldStringValue = recording.cleanURL.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard destination.standardizedFileURL != recording.cleanURL.standardizedFileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: copyForReplacement(recording.cleanURL))
            } else { try FileManager.default.copyItem(at: recording.cleanURL, to: destination) }
            notice = "Rekaman diekspor ke \(destination.lastPathComponent)."
        } catch { self.error = error.localizedDescription }
    }
    private func copyForReplacement(_ source: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try FileManager.default.copyItem(at: source, to: temp); return temp
    }
    func installDriver() {
        guard !active else { error = "Hentikan mikrofon sebelum memasang driver."; return }
        guard let url = Bundle.main.url(forResource: "iHearYouMicrophone", withExtension: "pkg") else {
            error = "Installer driver tidak ditemukan. Jalankan scripts/build.sh untuk membuat bundle lengkap."; return
        }
        NSWorkspace.shared.open(url)
        notice = "Ikuti installer macOS. Setelah selesai, muat ulang perangkat. Restart Mac jika driver belum muncul."
    }
    func openPrivacy() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }
    func showMainWindow() {
        onShowControls?()
    }
    func showSettings() {
        onShowSettings?()
        NSApp.activate(ignoringOtherApps: true)
    }
    func openBrowserRecorder() {
        Task { @MainActor [self] in
            if !active { await start() }
            guard active else { return }
            guard virtualMic != nil else { error = "Pasang driver iHearYou Microphone untuk merekam melalui browser."; return }
            browserRecorder.open { [weak self] result in
                switch result {
                case .success(let url): NSWorkspace.shared.open(url)
                case .failure(let failure): self?.error = failure.localizedDescription
                }
            }
        }
    }
    func shutdown() { stop(); stopPlayback(); browserRecorder.stop(); phoneSpeaker.stop(); timer?.invalidate() }
}
