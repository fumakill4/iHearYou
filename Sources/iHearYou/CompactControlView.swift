// iHearYou | Signature: i729
import SwiftUI
import AppKit

struct CompactControlView: View {
    @EnvironmentObject var model: AppModel
    @State private var noiseExpanded = true
    @State private var devicesExpanded = true
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = model.error { message(error, isError: true) }
                    if let notice = model.notice { message(notice, isError: false) }
                    Button(action: openMargVoice) {
                        Label(model.t("Voice-over · MargVoice", "Narasi · MargVoice"), systemImage: "globe")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(model.starting)
                        .help(model.t("Start the microphone and open your MargVoice voice-over project", "Aktifkan mikrofon dan buka proyek narasi MargVoice"))
                        .padding(.horizontal, 20).padding(.bottom, 18)
                    separator
                    noiseControls
                    separator
                    deviceControls
                    separator
                    recordingControls
                }
            }.scrollIndicators(.hidden)
            footer
        }
        .frame(width: 360, height: 646)
        .background(Palette.background).foregroundStyle(Palette.ink).tint(Palette.accent)
        .preferredColorScheme(model.appearance.colorScheme)
        .environment(\.locale, model.language.locale)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("iHearYou").font(.system(size: 24, weight: .bold, design: .rounded))
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 17)) }
                .buttonStyle(.plain).help(model.t("Settings", "Pengaturan")).accessibilityLabel(model.t("Settings", "Pengaturan"))
                .frame(width: 27, height: 30)
            Menu {
                Toggle(model.t("Floating control", "Kontrol mengambang"), isOn: $model.showFloating)
                Button(model.t("Recordings", "Rekaman")) { model.refreshRecordings(); model.screen = .recordings; openSettings() }
                Button(model.t("Browser microphone guide", "Panduan mikrofon browser")) { model.screen = .guide; openSettings() }
                Divider()
                Button(model.t("Quit iHearYou", "Keluar iHearYou")) { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 24, height: 30)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(model.t("iHearYou menu", "Menu iHearYou"))
        }.padding(.horizontal, 20).padding(.top, 17).padding(.bottom, 21)
    }

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading(model.t("Noise Cancellation", "Peredaman Bising"), isExpanded: $noiseExpanded) {
                Text(model.suppression ? model.t("● ON", "● AKTIF") : model.t("OFF", "NONAKTIF"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.suppression ? Palette.clean : Palette.secondary)
            }
            if noiseExpanded {
                Toggle(model.t("Cancel my noise", "Redam bising saya"), isOn: $model.suppression)
                    .font(.system(size: 13, weight: .medium)).toggleStyle(.switch)
                Picker(model.t("Noise cancellation", "Peredaman bising"), selection: $model.mode) {
                    ForEach(SuppressionMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().disabled(!model.suppression)
                    .accessibilityLabel(model.t("Noise cancellation intensity", "Intensitas peredaman bising"))
                Text(model.mode.explanation).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20)
    }

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(model.t("iHearYou Devices", "Perangkat iHearYou"), isExpanded: $devicesExpanded) {
                Image(systemName: model.virtualMic == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(model.virtualMic == nil ? Color.orange : Palette.clean)
            }
            if devicesExpanded {
                Button { model.toggle() } label: {
                    HStack {
                        Image(systemName: model.active ? "mic.fill" : "mic.slash")
                        Text(model.starting ? model.t("Starting…", "Memulai…") : model.active ? model.t("Microphone active", "Mikrofon aktif") : model.t("Start microphone", "Aktifkan mikrofon"))
                        Spacer()
                        if model.active { Text(model.sessionElapsed).monospacedDigit() }
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(.white).padding(.vertical, 4)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!model.canStart && !model.active)
                    .help(model.active ? model.t("Stop microphone", "Hentikan mikrofon") : model.t("Start microphone", "Aktifkan mikrofon"))
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.t("Microphone", "Mikrofon")).font(.system(size: 11, weight: .medium))
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill").frame(width: 20)
                        Picker(model.t("Microphone", "Mikrofon"), selection: Binding(get: { model.inputUID }, set: { model.selectInput($0) })) {
                            if model.microphones.isEmpty { Text(model.t("No microphone found", "Mikrofon tidak ditemukan")).tag("") }
                            if !model.inputUID.isEmpty && model.selectedInput == nil { Text(model.t("Selected microphone disconnected", "Mikrofon terpilih terputus")).tag(model.inputUID) }
                            ForEach(model.microphones) { Text($0.selectionLabel).tag($0.uid) }
                        }.labelsHidden().frame(maxWidth: .infinity)
                            .disabled(model.starting).help(model.selectedInput?.selectionLabel ?? model.t("Choose a microphone", "Pilih mikrofon"))
                    }.padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.t("Speaker", "Speaker")).font(.system(size: 11, weight: .medium))
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill").frame(width: 20)
                        Picker(model.t("Speaker for live monitoring", "Speaker untuk dengar langsung"), selection: Binding(get: { model.monitorUID }, set: { model.selectMonitor($0) })) {
                            if model.headphones.isEmpty { Text(model.t("No output found", "Output tidak ditemukan")).tag("") }
                            if !model.monitorUID.isEmpty && model.selectedMonitor == nil { Text(model.t("Selected output disconnected", "Output terpilih terputus")).tag(model.monitorUID) }
                            ForEach(model.headphones) { Text($0.selectionLabel).tag($0.uid) }
                        }.labelsHidden().frame(maxWidth: .infinity)
                            .disabled(model.starting).help(model.selectedMonitor?.selectionLabel ?? model.t("Choose an output", "Pilih output"))
                    }.padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 1))
                }
                Toggle(model.t("Live monitoring", "Dengar langsung"), isOn: Binding(get: { model.monitoring }, set: { model.setMonitoring($0) }))
                    .font(.system(size: 12)).toggleStyle(.switch).disabled(model.starting)
                Text(model.t("Use headphones to hear your own voice. The browser input remains iHearYou Microphone.", "Gunakan headphone untuk mendengar suara sendiri. Input browser tetap iHearYou Microphone."))
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                Button(model.t("Refresh devices", "Muat ulang perangkat")) { model.refreshDevices() }.font(.system(size: 11))
                    .buttonStyle(.bordered).disabled(model.starting)
                Toggle(model.t("iPhone speaker via Safari", "Speaker iPhone via Safari"), isOn: Binding(get: { model.phoneSpeakerEnabled }, set: { model.setPhoneSpeakerEnabled($0) }))
                    .font(.system(size: 11)).toggleStyle(.switch)
                if model.phoneSpeakerEnabled {
                    HStack {
                        Text(model.phoneSpeakerConnected ? model.t("Receiver connected", "Penerima terhubung") : model.t("Waiting for iPhone Safari", "Menunggu Safari iPhone"))
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Button(model.t("Link", "Tautan")) { model.screen = .microphone; model.showSettings() }.buttonStyle(.bordered).font(.system(size: 10))
                    }
                }
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                    Text(model.virtualMic == nil ? model.t("The microphone driver is not ready. Open Settings → Guide.", "Driver mikrofon belum siap. Buka Pengaturan → Panduan.") : "Output: iHearYou Microphone")
                        .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Palette.secondary)
                if model.permissionDenied {
                    Button(model.t("Allow microphone access", "Izinkan akses mikrofon")) { model.openPrivacy() }.font(.system(size: 11))
                }
            }
        }.padding(20)
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.t("Recording", "Rekaman")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.recording ? model.elapsed : "WAV · 48 kHz")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 4) {
                ForEach(Array(model.cleanHistory.suffix(32).enumerated()), id: \.offset) { _, value in
                    Capsule().fill(model.active ? Palette.clean : Palette.secondary.opacity(0.35))
                        .frame(maxWidth: .infinity).frame(height: max(2, CGFloat(value) * 25))
                }
            }.frame(height: 25).accessibilityLabel(model.t("Clean audio level \(Int(model.outputDB)) dB", "Level suara bersih \(Int(model.outputDB)) dB"))
            HStack(spacing: 9) {
                Button { model.toggleRecording() } label: {
                    HStack {
                        Image(systemName: model.recording ? "stop.fill" : "record.circle")
                            .foregroundStyle(model.recording ? Color.red : Palette.ink)
                        Text(model.recording ? model.t("Save", "Simpan") : model.t("Record WAV", "Rekam WAV"))
                    }
                }.disabled(model.starting || (!model.active && !model.canStart))
                Button(model.t("Test browser", "Uji browser")) { model.openBrowserRecorder() }.disabled(model.starting)
                Button(model.t("Recordings", "Rekaman")) { model.refreshRecordings(); model.screen = .recordings; openSettings() }
                Spacer(minLength: 0)
            }.font(.system(size: 11)).buttonStyle(.bordered)
        }.padding(20)
    }

    private var footer: some View {
        HStack {
            Text(model.t("Created by i729", "Dibuat oleh i729")).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(model.t("\(model.appVersion) · No trial", "\(model.appVersion) · Tanpa trial")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 13).background(Palette.sidebar)
    }
    private var separator: some View { Rectangle().fill(Palette.line).frame(height: 1) }

    private func sectionHeading<Content: View>(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder badge: () -> Content) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.wrappedValue.toggle() } } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold))
                badge()
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90)).foregroundStyle(Palette.secondary)
            }
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(isExpanded.wrappedValue ? model.t("expanded", "terbuka") : model.t("collapsed", "tertutup"))")
    }
    private func message(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { if isError { model.error = nil } else { model.notice = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel(model.t("Dismiss message", "Tutup pesan"))
        }.padding(10).background(isError ? Palette.errorBackground : Palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 20).padding(.bottom, 12)
    }
    private func openMargVoice() {
        Task { @MainActor in
            if !model.active { await model.start() }
            guard model.active else { return }
            guard model.virtualMic != nil else {
                model.error = model.t("Install the iHearYou Microphone driver to use clean audio in MargVoice.", "Pasang driver iHearYou Microphone untuk memakai suara bersih di MargVoice."); return
            }
            NSWorkspace.shared.open(URL(string: "https://margvoice.com/projects/reading")!)
        }
    }
}
