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
                        Label("Voice-over · MargVoice", systemImage: "globe")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(model.starting)
                        .help("Aktifkan mikrofon dan buka project voice-over MargVoice")
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
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("iHearYou").font(.system(size: 24, weight: .bold, design: .rounded))
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 17)) }
                .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
                .frame(width: 27, height: 30)
            Menu {
                Toggle("Floating control", isOn: $model.showFloating)
                Button("Panduan mikrofon browser") { model.screen = .guide; openSettings() }
                Divider()
                Button("Keluar iHearYou") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 24, height: 30)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Menu iHearYou")
        }.padding(.horizontal, 20).padding(.top, 17).padding(.bottom, 21)
    }

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Noise Cancellation", isExpanded: $noiseExpanded) {
                Text(model.suppression ? "● ON" : "OFF")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.suppression ? Palette.clean : Palette.secondary)
            }
            if noiseExpanded {
                Toggle("Cancel my noise", isOn: $model.suppression)
                    .font(.system(size: 13, weight: .medium)).toggleStyle(.switch)
                Picker("Peredaman", selection: $model.mode) {
                    ForEach(SuppressionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().disabled(!model.suppression)
                    .accessibilityLabel("Intensitas noise cancellation")
                Text(model.mode.explanation).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20)
    }

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("iHearYou Devices", isExpanded: $devicesExpanded) {
                Image(systemName: model.virtualMic == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(model.virtualMic == nil ? Color.orange : Palette.clean)
            }
            if devicesExpanded {
                Button { model.toggle() } label: {
                    HStack {
                        Image(systemName: model.active ? "mic.fill" : "mic.slash")
                        Text(model.starting ? "Memulai…" : model.active ? "Mikrofon aktif" : "Aktifkan mikrofon")
                        Spacer()
                        if model.active { Text(model.sessionElapsed).monospacedDigit() }
                    }.font(.system(size: 12, weight: .medium)).padding(.vertical, 4)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!model.canStart && !model.active)
                    .help(model.active ? "Hentikan mikrofon" : "Aktifkan mikrofon")
                VStack(alignment: .leading, spacing: 7) {
                    Text("Microphone").font(.system(size: 11, weight: .medium))
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill").frame(width: 20)
                        Picker("Microphone", selection: $model.inputUID) {
                            if model.microphones.isEmpty { Text("Mikrofon tidak ditemukan").tag("") }
                            ForEach(model.microphones) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().frame(maxWidth: .infinity)
                            .disabled(model.active || model.starting)
                    }.padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Speaker").font(.system(size: 11, weight: .medium))
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill").frame(width: 20)
                        Picker("Speaker untuk dengar langsung", selection: $model.monitorUID) {
                            if model.headphones.isEmpty { Text("Output tidak ditemukan").tag("") }
                            ForEach(model.headphones) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().frame(maxWidth: .infinity)
                            .disabled(model.active || model.starting)
                    }.padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line, lineWidth: 1))
                }
                Toggle("Dengar langsung", isOn: $model.monitoring)
                    .font(.system(size: 12)).toggleStyle(.switch).disabled(model.active || model.starting)
                Text("Gunakan headphone untuk mendengar suara sendiri. Input browser tetap iHearYou Microphone.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
                    Text(model.virtualMic == nil ? "Driver mikrofon belum siap. Buka Settings → Panduan." : "Output: iHearYou Microphone")
                        .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Palette.secondary)
                if model.permissionDenied {
                    Button("Izinkan akses mikrofon") { model.openPrivacy() }.font(.system(size: 11))
                }
            }
        }.padding(20)
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recording").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.recording ? model.elapsed : "WAV · 48 kHz")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 4) {
                ForEach(Array(model.cleanHistory.suffix(32).enumerated()), id: \.offset) { _, value in
                    Capsule().fill(model.active ? Palette.clean : Palette.secondary.opacity(0.35))
                        .frame(maxWidth: .infinity).frame(height: max(2, CGFloat(value) * 25))
                }
            }.frame(height: 25).accessibilityLabel("Level suara bersih \(Int(model.outputDB)) dB")
            HStack(spacing: 9) {
                Button { model.toggleRecording() } label: {
                    Label(model.recording ? "Simpan" : "Rekam WAV", systemImage: model.recording ? "stop.circle.fill" : "record.circle")
                }.disabled(!model.active)
                Button("Uji browser") { model.openBrowserRecorder() }.disabled(model.starting)
                Spacer(minLength: 0)
            }.font(.system(size: 11)).buttonStyle(.bordered)
        }.padding(20)
    }

    private var footer: some View {
        HStack {
            Text("Dibuat oleh i729").font(.system(size: 11, weight: .medium))
            Spacer()
            Text("1.1 · Tanpa trial").font(.system(size: 10)).foregroundStyle(Palette.secondary)
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
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(isExpanded.wrappedValue ? "terbuka" : "tertutup")")
    }
    private func message(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { if isError { model.error = nil } else { model.notice = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Tutup pesan")
        }.padding(10).background(isError ? Palette.errorBackground : Palette.surface, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 20).padding(.bottom, 12)
    }
    private func openMargVoice() {
        Task { @MainActor in
            if !model.active { await model.start() }
            guard model.active else { return }
            NSWorkspace.shared.open(URL(string: "https://margvoice.com/projects/reading")!)
        }
    }
}
