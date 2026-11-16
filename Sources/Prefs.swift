// mPARLE — réglages (UserDefaults) et Trousseau.
import Foundation
import Security
import Carbon.HIToolbox

enum Prefs {
    static let d = UserDefaults.standard
    static var systemLang: String {
        let id = Locale.preferredLanguages.first ?? "en"
        if id.hasPrefix("zh-Hant") || id.hasPrefix("zh-TW") || id.hasPrefix("zh-HK") { return "zh-Hant" }
        if id.hasPrefix("zh") { return "zh-Hans" }
        return String(id.prefix(2))
    }
    static var target: String { d.string(forKey: "target") ?? (Langs.all.contains(systemLang) ? systemLang : "en") }
    static var alt: String { d.string(forKey: "alt") ?? (target == "en" ? "fr" : "en") }
    static var fast: Engine { Engine(rawValue: d.string(forKey: "fast") ?? "apple") ?? .apple }
    static var quality: Engine { Engine(rawValue: d.string(forKey: "quality") ?? "deepl") ?? .deepl }
    static var replace: Bool { d.object(forKey: "replace") as? Bool ?? true }
    static var history: Bool { d.object(forKey: "history") as? Bool ?? false }
    static var theme: String { d.string(forKey: "theme") ?? "system" }
    static var llmURL: String { d.string(forKey: "llmURL") ?? "http://localhost:11434" }
    static var llmModel: String { d.string(forKey: "llmModel") ?? "" }
    static var autoUpdate: Bool { d.object(forKey: "autoUpdate") as? Bool ?? true }

    // Raccourcis : code de touche virtuelle + modificateurs Carbon. Défauts : ⌥T et ⌥⇧T.
    static func hotkey(_ n: Int) -> (code: UInt32, mods: UInt32) {
        let dc = n == 1 ? UInt32(kVK_ANSI_T) : UInt32(kVK_ANSI_T)
        let dm = n == 1 ? UInt32(optionKey) : UInt32(optionKey | shiftKey)
        let c = d.object(forKey: "hk\(n)Code") as? Int, m = d.object(forKey: "hk\(n)Mods") as? Int
        return (c.map(UInt32.init) ?? dc, m.map(UInt32.init) ?? dm)
    }
    static func setHotkey(_ n: Int, code: UInt32, mods: UInt32) { d.set(Int(code), forKey: "hk\(n)Code"); d.set(Int(mods), forKey: "hk\(n)Mods") }
}

enum Keychain {
    private static var service: String { Bundle.main.bundleIdentifier ?? "fr.stephan.mparle" }
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var q = base; q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

func shortcutLabel(code: UInt32, mods: UInt32) -> String {
    var s = ""
    if mods & UInt32(controlKey) != 0 { s += "⌃" }
    if mods & UInt32(optionKey) != 0 { s += "⌥" }
    if mods & UInt32(shiftKey) != 0 { s += "⇧" }
    if mods & UInt32(cmdKey) != 0 { s += "⌘" }
    let names: [UInt32: String] = [UInt32(kVK_Space): "Espace", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥"]
    if let n = names[code] { return s + n }
    // Lettre selon la disposition clavier courante
    if let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
       let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0; var len = 0; var chars = [UniChar](repeating: 0, count: 4)
        data.withUnsafeBytes { raw in
            let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        if len > 0 { return s + String(utf16CodeUnits: chars, count: len).uppercased() }
    }
    return s + "#\(code)"
}
