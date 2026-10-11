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
        installMenus()
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
    private func installMenus() {
        let menuBar = NSMenu()
        let appItem = NSMenuItem()
        menuBar.addItem(appItem)
        let appMenu = NSMenu(title: "iHearYou")
        appItem.submenu = appMenu
        func add(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self; item.keyEquivalentModifierMask = modifiers
            appMenu.addItem(item)
        }
        add("Buka kontrol iHearYou", #selector(openControls))
        add("Settings…", #selector(showSettings), key: ",")
        appMenu.addItem(.separator())
        add("Aktifkan / hentikan mikrofon", #selector(toggleMicrophone), key: "m", modifiers: [.command, .shift])
        add("Rekam / simpan suara", #selector(toggleRecording), key: "r")
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Keluar iHearYou", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; appMenu.addItem(quit)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu; menuBar.addItem(fileItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        editItem.submenu = editMenu; menuBar.addItem(editItem)
        NSApp.mainMenu = menuBar
    }
    @objc private func openControls() { AppModel.shared.showMainWindow() }
    @objc private func toggleMicrophone() { AppModel.shared.toggle() }
    @objc private func toggleRecording() { if AppModel.shared.active { AppModel.shared.toggleRecording() } }

    @objc private func showSettings() {
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
        // Open after the originating mouse event ends so a floating-panel click
        // is not interpreted as an outside click that immediately closes it.
        model.onShowControls = { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.show() }
        }
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

// AppKit owns the sole settings window; no automatic SwiftUI Settings scene is created.
@main enum iHearYouApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
