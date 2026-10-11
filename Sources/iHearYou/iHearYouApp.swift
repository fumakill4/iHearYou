// iHearYou | Signature: i729
// Copyright (c) 2026 i729. GPL-3.0-or-later.
import SwiftUI
import AppKit
import Combine

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var floatingControl: FloatingControl?
    private var statusControl: StatusControl?
    private var settingsWindow: NSWindow?
    private var appearanceSubscription: AnyCancellable?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusControl?.show(); return false
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        NSApp.setActivationPolicy(.accessory)
        statusControl = StatusControl(model: model)
        floatingControl = FloatingControl(model: model)
        model.onShowSettings = { [weak self] in self?.showSettings() }
        appearanceSubscription = model.$appearance.removeDuplicates().sink { [weak self] appearance in
            self?.settingsWindow?.appearance = appearance.appKitAppearance
        }
        // Developer smoke test is explicit, never enabled on normal launch.
        if CommandLine.arguments.contains("--audio-smoke-test") {
            Task { @MainActor in
                await model.start()
                if !model.active { print("SMOKE FAILED: \(model.error ?? "unknown")"); NSApp.terminate(nil); return }
                model.toggleRecording()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                model.stop()
                print("SMOKE: capture + DPDFNet2 + WAV completed. Files: \(RecordingStore.folder.path)")
                NSApp.terminate(nil)
            }
        } else {
            DispatchQueue.main.async { [weak self] in self?.statusControl?.show() }
        }
    }
    private func showSettings() {
        statusControl?.close()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "iHearYou — Settings"
            window.identifier = NSUserInterfaceItemIdentifier("main")
            window.minSize = NSSize(width: 830, height: 650)
            window.isReleasedWhenClosed = false
            window.appearance = AppModel.shared.appearance.appKitAppearance
            window.contentView = NSHostingView(rootView: ContentView().environmentObject(AppModel.shared))
            window.setFrameAutosaveName("iHearYouSettings")
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor private final class StatusControl: NSObject {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        super.init()
        if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityLabel("iHearYou controls")
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 646)
        popover.contentViewController = NSHostingController(rootView:
            CompactControlView(openSettings: { [weak model] in model?.showSettings() }).environmentObject(model))
        model.onShowControls = { [weak self] in self?.show() }
        model.$active.removeDuplicates().sink { [weak self] active in
            self?.item.button?.image = NSImage(systemSymbolName: active ? "waveform.circle.fill" : "waveform.circle",
                                               accessibilityDescription: "iHearYou")
            self?.item.button?.image?.isTemplate = true
            self?.item.button?.toolTip = active ? "iHearYou — Mikrofon aktif" : "iHearYou — Buka kontrol"
        }.store(in: &subscriptions)
        model.$appearance.removeDuplicates().sink { [weak self] appearance in
            self?.popover.appearance = appearance.appKitAppearance
            self?.popover.contentViewController?.view.appearance = appearance.appKitAppearance
        }.store(in: &subscriptions)
    }
    @objc private func toggle() { if popover.isShown { close() } else { show() } }
    func show() {
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
        popover.contentViewController?.view.window?.makeKey()
    }
    func close() { popover.performClose(nil) }
}

@main struct iHearYouApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        Settings {
            ContentView().environmentObject(model).preferredColorScheme(model.appearance.colorScheme)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings() }.keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {
                Button("Buka kontrol iHearYou") { model.showMainWindow() }
                Button(model.active ? "Hentikan mikrofon" : "Aktifkan mikrofon") { model.toggle() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button(model.recording ? "Simpan rekaman" : "Rekam suara") { model.toggleRecording() }
                    .keyboardShortcut("r", modifiers: [.command]).disabled(!model.active)
            }
        }
    }
}
