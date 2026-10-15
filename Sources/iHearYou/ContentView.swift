// iHearYou | Signature: i729
import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 182)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.screen == .microphone ? model.t("Settings", "Pengaturan") : model.screen.title).font(.system(size: 28, weight: .semibold))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button { model.showMainWindow() } label: {
                        Label(model.t("Open controls", "Buka kontrol"), systemImage: "waveform.circle")
                            .font(.system(size: 11))
                    }.buttonStyle(.bordered)
                }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 22)
                Divider().overlay(Palette.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = model.error { message(error, error: true) }
                        if let notice = model.notice { message(notice, error: false) }
                        switch model.screen {
                        case .microphone: MicrophoneView()
                        case .recordings: RecordingsView()
                        case .guide: GuideView()
                        }
                    }.padding(30)
                }
            }
        }
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .preferredColorScheme(model.appearance.colorScheme)
        .environment(\.locale, model.language.locale)
    }
    var subtitle: String {
        switch model.screen {
        case .microphone: return model.t("Configure appearance, noise cancellation, and audio devices.", "Atur tampilan, peredaman, dan perangkat audio.")
        case .recordings: return model.t("Listen to original and noise-reduced audio.", "Dengarkan suara asli dan hasil peredaman.")
        case .guide: return model.t("Set up your microphone for recordings and calls.", "Siapkan mikrofon untuk rekaman dan panggilan.")
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("iHearYou").font(.system(size: 25, weight: .bold)).padding(.top, 46).padding(.bottom, 6)
            Text(model.t("Settings", "Pengaturan")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                .padding(.bottom, 36)
            ForEach(Screen.allCases, id: \.self) { screen in
                Button { model.screen = screen; if screen == .recordings { model.refreshRecordings() } } label: {
                    Label(screen == .microphone ? model.t("Audio & appearance", "Audio & tampilan") : screen.title, systemImage: icon(screen))
                        .font(.system(size: 13, weight: model.screen == screen ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 13)
                        .background(model.screen == screen ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Spacer(minLength: 40)
            HStack(spacing: 7) {
                Circle().fill(model.active ? Palette.accent : Palette.secondary).frame(width: 6, height: 6)
                Text(model.active ? model.t("Microphone active", "Mikrofon aktif") : model.t("Microphone stopped", "Mikrofon berhenti")).font(.system(size: 11))
            }.padding(.bottom, 20)
            Divider().overlay(Palette.line)
            Text(model.t("Created by i729", "Dibuat oleh i729")).font(.system(size: 12, weight: .medium)).padding(.top, 18)
            Text(model.t("Version \(model.appVersion) • No trial", "Versi \(model.appVersion) • Tanpa trial")).font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.top, 10).padding(.bottom, 24)
        }.padding(.horizontal, 18).background(Palette.sidebar)
    }
    func icon(_ screen: Screen) -> String {
        switch screen { case .microphone: return "mic"; case .recordings: return "waveform"; case .guide: return "slider.horizontal.3" }
    }
    func message(_ text: String, error: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: error ? "exclamationmark.triangle" : "info.circle")
            Text(text).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Button { if error { model.error = nil } else { model.notice = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel(model.t("Dismiss message", "Tutup pesan"))
        }.padding(14).background(error ? Palette.errorBackground : Palette.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MicrophoneView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.t("Appearance", "Tampilan")).font(.system(size: 17, weight: .semibold))
                HStack {
                    Text(model.t("Appearance", "Tampilan")).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker(model.t("Appearance", "Tampilan"), selection: $model.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
                }
                Text(model.t("System follows the macOS appearance. Your choice applies to controls, Settings, and the floating control.", "Sistem mengikuti tampilan macOS. Pilihan berlaku untuk kontrol, Pengaturan, dan kontrol mengambang."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                HStack {
                    Text(model.t("Language", "Bahasa")).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker(model.t("Language", "Bahasa"), selection: $model.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
                }
                Divider().overlay(Palette.line)
                Toggle(model.t("Show floating control", "Tampilkan kontrol mengambang"), isOn: $model.showFloating).font(.system(size: 12))
            }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.t("Audio source", "Sumber suara")).font(.system(size: 12, weight: .medium))
                    Picker(model.t("Microphone", "Mikrofon"), selection: Binding(get: { model.inputUID }, set: { model.selectInput($0) })) {
                        if model.microphones.isEmpty { Text(model.t("No microphone found", "Mikrofon tidak ditemukan")).tag("") }
                        if !model.inputUID.isEmpty && model.selectedInput == nil { Text(model.t("Selected microphone disconnected", "Mikrofon terpilih terputus")).tag(model.inputUID) }
                        ForEach(model.microphones) { Text($0.selectionLabel).tag($0.uid) }
                    }.labelsHidden().controlSize(.large).disabled(model.starting)
                        .help(model.selectedInput?.selectionLabel ?? model.t("Choose a microphone", "Pilih mikrofon"))
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { model.toggle() } label: {
                    Label(model.starting ? model.t("Starting...", "Memulai...") : model.active ? model.t("Stop", "Hentikan") : model.t("Start microphone", "Aktifkan mikrofon"), systemImage: model.active ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStart && !model.active)
            }
            if model.permissionDenied {
                Button(model.t("Allow microphone access in Privacy Settings", "Izinkan mikrofon di Pengaturan Privasi")) { model.openPrivacy() }.buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .center) {
                    Image(systemName: "waveform.path").font(.system(size: 24)).frame(width: 38)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.t("Noise cancellation", "Peredaman bising")).font(.system(size: 19, weight: .semibold))
                        Text(model.suppression ? model.t("Reduce background noise while preserving speech.", "Redam gangguan, pertahankan suara bicara.") : model.t("Original audio passes through without noise cancellation.", "Suara asli diteruskan tanpa peredaman."))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Toggle(model.t("Noise cancellation", "Peredaman bising"), isOn: $model.suppression).labelsHidden().toggleStyle(.switch).controlSize(.large)
                }
                Divider()
                HStack(spacing: 18) {
                    Picker(model.t("Intensity", "Intensitas"), selection: $model.mode) {
                        ForEach(SuppressionMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 250).disabled(!model.suppression)
                    Text(model.suppressionExplanation).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(model.t("Hear the difference", "Dengar perbedaannya")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(model.active ? (model.voice > 0.5 ? model.t("Audio active", "Audio aktif") : model.t("Waiting for speech", "Menunggu ucapan")) : model.t("Start the microphone to monitor audio", "Aktifkan mikrofon untuk memantau"))
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.72))
                }
                SignalTrack(title: model.t("Original audio", "Suara asli"), db: model.inputDB, values: model.originalHistory, color: Color(red: 0.76, green: 0.73, blue: 0.69))
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                SignalTrack(title: model.t("Clean audio", "Hasil bersih"), db: model.outputDB, values: model.cleanHistory, color: Palette.clean)
                HStack {
                    Text(model.t("Live audio levels • dBFS", "Level audio langsung • dBFS")).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.72))
                    Spacer()
                    if model.recording { Text(model.elapsed).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Palette.clean) }
                    Button { model.toggleRecording() } label: {
                        HStack {
                            Image(systemName: model.recording ? "stop.fill" : "record.circle")
                                .foregroundStyle(model.recording ? Color.red : Color.white)
                            Text(model.recording ? model.t("Save recording", "Simpan rekaman") : model.t("Record audio", "Rekam suara"))
                        }.font(.system(size: 12, weight: .medium))
                    }.buttonStyle(.bordered).tint(.white).disabled(model.starting || (!model.active && !model.canStart))
                }.padding(.top, 3)
            }.padding(22).background(Palette.signalBackground, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)

            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.t("Audio volume", "Volume suara")).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%+.0f dB", model.gain)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary)
                    }
                    Slider(value: $model.gain, in: -12...12, step: 1).accessibilityLabel(model.t("Audio gain", "Gain suara"))
                    Text(model.t("Lower this if the audio is too loud.", "Turunkan jika hasil suara terlalu keras.")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(model.t("Live monitoring", "Dengar langsung"), isOn: Binding(get: { model.monitoring }, set: { model.setMonitoring($0) }))
                        .font(.system(size: 12, weight: .medium)).disabled(model.starting)
                    Picker(model.t("Speaker / headphones", "Speaker / headphone"), selection: Binding(get: { model.monitorUID }, set: { model.selectMonitor($0) })) {
                        if model.headphones.isEmpty { Text(model.t("No output found", "Output tidak ditemukan")).tag("") }
                        if !model.monitorUID.isEmpty && model.selectedMonitor == nil { Text(model.t("Selected output disconnected", "Output terpilih terputus")).tag(model.monitorUID) }
                        ForEach(model.headphones) { Text($0.selectionLabel).tag($0.uid) }
                    }.labelsHidden().disabled(model.starting).help(model.selectedMonitor?.selectionLabel ?? model.t("Choose an output", "Pilih output"))
                    Text(model.t("Use headphones to avoid feedback.", "Gunakan headphone untuk menghindari feedback.")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            PhoneSpeakerControls().padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            Divider().overlay(Palette.line)
            HStack(alignment: .center) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.virtualMic == nil ? model.t("Output to other apps is not ready", "Output ke aplikasi lain belum siap") : "Output: iHearYou Microphone")
                        .font(.system(size: 12, weight: .medium))
                    Text(model.virtualMic == nil ? model.t("WAV recording is available without the driver.", "Rekaman WAV tetap bisa dipakai tanpa driver.") : model.t("Select this microphone in your meeting or recording app.", "Pilih mikrofon ini di aplikasi meeting atau perekam."))
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button(model.virtualMic == nil ? model.t("Set up driver", "Siapkan driver") : model.t("Guide", "Panduan")) { model.screen = .guide }.buttonStyle(.bordered)
            }
            HStack {
                Label(model.t("Audio is processed on your Mac", "Audio diproses di Mac"), systemImage: "desktopcomputer").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                Button(model.t("Record in browser", "Rekam lewat browser")) { model.openBrowserRecorder() }.buttonStyle(.borderedProminent)
                    .disabled(model.starting)
            }
            Text(model.t("For voice-over on other websites, choose iHearYou Microphone as the site input. The floating control stays visible as you switch apps.", "Untuk voice-over di situs lain, pilih iHearYou Microphone sebagai input situs. Floating control tetap terlihat saat kamu berpindah aplikasi."))
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if model.inputDrops > 0 && model.active {
                Text(model.t("Audio processing fell behind. Close demanding apps if you hear dropouts.", "Audio sempat terlambat diproses. Tutup aplikasi berat jika terdengar putus-putus."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct PhoneSpeakerControls: View {
    @EnvironmentObject var model: AppModel
    @State private var code: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(model.t("iPhone speaker via Safari", "Speaker iPhone via Safari"), isOn: Binding(get: { model.phoneSpeakerEnabled }, set: { model.setPhoneSpeakerEnabled($0) }))
                .font(.system(size: 14, weight: .semibold)).toggleStyle(.switch)
            Text(model.t("Use a Mac, USB, or Bluetooth microphone. Connect your iPhone to the same Wi-Fi, scan the code, then tap Listen in Safari. Keep the tab and iPhone screen open.", "Pakai mikrofon Mac/USB/Bluetooth. Sambungkan iPhone ke Wi-Fi yang sama, pindai kode, lalu ketuk Dengarkan di Safari. Biarkan tab dan layar iPhone terbuka."))
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if model.phoneSpeakerEnabled {
                Text(model.phoneSpeakerConnected ? model.t("● Receiver connected", "● Penerima terhubung") : model.t("Waiting for a Safari receiver", "Menunggu penerima Safari"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(model.phoneSpeakerConnected ? Palette.clean : Palette.secondary)
                if let url = model.phoneSpeakerURLs.first {
                    HStack(alignment: .top, spacing: 16) {
                        if let code {
                            Image(nsImage: code).resizable().interpolation(.none).frame(width: 110, height: 110)
                                .padding(8).background(.white).accessibilityLabel(model.t("QR code for the iPhone speaker link", "Kode QR tautan speaker iPhone"))
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(url.absoluteString).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button(model.t("Copy link", "Salin tautan")) { model.copyPhoneSpeakerURL() }.buttonStyle(.bordered)
                                Button(model.t("Preview on Mac", "Preview di Mac")) { model.openPhoneSpeakerPreview() }.buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    Text(model.t("Preparing local network link…", "Menyiapkan tautan jaringan lokal…")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Text(model.t("Audio streams directly over your local network. The link allows listening until this mode is turned off. Use a low volume or earphones to avoid feedback.", "Audio dikirim langsung melalui jaringan lokal. Tautan memberi akses mendengarkan sampai mode ini dimatikan. Gunakan volume rendah atau earphone untuk menghindari feedback."))
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }.onChange(of: model.phoneSpeakerURLs.first, initial: true) { _, url in
            guard let url else { code = nil; return }
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(url.absoluteString.utf8)
            filter.correctionLevel = "M"
            guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 5, y: 5)),
                  let bitmap = CIContext().createCGImage(image, from: image.extent) else { code = nil; return }
            code = NSImage(cgImage: bitmap, size: image.extent.size)
        }
    }
}

struct SignalTrack: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let db: Float
    let values: [Float]
    let color: Color
    var body: some View {
        HStack(spacing: 20) {
            Text(title).font(.system(size: 12)).frame(width: 85, alignment: .leading)
            GeometryReader { geometry in
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 1).fill(color)
                            .frame(width: max(1, (geometry.size.width - CGFloat(values.count - 1) * 3) / CGFloat(values.count)),
                                   height: max(2, CGFloat(value) * geometry.size.height))
                    }
                }.frame(height: geometry.size.height)
            }.frame(height: 43).accessibilityHidden(true)
            Text(db <= -89 ? model.t("Silence", "Hening") : String(format: "%.0f dB", db))
                .font(.system(size: 11, design: .monospaced)).frame(width: 55, alignment: .trailing)
        }.accessibilityElement(children: .combine)
    }
}

struct RecordingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("WAV • 48 kHz • Mono").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer()
                Button(model.t("Refresh", "Muat ulang")) { model.refreshRecordings() }.buttonStyle(.bordered)
                Button(model.t("Open folder", "Buka folder")) { model.revealRecordings() }.buttonStyle(.bordered)
            }
            Text(model.t("\(model.recordings.count) saved recordings", "\(model.recordings.count) rekaman tersimpan"))
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            if model.active {
                HStack {
                    Text(model.t("Playback stops the microphone automatically to avoid feedback.", "Pemutaran otomatis menghentikan mikrofon agar tidak terjadi feedback."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button(model.t("Stop microphone", "Hentikan mikrofon")) { model.stop() }.buttonStyle(.bordered)
                }
            }
            if model.recordings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform").font(.system(size: 38)).foregroundStyle(Palette.secondary)
                    Text(model.t("No recordings yet", "Belum ada rekaman")).font(.system(size: 20, weight: .semibold))
                    Text(model.t("Start the microphone, then press Record audio.\nOriginal and clean versions are saved together.", "Aktifkan mikrofon, lalu tekan Rekam suara.\nVersi asli dan hasil bersih disimpan berpasangan."))
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    Button(model.t("Open microphone controls", "Buka kontrol mikrofon")) { model.screen = .microphone }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(.vertical, 90)
            }
            ForEach(model.recordings) { recording in
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recording.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(model.language.locale))).font(.system(size: 15, weight: .medium))
                            Text(recording.title).font(.system(size: 10)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        Text(String(format: "%02d:%02d", Int(recording.duration) / 60, Int(recording.duration) % 60))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    HStack {
                        Button { model.play(recording.rawURL) } label: {
                            Label(model.playingURL == recording.rawURL ? model.t("Stop", "Hentikan") : model.t("Original audio", "Suara asli"), systemImage: model.playingURL == recording.rawURL ? "stop.fill" : "play.fill")
                        }.buttonStyle(.bordered).disabled(model.recording || !FileManager.default.fileExists(atPath: recording.rawURL.path))
                        Button { model.play(recording.cleanURL) } label: {
                            Label(model.playingURL == recording.cleanURL ? model.t("Stop", "Hentikan") : model.t("Clean audio", "Hasil bersih"), systemImage: model.playingURL == recording.cleanURL ? "stop.fill" : "play.fill")
                        }.buttonStyle(.borderedProminent).disabled(model.recording)
                        Spacer()
                        Button(model.t("Export WAV", "Ekspor WAV")) { model.export(recording) }.buttonStyle(.bordered)
                    }
                }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }.onAppear { model.refreshRecordings() }
    }
}

