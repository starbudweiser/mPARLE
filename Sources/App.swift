// mPARLE — traduction de n'importe quel texte sélectionné. Appli de barre de menus.
import AppKit
import SwiftUI

@main
struct MParleApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var windows: [String: NSWindow] = [:]

    func applicationDidFinishLaunching(_ n: Notification) {
        applyTheme()
        NSApp.servicesProvider = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            let img = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: Brand.name)
            img?.isTemplate = true; b.image = img
            b.target = self; b.action = #selector(openMenu); b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let h1 = Prefs.hotkey(1), h2 = Prefs.hotkey(2)
        HotKeys.shared.register(1, code: h1.code, mods: h1.mods) { [weak self] in self?.translateSelection() }
        HotKeys.shared.register(2, code: h2.code, mods: h2.mods) { [weak self] in self?.showQuick() }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in Task { @MainActor in Updater.shared.tick() } }
        Task { @MainActor in Updater.shared.tick() }
        if !Selection.trusted() { _ = Selection.trusted(prompt: true) }
        // Aide aux captures d'écran (variable d'environnement, sans effet en usage normal) : ouvre une fenêtre sans prendre le focus.
        if let shot = ProcessInfo.processInfo.environment["MPARLE_SHOT"] {
            switch shot {
            case "quick": showQuick()
            case "settings": showSettings()
            case "history": showHistory()
            case "bubble": BubbleController.shared.show(text: ProcessInfo.processInfo.environment["MPARLE_DEMO_TEXT"] ?? "", editable: false)
            default: break
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    // Menu sous l'icône (jamais statusItem.menu)
    @objc private func openMenu() {
        guard let b = item.button else { return }
        let m = NSMenu()
        func add(_ t: String, _ sel: Selector, key: String = "") { let i = NSMenuItem(title: t, action: sel, keyEquivalent: key); i.target = self; m.addItem(i) }
        let h1 = Prefs.hotkey(1), h2 = Prefs.hotkey(2)
        add(L.t("menu.translate") + "   " + shortcutLabel(code: h1.code, mods: h1.mods), #selector(translateSelection))
        add(L.t("menu.quick") + "   " + shortcutLabel(code: h2.code, mods: h2.mods), #selector(showQuick))
        add(L.t("menu.history"), #selector(showHistory))
        m.addItem(.separator())
        add(L.t("menu.settings"), #selector(showSettings), key: ",")
        add(L.t("menu.about"), #selector(showAbout))
        m.addItem(.separator())
        add(L.t("menu.quit"), #selector(quit), key: "q")
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: b.isFlipped ? b.bounds.maxY + 4 : -4), in: b)
    }

    @objc func translateSelection() {
        Task { @MainActor in
            guard Selection.trusted() else { BubbleController.shared.showMessage(L.t("bubble.needAX")); return }
            guard let g = await Selection.grab() else { BubbleController.shared.showMessage(L.t("bubble.nosel")); return }
            BubbleController.shared.show(text: g.text, editable: g.editable)
        }
    }
    /// Service macOS « Traduire avec mPARLE » (menu Services de toute appli).
    @objc func translateService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let t = pboard.string(forType: .string), !t.isEmpty else { return }
        DispatchQueue.main.async { BubbleController.shared.show(text: t, editable: false) }
    }
    @objc func showQuick() { show("quick", title: L.t("quick.title"), size: NSSize(width: 640, height: 330)) { AnyView(QuickView()) } }
    @objc func showHistory() { show("history", title: L.t("hist.title"), size: NSSize(width: 480, height: 520)) { AnyView(HistoryView()) } }
    @objc func showSettings() { show("settings", title: L.t("set.title"), size: NSSize(width: 560, height: 640)) { AnyView(SettingsView()) } }
    @objc func showAbout() { About.show() }
    @objc func quit() { NSApp.terminate(nil) }

    private func show(_ key: String, title: String, size: NSSize, _ view: () -> AnyView) {
        if windows[key] == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = title; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: view())
            w.center(); windows[key] = w
        }
        windows[key]?.present()
    }
}
