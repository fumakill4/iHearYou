// iHearYou | Signature: i729
import SwiftUI
import AVFoundation
import AppKit
import CoreAudio

enum Screen: String, CaseIterable {
    case microphone = "Mikrofon", recordings = "Rekaman", guide = "Panduan"
    var title: String {
        switch self {
        case .microphone: return L("Microphone", "Mikrofon")
        case .recordings: return L("Recordings", "Rekaman")
        case .guide: return L("Guide", "Panduan")
        }
    }
}
enum SuppressionMode: String, CaseIterable {
    case natural = "Natural", balanced = "Seimbang", strong = "Kuat"
    // Keep persisted preset identifiers compatible with previous app versions.
    var title: String {
        switch self {
        case .natural: return L("Natural", "Natural")
        case .balanced: return L("Balanced", "Seimbang")
        case .strong: return L("Studio", "Studio")
        }
    }
    var strength: Float { switch self { case .natural: return 0.65; case .balanced, .strong: return 1 } }
    var explanation: String {
        switch self {
        case .natural: return L("Full neural noise reduction with a gentle speech gate.", "Peredaman neural penuh dengan gerbang ucapan lembut.")
        case .balanced: return L("Full neural noise reduction with a balanced speech gate.", "Peredaman neural penuh dengan gerbang ucapan seimbang.")
        case .strong: return L("Full noise reduction, rumble filter and speech-only gate.", "Peredaman penuh, filter dengung, dan gerbang khusus ucapan.")
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
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            L10n.language = language
            error = L10n.retranslate(error, language: language)
            notice = L10n.retranslate(notice, language: language)
        }
    }
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
    private var bluetoothSeenAt: [String: Date] = [:]
    private var lastDeviceRefresh = Date()
    private var recoveryGeneration = UUID()
    private var recoveryTask: Task<Void, Never>?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var player: AVAudioPlayer?
    var microphones: [AudioDevice] { devices.inputCandidates }
    var headphones: [AudioDevice] { devices.outputCandidates }
    var virtualMic: AudioDevice? { devices.first { $0.isOurMic && $0.outputChannels > 0 } }
    var selectedInput: AudioDevice? { microphones.first { $0.uid == inputUID } }
    var selectedMonitor: AudioDevice? { headphones.first { $0.uid == monitorUID } }
    var isBluetoothInput: Bool {
        selectedInput?.transport == kAudioDeviceTransportTypeBluetooth || selectedInput?.transport == kAudioDeviceTransportTypeBluetoothLE
    }
    var suppressionExplanation: String {
        isBluetoothInput
            ? t("Headset noise reduction: optimized for Bluetooth speech; other voices may remain.", "Peredaman headset: dioptimalkan untuk ucapan Bluetooth; suara orang lain masih bisa masuk.")
            : mode.explanation
    }
    var canStart: Bool { selectedInput != nil && !starting }
    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    var elapsed: String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    var sessionElapsed: String { String(format: "%02d:%02d", Int(sessionSeconds) / 60, Int(sessionSeconds) % 60) }
    var permissionDenied: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .denied || AVCaptureDevice.authorizationStatus(for: .audio) == .restricted }
    func t(_ english: String, _ indonesian: String) -> String { L10n.text(english, indonesian, language: language) }

    private init() {
        let defaults = UserDefaults.standard
        inputUID = defaults.string(forKey: "inputUID") ?? ""
        monitorUID = defaults.string(forKey: "monitorUID") ?? ""
        suppression = defaults.object(forKey: "suppression") as? Bool ?? true
        mode = SuppressionMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .strong
        gain = defaults.object(forKey: "gain") as? Double ?? 0
        showFloating = defaults.object(forKey: "showFloating") as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .english
        L10n.language = language
        refreshDevices(); refreshRecordings()
        let receiver = phoneSpeaker
        session.onProcessedAudio = { samples in receiver.publish(samples) }
        receiver.onState = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.phoneSpeakerURLs = state.urls
                self.phoneSpeakerConnected = state.connected
                if let message = state.error { self.error = message }
            }
        }
        session.onDeviceFailure = { [weak self] message in
            guard let self, self.active else { return }
            self.reconnectAudio(message: message)
        }
        let meterTimer = Timer(timeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateMeters() }
        }
        timer = meterTimer
        RunLoop.main.add(meterTimer, forMode: .common)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshDevices()
            }
        }
        deviceListener = listener
        var a = AudioDevices.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, listener)
    }
    private func reconnectAudio(message: String) {
        let resumeRecording = recording
        let microphoneUID = inputUID
        stop()
        starting = true
        notice = message
        let generation = recoveryGeneration
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.recoveryGeneration == generation { self.starting = false; self.recoveryTask = nil } }
            for attempt in 1...3 {
                do { try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                self.refreshDevices()
                guard self.microphones.contains(where: { $0.uid == microphoneUID }) else {
                    self.error = self.t("Microphone disconnected. Your recording was saved; select a microphone to continue.", "Mikrofon terputus. Rekaman sudah disimpan; pilih mikrofon untuk melanjutkan.")
                    return
                }
                await self.startSession()
                if self.active {
                    if resumeRecording { self.beginRecording() }
                    self.notice = self.t("Audio reconnected." + (resumeRecording ? " Recording continues in a new file." : ""),
                                         "Audio tersambung kembali." + (resumeRecording ? " Perekaman berlanjut di file baru." : ""))
                    return
                }
            }
        }
    }
    func refreshDevices() {
        devices = AudioDevices.list()
        let bluetoothUIDs = Set(devices.filter {
            $0.transport == kAudioDeviceTransportTypeBluetooth || $0.transport == kAudioDeviceTransportTypeBluetoothLE
        }.map(\.uid))
        bluetoothSeenAt = bluetoothSeenAt.filter { bluetoothUIDs.contains($0.key) }
        for uid in bluetoothUIDs where bluetoothSeenAt[uid] == nil { bluetoothSeenAt[uid] = Date() }
        let inputLost = selectedInput == nil || selectedInput?.id != runningInputID
        let monitorLost = selectedMonitor == nil || selectedMonitor?.id != runningMonitorID
        if active && (inputLost || (monitoring && monitorLost)) {
            let hadRecording = recording
            stop()
            error = t((inputLost ? "Microphone disconnected." : "Live monitoring device disconnected.")
                + (hadRecording ? " Your recording was saved." : "") + " Select a device and start the microphone again.",
                (inputLost ? "Mikrofon terputus." : "Perangkat dengar langsung terputus.")
                + (hadRecording ? " Rekaman sudah disimpan." : "") + " Pilih perangkat lalu aktifkan kembali mikrofon.")
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
            error = t("Microphone unavailable. Refresh Devices and select it again.", "Mikrofon tidak tersedia. Muat ulang perangkat lalu pilih kembali."); return
        }
        let usesContinuity = device.transport == kAudioDeviceTransportTypeContinuityCaptureWired
            || device.transport == kAudioDeviceTransportTypeContinuityCaptureWireless
        let receiverStopped = phoneSpeakerEnabled && usesContinuity
        if receiverStopped { setPhoneSpeakerEnabled(false) }
        changeHardware(english: "Microphone changed to \(device.name)." + (receiverStopped ? " Safari listening was turned off so the iPhone can be used as a microphone." : ""), indonesian: "Mikrofon diganti ke \(device.name)." + (receiverStopped ? " Penerima Safari dimatikan agar iPhone dapat dipakai sebagai mikrofon." : "")) { inputUID = uid }
    }
    func selectMonitor(_ uid: String) {
        guard !starting, uid != monitorUID else { return }
        guard let device = headphones.first(where: { $0.uid == uid }) else {
            error = t("Output unavailable. Refresh Devices and select it again.", "Output tidak tersedia. Muat ulang perangkat lalu pilih kembali."); return
        }
        changeHardware(english: "Speaker changed to \(device.name).", indonesian: "Speaker diganti ke \(device.name).") { monitorUID = uid }
    }
    func setMonitoring(_ enabled: Bool) {
        guard !starting, enabled != monitoring else { return }
        guard !enabled || selectedMonitor != nil else {
            error = t("Select an available speaker or headphones before enabling Live Monitoring.", "Pilih speaker atau headphone yang tersedia sebelum mengaktifkan dengar langsung."); return
        }
        changeHardware(english: enabled ? "Live Monitoring enabled." : "Live Monitoring disabled.", indonesian: enabled ? "Dengar langsung diaktifkan." : "Dengar langsung dimatikan.") { monitoring = enabled }
    }
    func setPhoneSpeakerEnabled(_ enabled: Bool) {
        guard enabled != phoneSpeakerEnabled else { return }
        error = nil
        if enabled {
            guard selectedInput?.transport != kAudioDeviceTransportTypeContinuityCaptureWired,
                  selectedInput?.transport != kAudioDeviceTransportTypeContinuityCaptureWireless else {
                error = t("For Safari on the same iPhone, first select a Mac/USB/Bluetooth microphone. Opening Safari pauses the iPhone Continuity microphone.", "Untuk Safari pada iPhone yang sama, pilih mikrofon Mac/USB/Bluetooth dahulu. Membuka Safari menjeda mikrofon Continuity iPhone."); return
            }
            do {
                try phoneSpeaker.start()
                phoneSpeakerEnabled = true
                notice = t("Open the speaker link in Safari on your iPhone on the same Wi-Fi, then tap Listen.", "Buka tautan speaker di Safari iPhone pada Wi-Fi yang sama, lalu ketuk Dengarkan.")
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
        notice = t("Speaker link copied. Open it in Safari on your iPhone on the same Wi-Fi.", "Tautan speaker disalin. Buka di Safari iPhone pada Wi-Fi yang sama.")
    }
    func openPhoneSpeakerPreview() {
        guard let url = phoneSpeakerURLs.first else { return }
        NSWorkspace.shared.open(url)
    }
    private func changeHardware(english: String, indonesian: String, apply: () -> Void) {
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
                if resumeRecording { notice = t("Your previous recording was saved. The microphone could not restart.", "Rekaman sebelumnya sudah disimpan. Mikrofon belum berhasil diaktifkan kembali.") }
                return
            }
            if resumeRecording {
                beginRecording()
                notice = recording
                    ? t(english + " Your previous recording was saved; recording continues in a new file.", indonesian + " Rekaman sebelumnya disimpan; perekaman berlanjut di file baru.")
                    : t(english + " Your previous recording was saved. A new recording has not started.", indonesian + " Rekaman sebelumnya disimpan. Rekaman baru belum dimulai.")
            } else {
                notice = t(english + (virtualMic == nil ? " Install the driver to use the output in your browser." : ""), indonesian + (virtualMic == nil ? " Pasang driver untuk memakai output di browser." : ""))
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
        for attempt in 0..<3 {
            if attempt > 0 {
                do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
            }
            await startSession()
            if active || permissionDenied || selectedInput == nil { break }
        }
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
            error = t("Microphone access is not allowed. Open Privacy Settings, enable iHearYou, and try again.", "Akses mikrofon belum diizinkan. Buka Pengaturan Privasi, aktifkan iHearYou, lalu coba lagi.")
            return
        }
        refreshDevices()
        guard let input = selectedInput else { error = t("Selected microphone unavailable. Connect it and click Refresh Devices.", "Mikrofon terpilih tidak tersedia. Sambungkan mikrofon lalu tekan Muat ulang perangkat."); return }
        if let seen = bluetoothSeenAt[input.uid] {
            let remaining = 0.75 - Date().timeIntervalSince(seen)
            if remaining > 0 {
                do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                catch { return }
                refreshDevices()
                guard selectedInput?.id == input.id else {
                    error = t("Bluetooth microphone changed while connecting. Select it again.", "Mikrofon Bluetooth berubah saat tersambung. Pilih kembali perangkat.")
                    return
                }
            }
        }
        do {
            let monitor = monitoring ? selectedMonitor : nil
            if monitoring && monitor == nil { throw AudioFailure.message(t("Select headphones for Live Monitoring.", "Pilih headphone untuk dengar langsung.")) }
            try session.start(input: input, virtual: virtualMic, monitor: monitor, enabled: suppression, strength: mode.strength, gain: Float(gain), gate: mode == .strong)
            runningInputID = input.id; runningMonitorID = monitor?.id
            active = true
            sessionStarted = Date(); sessionSeconds = 0
            if virtualMic == nil { notice = t("Recording is ready. Install the driver to use iHearYou in meeting apps.", "Mode rekaman siap. Pasang driver untuk memakai iHearYou di aplikasi meeting.") }
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        recoveryGeneration = UUID()
        if recoveryTask != nil { recoveryTask?.cancel(); recoveryTask = nil; starting = false }
        let wasRecording = recording
        session.stop(); active = false; recording = false; seconds = 0
        runningInputID = nil; runningMonitorID = nil
        sessionStarted = nil; sessionSeconds = 0
        inputDB = -90; outputDB = -90; voice = 0
        originalHistory = [Float](repeating: 0, count: 72); cleanHistory = originalHistory
        if wasRecording { refreshRecordings(); notice = t("Recording saved in Music/iHearYou.", "Rekaman disimpan di Musik/iHearYou.") }
    }
    func toggleRecording() {
        guard !starting else { return }
        error = nil
        if recording {
            session.stopRecording(); recording = false; seconds = 0
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self else { return }
                self.refreshRecordings()
                if !self.recording { self.screen = .recordings; self.showSettings() }
            }
            notice = t("Clean and original recordings were saved.", "Rekaman bersih dan suara asli sudah disimpan.")
        } else {
            if active { beginRecording() }
            else {
                Task { @MainActor [self] in
                    await start()
                    if active && !recording { beginRecording() }
                }
            }
        }
    }
    private func beginRecording() {
        do { try session.startRecording(); recording = true; seconds = 0; notice = nil }
        catch { self.error = error.localizedDescription }
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
                stop(); error = t("Noise reduction failed to process audio. Start the microphone again.", "Mesin peredaman gagal memproses audio. Aktifkan kembali mikrofon."); return
            }
            originalHistory.removeFirst(); originalHistory.append(level(inputDB))
            cleanHistory.removeFirst(); cleanHistory.append(level(outputDB))
            if recording && !snapshot.isRecording { recording = false; refreshRecordings() }
            if let message = snapshot.recordingError { error = L10n.retranslate(message, language: language) }
        }
        if playingURL != nil && player?.isPlaying != true { playingURL = nil; player = nil }
    }
    func level(_ db: Float) -> Float { max(0, min(1, (db + 60) / 60)) }
    func refreshRecordings() {
        do { recordings = try RecordingStore.list() }
        catch { self.error = t("Could not open the recordings folder: \(error.localizedDescription)", "Folder rekaman tidak bisa dibuka: \(error.localizedDescription)") }
    }
    func play(_ url: URL) {
        if playingURL == url { stopPlayback(); return }
        stopPlayback()
        guard !recording else { error = t("Save the current recording before playback.", "Simpan rekaman yang sedang berjalan sebelum memutar audio."); return }
        if active { stop() }
        do { player = try AVAudioPlayer(contentsOf: url); player?.play(); playingURL = url }
        catch { self.error = t("Could not play recording: \(error.localizedDescription)", "Rekaman tidak bisa diputar: \(error.localizedDescription)") }
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
            notice = t("Recording exported to \(destination.lastPathComponent).", "Rekaman diekspor ke \(destination.lastPathComponent).")
        } catch { self.error = error.localizedDescription }
    }
    private func copyForReplacement(_ source: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try FileManager.default.copyItem(at: source, to: temp); return temp
    }
    func installDriver() {
        guard !active else { error = t("Stop the microphone before installing the driver.", "Hentikan mikrofon sebelum memasang driver."); return }
        guard let url = Bundle.main.url(forResource: "iHearYouMicrophone", withExtension: "pkg") else {
            error = t("Driver installer missing. Run scripts/build.sh to create the complete app bundle.", "Installer driver tidak ditemukan. Jalankan scripts/build.sh untuk membuat bundle lengkap."); return
        }
        NSWorkspace.shared.open(url)
        notice = t("Follow the macOS installer. Refresh Devices afterward. Restart your Mac if the driver does not appear.", "Ikuti installer macOS. Setelah selesai, muat ulang perangkat. Restart Mac jika driver belum muncul.")
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
            guard virtualMic != nil else { error = t("Install the iHearYou Microphone driver to record in your browser.", "Pasang driver iHearYou Microphone untuk merekam melalui browser."); return }
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