struct GuideView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "mic.badge.plus").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("iHearYou Microphone").font(.system(size: 19, weight: .semibold))
                        Text(model.virtualMic == nil ? model.t("The driver is not installed or has not been loaded by macOS.", "Driver belum terpasang atau belum dimuat macOS.") : model.t("The driver is detected and ready to use.", "Driver terdeteksi dan siap digunakan."))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
                Text(model.t("The driver makes clean audio available as a microphone in other apps. The installer asks for your macOS administrator password and restarts the audio service. Save recordings and end calls before installing.", "Driver membuat suara bersih tersedia sebagai mikrofon di aplikasi lain. Installer meminta password admin macOS dan memuat ulang layanan audio. Simpan rekaman dan tutup panggilan sebelum memasang."))
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(model.virtualMic == nil ? model.t("Install microphone driver", "Pasang driver mikrofon") : model.t("Reinstall driver", "Pasang ulang driver")) { model.installDriver() }
                        .buttonStyle(.borderedProminent).disabled(model.recording)
                    Button(model.t("Refresh devices", "Muat ulang perangkat")) { model.refreshDevices() }.buttonStyle(.bordered)
                }
            }.padding(24).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 17) {
                Text(model.t("For meetings and recording apps", "Untuk meeting atau aplikasi rekaman")).font(.system(size: 17, weight: .semibold))
                instruction("1", model.t("Choose a microphone source", "Pilih sumber mikrofon"), model.t("In the compact controls or Settings → Audio & appearance, choose a Mac, iPhone, USB, or headset microphone recognized by macOS. Enable noise cancellation, then start the microphone.", "Di kontrol ringkas atau Pengaturan → Audio & tampilan, pilih mikrofon Mac, iPhone, USB, atau headset yang dikenali macOS. Aktifkan peredaman bising lalu Aktifkan mikrofon."))
                instruction("2", model.t("Select iHearYou Microphone in the target app", "Pilih iHearYou Microphone di aplikasi tujuan"), model.t("Open the audio settings in Zoom, Meet, Discord, OBS, or your recorder. Use iHearYou Microphone as the input. Keep the output set to your usual headphones or speakers.", "Buka pengaturan audio Zoom, Meet, Discord, OBS, atau perekam. Gunakan iHearYou Microphone sebagai input. Biarkan output speaker pada headphone atau speaker biasa."))
                instruction("3", model.t("Keep iHearYou running", "Biarkan iHearYou berjalan"), model.t("Closing the window keeps processing running. Controls are also available in the menu bar. Quitting the app stops the virtual microphone.", "Menutup jendela tidak menghentikan proses. Kontrol juga tersedia di menu bar. Keluar dari aplikasi akan menghentikan mikrofon virtual."))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(model.t("iPhone, Bluetooth, and wired devices", "iPhone, Bluetooth, dan perangkat kabel")).font(.system(size: 17, weight: .semibold))
                Text(model.t("The iPhone microphone is available through Continuity Camera over USB or wirelessly. For USB, tap Trust on your iPhone. For wireless use, sign in to the same Apple Account and enable Wi-Fi and Bluetooth on both devices. Once the device appears in macOS, press Refresh devices and choose its name under Microphone.", "Mikrofon iPhone tersedia melalui Continuity Camera, lewat USB atau nirkabel. Untuk USB, izinkan Trust pada iPhone. Untuk nirkabel, gunakan Apple Account yang sama dan aktifkan Wi-Fi serta Bluetooth pada kedua perangkat. Setelah perangkat muncul di macOS, tekan Muat ulang perangkat lalu pilih namanya di Mikrofon."))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(model.t("Pair Bluetooth headsets or speakers in macOS settings; connect wired or USB microphones and headphones as usual. iHearYou lists available input and output devices. An iPhone Continuity device that only provides a microphone appears under Microphone, not Speaker. Speaker is used for live monitoring; the browser input remains iHearYou Microphone.", "Pasangkan headset atau speaker Bluetooth melalui pengaturan macOS; sambungkan mikrofon dan headphone kabel atau USB seperti biasa. iHearYou menampilkan perangkat input dan output yang tersedia. iPhone Continuity yang hanya menyediakan mikrofon muncul di Mikrofon, bukan Speaker. Speaker dipakai untuk Dengar langsung; input browser tetap iHearYou Microphone."))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(model.t("You can switch devices while the microphone is active. During WAV recording, the current file is saved and recording continues in a new file. Disconnecting a device stops the session so it does not silently switch to another microphone.", "Perangkat dapat diganti saat mikrofon aktif. Jika sedang merekam WAV, file sebelumnya disimpan dan perekaman berlanjut di file baru. Perangkat yang terputus menghentikan sesi agar tidak diam-diam berpindah ke mikrofon lain."))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                HStack {
                    Button(model.t("Refresh devices", "Muat ulang perangkat")) { model.refreshDevices() }.buttonStyle(.bordered).disabled(model.starting)
                    Link(model.t("Apple Continuity guide", "Panduan Continuity dari Apple"), destination: URL(string: "https://support.apple.com/102546")!)
                        .font(.system(size: 12))
                }
            }
            PhoneSpeakerControls().padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 14) {
                Text(model.t("Voice-over in Brave / MargVoice", "Voice-over di Brave / MargVoice")).font(.system(size: 17, weight: .semibold))
                Text(model.t("In Brave, open Settings → Privacy and security → Site and Shields Settings → Microphone. Choose iHearYou Microphone (Virtual). Allow microphone access for margvoice.com. If a recording session is already open, reopen it to detect the new input. Check that the Clean audio meter moves before recording.", "Di Brave, buka Settings → Privacy and security → Site and Shields Settings → Microphone. Pilih iHearYou Microphone (Virtual). Izinkan mikrofon untuk margvoice.com. Jika sesi rekaman sudah terbuka, buka ulang sesi agar input baru terbaca. Pastikan meter Hasil bersih bergerak sebelum mulai merekam."))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                HStack {
                    Button(model.t("Test local browser recording", "Uji rekaman browser lokal")) { model.openBrowserRecorder() }.buttonStyle(.borderedProminent)
                    Button(model.t("Open MargVoice", "Buka MargVoice")) { NSWorkspace.shared.open(URL(string: "https://margvoice.com/projects/reading")!) }.buttonStyle(.bordered)
                }
                Toggle(model.t("Show floating control", "Tampilkan kontrol mengambang"), isOn: $model.showFloating).font(.system(size: 12))
            }
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.t("If you cannot hear audio", "Jika audio belum terdengar")).font(.system(size: 16, weight: .semibold))
                Text(model.t("Make sure microphone access is allowed and the audio meters move. After installing the driver, reopen the target app. Restart your Mac if the device does not appear. Disable additional noise suppression in the target app if speech sounds cut off.", "Pastikan akses mikrofon diizinkan dan meter suara bergerak. Setelah memasang driver, buka ulang aplikasi tujuan. Restart Mac jika perangkat belum muncul. Matikan noise suppression tambahan di aplikasi tujuan jika suara terdengar terpotong."))
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Button(model.t("Open Microphone Privacy Settings", "Buka Pengaturan Privasi Mikrofon")) { model.openPrivacy() }.buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(model.t("Audio and privacy", "Suara dan privasi")).font(.system(size: 16, weight: .semibold))
                Text(model.t("Audio is processed locally without an account or uploads. Recordings are saved in Music/iHearYou. DPDFNet2 reduces background noise; overlapping voices, strong echoes, and clipped microphone audio cannot always be separated. Keep your microphone close to your mouth for better results.", "Audio diproses lokal tanpa akun atau unggahan. File rekaman disimpan di Musik/iHearYou. DPDFNet2 meredam noise latar; suara orang lain yang berbicara bersamaan, gema berat, dan mikrofon yang sudah clipping tidak selalu bisa dipisahkan. Gunakan mikrofon dekat mulut untuk hasil lebih baik."))
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("Created by i729", "Dibuat oleh i729")).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
                Text(model.t("iHearYou \(model.appVersion) • Original app code • No trial or subscription", "iHearYou \(model.appVersion) • Kode aplikasi sendiri • Tanpa trial atau langganan")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text(model.t("Noise suppression: DPDFNet2 / CEVA. Runtime: sherpa-onnx / ONNX Runtime. Driver derived from BlackHole / Existential Audio, GPLv3. License notices are included in the app bundle and project source.", "Noise suppression: DPDFNet2 / CEVA. Runtime: sherpa-onnx / ONNX Runtime. Driver turunan BlackHole / Existential Audio, GPLv3. Pemberitahuan lisensi ada di bundle aplikasi dan source project."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
    }
    func instruction(_ index: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(index).font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26)
                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(text).font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
