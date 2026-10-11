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
                        Text(model.screen == .microphone ? "Settings" : model.screen.rawValue).font(.system(size: 28, weight: .semibold))
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button { model.showMainWindow() } label: {
                        Label("Buka kontrol", systemImage: "waveform.circle")
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
    }
    var subtitle: String {
        switch model.screen {
        case .microphone: return "Atur tampilan, peredaman, dan perangkat audio."
        case .recordings: return "Dengarkan suara asli dan hasil peredaman."
        case .guide: return "Siapkan mikrofon untuk rekaman dan panggilan."
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("iHearYou").font(.system(size: 25, weight: .bold)).padding(.top, 46).padding(.bottom, 6)
            Text("Settings").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                .padding(.bottom, 36)
            ForEach(Screen.allCases, id: \.self) { screen in
                Button { model.screen = screen; if screen == .recordings { model.refreshRecordings() } } label: {
                    Label(screen == .microphone ? "Audio & tampilan" : screen.rawValue, systemImage: icon(screen))
                        .font(.system(size: 13, weight: model.screen == screen ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 13)
                        .background(model.screen == screen ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Spacer(minLength: 40)
            HStack(spacing: 7) {
                Circle().fill(model.active ? Palette.accent : Palette.secondary).frame(width: 6, height: 6)
                Text(model.active ? "Mikrofon aktif" : "Mikrofon berhenti").font(.system(size: 11))
            }.padding(.bottom, 20)
            Divider().overlay(Palette.line)
            Text("Dibuat oleh i729").font(.system(size: 12, weight: .medium)).padding(.top, 18)
            Text("Versi \(model.appVersion) • Tanpa trial").font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.top, 10).padding(.bottom, 24)
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
                .buttonStyle(.plain).accessibilityLabel("Tutup pesan")
        }.padding(14).background(error ? Palette.errorBackground : Palette.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MicrophoneView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tampilan").font(.system(size: 17, weight: .semibold))
                HStack {
                    Text("Appearance").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 260).labelsHidden()
                }
                Text("System mengikuti tampilan macOS. Pilihan berlaku untuk kontrol, Settings, dan floating control.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Divider().overlay(Palette.line)
                Toggle("Tampilkan floating control", isOn: $model.showFloating).font(.system(size: 12))
            }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sumber suara").font(.system(size: 12, weight: .medium))
                    Picker("Mikrofon", selection: Binding(get: { model.inputUID }, set: { model.selectInput($0) })) {
                        if model.microphones.isEmpty { Text("Mikrofon tidak ditemukan").tag("") }
                        if !model.inputUID.isEmpty && model.selectedInput == nil { Text("Mikrofon terpilih terputus").tag(model.inputUID) }
                        ForEach(model.microphones) { Text($0.selectionLabel).tag($0.uid) }
                    }.labelsHidden().controlSize(.large).disabled(model.starting)
                        .help(model.selectedInput?.selectionLabel ?? "Pilih mikrofon")
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { model.toggle() } label: {
                    Label(model.starting ? "Memulai..." : model.active ? "Hentikan" : "Aktifkan mikrofon", systemImage: model.active ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canStart && !model.active)
            }
            if model.permissionDenied {
                Button("Izinkan mikrofon di Pengaturan Privasi") { model.openPrivacy() }.buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .center) {
                    Image(systemName: "waveform.path").font(.system(size: 24)).frame(width: 38)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Noise cancellation").font(.system(size: 19, weight: .semibold))
                        Text(model.suppression ? "Redam gangguan, pertahankan suara bicara." : "Suara asli diteruskan tanpa peredaman.")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Toggle("Noise cancellation", isOn: $model.suppression).labelsHidden().toggleStyle(.switch).controlSize(.large)
                }
                Divider()
                HStack(spacing: 18) {
                    Picker("Intensitas", selection: $model.mode) {
                        ForEach(SuppressionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 250).disabled(!model.suppression)
                    Text(model.mode.explanation).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Dengar perbedaannya").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(model.active ? (model.voice > 0.5 ? "Output audio terdeteksi" : "Memantau suara") : "Aktifkan mikrofon untuk memantau")
                        .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.72))
                }
                SignalTrack(title: "Suara asli", db: model.inputDB, values: model.originalHistory, color: Color(red: 0.76, green: 0.73, blue: 0.69))
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                SignalTrack(title: "Hasil bersih", db: model.outputDB, values: model.cleanHistory, color: Palette.clean)
                HStack {
                    Text("Level audio langsung • dBFS").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.72))
                    Spacer()
                    if model.recording { Text(model.elapsed).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Palette.clean) }
                    Button { model.toggleRecording() } label: {
                        Label(model.recording ? "Simpan rekaman" : "Rekam suara", systemImage: model.recording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 12, weight: .medium))
                    }.buttonStyle(.bordered).tint(.white).disabled(!model.active)
                }.padding(.top, 3)
            }.padding(22).background(Palette.signalBackground, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)

            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Volume suara").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%+.0f dB", model.gain)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary)
                    }
                    Slider(value: $model.gain, in: -12...12, step: 1).accessibilityLabel("Gain suara")
                    Text("Turunkan jika hasil suara terlalu keras.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Dengar langsung", isOn: Binding(get: { model.monitoring }, set: { model.setMonitoring($0) }))
                        .font(.system(size: 12, weight: .medium)).disabled(model.starting)
                    Picker("Speaker / headphone", selection: Binding(get: { model.monitorUID }, set: { model.selectMonitor($0) })) {
                        if model.headphones.isEmpty { Text("Output tidak ditemukan").tag("") }
                        if !model.monitorUID.isEmpty && model.selectedMonitor == nil { Text("Output terpilih terputus").tag(model.monitorUID) }
                        ForEach(model.headphones) { Text($0.selectionLabel).tag($0.uid) }
                    }.labelsHidden().disabled(model.starting).help(model.selectedMonitor?.selectionLabel ?? "Pilih output")
                    Text("Gunakan headphone untuk menghindari feedback.").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            PhoneSpeakerControls().padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            Divider().overlay(Palette.line)
            HStack(alignment: .center) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.virtualMic == nil ? "Output ke aplikasi lain belum siap" : "Output: iHearYou Microphone")
                        .font(.system(size: 12, weight: .medium))
                    Text(model.virtualMic == nil ? "Rekaman WAV tetap bisa dipakai tanpa driver." : "Pilih mikrofon ini di aplikasi meeting atau perekam.")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button(model.virtualMic == nil ? "Siapkan driver" : "Panduan") { model.screen = .guide }.buttonStyle(.bordered)
            }
            HStack {
                Label("Audio diproses di Mac", systemImage: "desktopcomputer").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                Button("Rekam lewat browser") { model.openBrowserRecorder() }.buttonStyle(.borderedProminent)
                    .disabled(model.starting)
            }
            Text("Untuk voice-over di situs lain, pilih iHearYou Microphone sebagai input situs. Floating control tetap terlihat saat kamu berpindah aplikasi.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if model.inputDrops > 0 && model.active {
                Text("Audio sempat terlambat diproses. Tutup aplikasi berat jika terdengar putus-putus.")
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
            Toggle("Speaker iPhone via Safari", isOn: Binding(get: { model.phoneSpeakerEnabled }, set: { model.setPhoneSpeakerEnabled($0) }))
                .font(.system(size: 14, weight: .semibold)).toggleStyle(.switch)
            Text("Pakai mikrofon Mac/USB/Bluetooth. Sambungkan iPhone ke Wi-Fi yang sama, pindai kode, lalu ketuk Dengarkan di Safari. Biarkan tab dan layar iPhone terbuka.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if model.phoneSpeakerEnabled {
                Text(model.phoneSpeakerConnected ? "● Penerima terhubung" : "Menunggu penerima Safari")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(model.phoneSpeakerConnected ? Palette.clean : Palette.secondary)
                if let url = model.phoneSpeakerURLs.first {
                    HStack(alignment: .top, spacing: 16) {
                        if let code {
                            Image(nsImage: code).resizable().interpolation(.none).frame(width: 110, height: 110)
                                .padding(8).background(.white).accessibilityLabel("Kode QR tautan speaker iPhone")
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(url.absoluteString).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Salin tautan") { model.copyPhoneSpeakerURL() }.buttonStyle(.bordered)
                                Button("Preview di Mac") { model.openPhoneSpeakerPreview() }.buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    Text("Menyiapkan tautan jaringan lokal…").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Text("Audio dikirim langsung melalui jaringan lokal. Tautan memberi akses mendengarkan sampai mode ini dimatikan. Gunakan volume rendah atau earphone untuk menghindari feedback.")
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
            Text(db <= -89 ? "Silence" : String(format: "%.0f dB", db))
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
                Button("Muat ulang") { model.refreshRecordings() }.buttonStyle(.bordered)
                Button("Buka folder") { model.revealRecordings() }.buttonStyle(.bordered)
            }
            if model.recordings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform").font(.system(size: 38)).foregroundStyle(Palette.secondary)
                    Text("Belum ada rekaman").font(.system(size: 20, weight: .semibold))
                    Text("Aktifkan mikrofon, lalu tekan Rekam suara.\nVersi asli dan hasil bersih disimpan berpasangan.")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                    Button("Buka kontrol mikrofon") { model.screen = .microphone }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(.vertical, 90)
            }
            ForEach(model.recordings) { recording in
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recording.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 15, weight: .medium))
                            Text(recording.title).font(.system(size: 10)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        Text(String(format: "%02d:%02d", Int(recording.duration) / 60, Int(recording.duration) % 60))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    HStack {
                        Button { model.play(recording.rawURL) } label: {
                            Label(model.playingURL == recording.rawURL ? "Hentikan" : "Suara asli", systemImage: model.playingURL == recording.rawURL ? "stop.fill" : "play.fill")
                        }.buttonStyle(.bordered).disabled(model.active || !FileManager.default.fileExists(atPath: recording.rawURL.path))
                        Button { model.play(recording.cleanURL) } label: {
                            Label(model.playingURL == recording.cleanURL ? "Hentikan" : "Hasil bersih", systemImage: model.playingURL == recording.cleanURL ? "stop.fill" : "play.fill")
                        }.buttonStyle(.borderedProminent).disabled(model.active)
                        Spacer()
                        Button("Ekspor WAV") { model.export(recording) }.buttonStyle(.bordered)
                    }
                }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if model.active { Text("Hentikan mikrofon sebelum memutar rekaman agar playback tidak ikut tertangkap.").font(.system(size: 12)).foregroundStyle(Palette.secondary) }
        }
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
                        Text(model.virtualMic == nil ? "Driver belum terpasang atau belum dimuat macOS." : "Driver terdeteksi dan siap digunakan.")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
                Text("Driver membuat suara bersih tersedia sebagai mikrofon di aplikasi lain. Installer meminta password admin macOS dan memuat ulang layanan audio. Simpan rekaman dan tutup panggilan sebelum memasang.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(model.virtualMic == nil ? "Pasang driver mikrofon" : "Pasang ulang driver") { model.installDriver() }
                        .buttonStyle(.borderedProminent).disabled(model.active)
                    Button("Muat ulang perangkat") { model.refreshDevices() }.buttonStyle(.bordered)
                }
            }.padding(24).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 17) {
                Text("Untuk meeting atau aplikasi rekaman").font(.system(size: 17, weight: .semibold))
                instruction("1", "Pilih sumber mikrofon", "Di kontrol ringkas atau Settings → Audio & tampilan, pilih mikrofon Mac, iPhone, USB, atau headset yang dikenali macOS. Aktifkan noise cancellation lalu Aktifkan mikrofon.")
                instruction("2", "Pilih iHearYou Microphone di aplikasi tujuan", "Buka pengaturan audio Zoom, Meet, Discord, OBS, atau perekam. Gunakan iHearYou Microphone sebagai input. Biarkan output speaker pada headphone atau speaker biasa.")
                instruction("3", "Biarkan iHearYou berjalan", "Menutup jendela tidak menghentikan proses. Kontrol juga tersedia di menu bar. Keluar dari aplikasi akan menghentikan mikrofon virtual.")
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("iPhone, Bluetooth, dan perangkat kabel").font(.system(size: 17, weight: .semibold))
                Text("Mikrofon iPhone tersedia melalui Continuity Camera, lewat USB atau nirkabel. Untuk USB, izinkan Trust pada iPhone. Untuk nirkabel, gunakan Apple Account yang sama dan aktifkan Wi-Fi serta Bluetooth pada kedua perangkat. Setelah perangkat muncul di macOS, tekan Muat ulang perangkat lalu pilih namanya di Microphone.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text("Pasangkan headset atau speaker Bluetooth melalui pengaturan macOS; sambungkan mikrofon dan headphone kabel atau USB seperti biasa. iHearYou menampilkan perangkat input dan output yang tersedia. iPhone Continuity yang hanya menyediakan mikrofon muncul di Microphone, bukan Speaker. Speaker dipakai untuk Dengar langsung; input browser tetap iHearYou Microphone.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text("Perangkat dapat diganti saat mikrofon aktif. Jika sedang merekam WAV, file sebelumnya disimpan dan perekaman berlanjut di file baru. Perangkat yang terputus menghentikan sesi agar tidak diam-diam berpindah ke mikrofon lain.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                HStack {
                    Button("Muat ulang perangkat") { model.refreshDevices() }.buttonStyle(.bordered).disabled(model.starting)
                    Link("Panduan Continuity dari Apple", destination: URL(string: "https://support.apple.com/102546")!)
                        .font(.system(size: 12))
                }
            }
            PhoneSpeakerControls().padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 14) {
                Text("Voice-over di Brave / MargVoice").font(.system(size: 17, weight: .semibold))
                Text("Di Brave, buka Settings → Privacy and security → Site and Shields Settings → Microphone. Pilih iHearYou Microphone (Virtual). Izinkan mikrofon untuk margvoice.com. Jika sesi rekaman sudah terbuka, buka ulang sesi agar input baru terbaca. Pastikan meter Hasil bersih bergerak sebelum mulai merekam.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                HStack {
                    Button("Uji rekaman browser lokal") { model.openBrowserRecorder() }.buttonStyle(.borderedProminent)
                    Button("Buka MargVoice") { NSWorkspace.shared.open(URL(string: "https://margvoice.com/projects/reading")!) }.buttonStyle(.bordered)
                }
                Toggle("Tampilkan floating control", isOn: $model.showFloating).font(.system(size: 12))
            }
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 12) {
                Text("Jika audio belum terdengar").font(.system(size: 16, weight: .semibold))
                Text("Pastikan akses mikrofon diizinkan dan meter suara bergerak. Setelah memasang driver, buka ulang aplikasi tujuan. Restart Mac jika perangkat belum muncul. Matikan noise suppression tambahan di aplikasi tujuan jika suara terdengar terpotong.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Button("Buka Pengaturan Privasi Mikrofon") { model.openPrivacy() }.buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Suara dan privasi").font(.system(size: 16, weight: .semibold))
                Text("Audio diproses lokal tanpa akun atau unggahan. File rekaman disimpan di Musik/iHearYou. DPDFNet2 meredam noise latar; suara orang lain yang berbicara bersamaan, gema berat, dan mikrofon yang sudah clipping tidak selalu bisa dipisahkan. Gunakan mikrofon dekat mulut untuk hasil lebih baik.")
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 6) {
                Text("Dibuat oleh i729").font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
                Text("iHearYou \(model.appVersion) • Kode aplikasi sendiri • Tanpa trial atau langganan").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text("Noise suppression: DPDFNet2 / CEVA. Runtime: sherpa-onnx / ONNX Runtime. Driver turunan BlackHole / Existential Audio, GPLv3. Pemberitahuan lisensi ada di bundle aplikasi dan source project.")
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
