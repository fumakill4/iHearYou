// iHearYou | Signature: i729
import AppKit
import SwiftUI
import Combine

@MainActor final class FloatingControl {
    private var panel: NSPanel?
    private var subscription: AnyCancellable?
    private var appearanceSubscription: AnyCancellable?
    init(model: AppModel) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 60, height: 164),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.title = "iHearYou — Floating"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: FloatingView().environmentObject(model))
        panel.setAccessibilityLabel("iHearYou floating control")
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
                .frame(width: 52, height: 14).overlay(DragHandle()).help("Geser panel dari area ini")
            Button { model.showMainWindow() } label: {
                Text("iH").font(.system(size: 19, weight: .bold)).frame(width: 38, height: 26)
            }.help("Buka iHearYou").accessibilityLabel("Buka iHearYou")
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(model.active ? Palette.clean : Color.gray)
                        .frame(width: 3, height: max(3, CGFloat(model.cleanHistory.suffix(5).dropFirst(index).first ?? 0) * 17))
                }
            }.frame(height: 18).accessibilityLabel("Level suara bersih \(Int(model.outputDB)) dB")
            Text(model.sessionElapsed).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                Button { model.toggle() } label: {
                    Image(systemName: model.active ? "mic.fill" : "mic.slash")
                        .foregroundStyle(model.active ? Palette.clean : Palette.ink)
                }.help(model.active ? "Hentikan mikrofon" : "Aktifkan mikrofon")
                    .accessibilityLabel(model.active ? "Hentikan mikrofon" : "Aktifkan mikrofon")
                    .disabled(!model.canStart && !model.active)
                Button { model.toggleRecording() } label: {
                    Image(systemName: model.recording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(model.recording ? Color.red : Palette.ink)
                }.disabled(!model.active).help(model.recording ? "Simpan rekaman" : "Rekam suara")
                    .accessibilityLabel(model.recording ? "Simpan rekaman" : "Rekam suara")
            }.font(.system(size: 12)).frame(height: 22)
        }.buttonStyle(.plain).padding(.vertical, 10).frame(width: 60, height: 164)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 25))
            .foregroundStyle(Palette.ink)
            .preferredColorScheme(model.appearance.colorScheme)
            .contextMenu {
                Toggle("Noise cancellation", isOn: $model.suppression)
                Button("Rekam lewat browser") { model.openBrowserRecorder() }
                Button("Sembunyikan panel") { model.showFloating = false }
            }
    }
}

private struct DragHandle: NSViewRepresentable {
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView {
        let view = Handle(); view.setAccessibilityLabel("Geser floating control"); return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
