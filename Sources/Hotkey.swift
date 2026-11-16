// mPARLE — raccourcis globaux (Carbon, sans autorisation) et enregistreur de raccourci.
import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class HotKeys {
    static let shared = HotKeys()
    private var refs: [Int: EventHotKeyRef] = [:]
    private var actions: [Int: () -> Void] = [:]
    private var installed = false

    func register(_ id: Int, code: UInt32, mods: UInt32, action: @escaping () -> Void) {
        install()
        if let r = refs[id] { UnregisterEventHotKey(r) }
        actions[id] = action
        var ref: EventHotKeyRef?
        let hid = EventHotKeyID(signature: OSType(0x6D50524C), id: UInt32(id))
        if RegisterEventHotKey(code, mods, hid, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs[id] = ref }
    }
    private func install() {
        guard !installed else { return }; installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, ev, _ -> OSStatus in
            var hid = EventHotKeyID()
            GetEventParameter(ev, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hid)
            let id = Int(hid.id)
            DispatchQueue.main.async { HotKeys.shared.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
    func reload() {
        for n in 1...2 { let h = Prefs.hotkey(n); register(n, code: h.code, mods: h.mods, action: actions[n] ?? {}) }
    }
}

/// Bouton « enregistreur » : un clic, puis la combinaison voulue.
struct ShortcutRecorder: View {
    let n: Int
    @State private var recording = false
    @State private var label = ""
    @State private var monitor: Any?
    var body: some View {
        Button(recording ? L.t("rec.press") : label) { recording ? stop() : start() }
            .buttonStyle(RoundButton(primary: recording))
            .onAppear { refresh() }
            .onDisappear { stop() }
    }
    private func refresh() { let h = Prefs.hotkey(n); label = shortcutLabel(code: h.code, mods: h.mods) }
    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            var m: UInt32 = 0
            if e.modifierFlags.contains(.command) { m |= UInt32(cmdKey) }
            if e.modifierFlags.contains(.option) { m |= UInt32(optionKey) }
            if e.modifierFlags.contains(.control) { m |= UInt32(controlKey) }
            if e.modifierFlags.contains(.shift) { m |= UInt32(shiftKey) }
            guard m != 0 else { return nil }
            Prefs.setHotkey(n, code: UInt32(e.keyCode), mods: m)
            HotKeys.shared.reload(); refresh(); stop(); return nil
        }
    }
    private func stop() { recording = false; if let m = monitor { NSEvent.removeMonitor(m); monitor = nil } }
}
