// mPARLE — lecture de la sélection (Accessibilité, repli ⌘C) et collage de la traduction.
import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Selection {
    struct Grab { var text: String; var editable: Bool? }

    static func trusted(prompt: Bool = false) -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary)
    }

    @MainActor static func grab() async -> Grab? {
        if let g = viaAccessibility() { return g }
        guard trusted() else { return nil }
        return await viaCopy()
    }

    private static func viaAccessibility() -> Grab? {
        guard trusted() else { return nil }
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let f = focused else { return nil }
        let el = f as! AXUIElement
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute as CFString, &sel) == .success,
              let s = sel as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable)
        return Grab(text: s, editable: settable.boolValue)
    }

    @MainActor private static func viaCopy() async -> Grab? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb); let count = pb.changeCount
        await waitForModifiersReleased()
        post(key: kVK_ANSI_C)
        var text: String?
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pb.changeCount != count { text = pb.string(forType: .string); break }
        }
        restore(saved, to: pb)
        guard let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Grab(text: t, editable: nil)
    }

    /// Colle `text` à la place de la sélection de l'appli active, puis restaure le presse-papiers.
    @MainActor static func paste(_ text: String) async {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        pb.clearContents(); pb.setString(text, forType: .string)
        await waitForModifiersReleased()
        post(key: kVK_ANSI_V)
        try? await Task.sleep(nanoseconds: 450_000_000)
        restore(saved, to: pb)
    }

    private static func snapshot(_ pb: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pb.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
    }
    private static func restore(_ s: [[(NSPasteboard.PasteboardType, Data)]], to pb: NSPasteboard) {
        pb.clearContents()
        let items = s.map { entries -> NSPasteboardItem in
            let i = NSPasteboardItem(); entries.forEach { i.setData($0.1, forType: $0.0) }; return i
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
    @MainActor private static func waitForModifiersReleased() async {
        for _ in 0..<20 {
            if NSEvent.modifierFlags.intersection([.option, .shift, .control, .command]).isEmpty { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }
    private static func post(key: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cgSessionEventTap)
        }
    }
}
