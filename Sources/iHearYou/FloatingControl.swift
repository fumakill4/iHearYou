// iHearYou | Signature: i729
import AppKit
import SwiftUI
import Combine

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private final class FloatingHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class FloatingControl {
    private var panel: NSPanel?
    private var subscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?
    init(model: AppModel) {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 60, height: 164),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = L("iHearYou — Floating control", "iHearYou — Kontrol mengambang")
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = FloatingHostingView(rootView: FloatingView().environmentObject(model))
        panel.setAccessibilityLabel(L("iHearYou floating control", "Kontrol mengambang iHearYou"))
        let defaults = UserDefaults.standard
        let saved = NSPoint(x: defaults.double(forKey: "floatingX"), y: defaults.double(forKey: "floatingY"))
        let screen = NSScreen.screens.first { $0.visibleFrame.contains(saved) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let point = defaults.object(forKey: "floatingX") == nil
                ? NSPoint(x: frame.maxX - 84, y: frame.midY - 82) : saved
            panel.setFrameOrigin(NSPoint(x: max(frame.minX, min(point.x, frame.maxX - 60)),
                                         y: max(frame.minY, min(point.y, frame.maxY - 164))))
        }
        self.panel = panel
        NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: panel)
        subscription = model.$showFloating.removeDuplicates().sink { [weak self] visible in
            if visible { self?.panel?.orderFrontRegardless() } else { self?.panel?.orderOut(nil) }
        }
        appearanceSubscription = model.$appearance.removeDuplicates().sink { [weak self] appearance in
            self?.panel?.appearance = appearance.appKitAppearance
            self?.panel?.contentView?.appearance = appearance.appKitAppearance
        }
        languageSubscription = model.$language.removeDuplicates().sink { [weak self] _ in
            // Published emits before the model stores the new language.
            DispatchQueue.main.async { [weak self] in
                self?.panel?.title = L("iHearYou — Floating control", "iHearYou — Kontrol mengambang")
                self?.panel?.setAccessibilityLabel(L("iHearYou floating control", "Kontrol mengambang iHearYou"))
            }
        }
    }
    @objc private func moved() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set(origin.x, forKey: "floatingX")
        UserDefaults.standard.set(origin.y, forKey: "floatingY")
    }
}

private struct FloatingView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(.gray)
                .frame(width: 52, height: 14).overlay(DragHandle(label: model.t("Drag floating control", "Geser kontrol mengambang"))).help(model.t("Drag the panel from this area", "Geser panel dari area ini"))
            Button { model.showMainWindow() } label: {
                Text("iH").font(.system(size: 19, weight: .bold)).frame(width: 38, height: 26)
            }.help(model.t("Open iHearYou", "Buka iHearYou")).accessibilityLabel(model.t("Open iHearYou", "Buka iHearYou"))
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(model.active ? Palette.clean : Color.gray)
                        .frame(width: 3, height: max(3, CGFloat(model.cleanHistory.suffix(5).dropFirst(index).first ?? 0) * 17))
                }
            }.frame(height: 18).accessibilityLabel(model.t("Clean audio level \(Int(model.outputDB)) dB", "Level suara bersih \(Int(model.outputDB)) dB"))
            Text(model.sessionElapsed).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                Button { model.toggle() } label: {
                    Image(systemName: model.active ? "mic.fill" : "mic.slash")
                        .foregroundStyle(model.active ? Palette.clean : Palette.ink)
                }.help(model.active ? model.t("Stop microphone", "Hentikan mikrofon") : model.t("Start microphone", "Aktifkan mikrofon"))
                    .accessibilityLabel(model.active ? model.t("Stop microphone", "Hentikan mikrofon") : model.t("Start microphone", "Aktifkan mikrofon"))
                    .disabled(!model.canStart && !model.active)
                Button { model.toggleRecording() } label: {
                    Image(systemName: model.recording ? "stop.fill" : "record.circle")
                        .foregroundStyle(model.recording ? Color.red : Palette.ink)
                }.disabled(model.starting || (!model.active && !model.canStart)).help(model.recording ? model.t("Save recording", "Simpan rekaman") : model.t("Record audio", "Rekam suara"))
                    .accessibilityLabel(model.recording ? model.t("Save recording", "Simpan rekaman") : model.t("Record audio", "Rekam suara"))
            }.font(.system(size: 12)).frame(height: 22)
        }.buttonStyle(.plain).padding(.vertical, 10).frame(width: 60, height: 164)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))
            .foregroundStyle(Palette.ink)
            .preferredColorScheme(model.appearance.colorScheme)
            .environment(\.locale, model.language.locale)
            .contextMenu {
                Toggle(model.t("Noise cancellation", "Peredaman bising"), isOn: $model.suppression)
                Button(model.t("Record in browser", "Rekam lewat browser")) { model.openBrowserRecorder() }
                Button(model.t("Hide panel", "Sembunyikan panel")) { model.showFloating = false }
            }
    }
}

private struct DragHandle: NSViewRepresentable {
    let label: String
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView {
        let view = Handle(); view.setAccessibilityLabel(label); return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.setAccessibilityLabel(label) }
}
