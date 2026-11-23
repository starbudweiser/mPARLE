// mPARLE — nom de l'appli (lettre minuscule colorée), présentation de fenêtre, thème.
import AppKit
import SwiftUI

enum Brand {
    static let name = "mPARLE"
    static let accentHex: UInt32 = 0xFF6B4A

    static func lowercaseRanges(in text: String) -> [NSRange] {
        let marks = name.utf16.enumerated().filter { CharacterSet.lowercaseLetters.contains(Unicode.Scalar($0.element)!) }.map(\.offset)
        let ns = text as NSString
        var ranges: [NSRange] = []
        var from = 0
        while from < ns.length {
            let found = ns.range(of: name, options: [.literal], range: NSRange(location: from, length: ns.length - from))
            if found.location == NSNotFound { break }
            from = found.location + found.length
            if found.location > 0, isWordPart(ns.character(at: found.location - 1), extra: "./@-_") { continue }
            if from < ns.length, isWordPart(ns.character(at: from), extra: "-_") { continue }
            ranges += marks.map { NSRange(location: found.location + $0, length: 1) }
        }
        return ranges
    }
    private static func isWordPart(_ unit: unichar, extra: String) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || extra.unicodeScalars.contains(scalar)
    }
}

enum BrandStyle {
    static let color = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0x7E / 255, blue: 0x62 / 255, alpha: 1)
            : NSColor(srgbRed: 0xE0 / 255, green: 0x4A / 255, blue: 0x28 / 255, alpha: 1)
    }
    static func colored(_ base: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: base)
        for r in Brand.lowercaseRanges(in: base.string) { out.addAttribute(.foregroundColor, value: color, range: r) }
        return out
    }
}

extension NSWindow {
    @MainActor func present() {
        if ProcessInfo.processInfo.environment["MPARLE_SHOT"] != nil { orderFrontRegardless(); return }   // captures : sans prendre le focus
        NSApp.activate()
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isKeyWindow else { return }
            NSApp.activate(); self.makeKeyAndOrderFront(nil)
        }
    }
}

/// Texte SwiftUI dont la lettre minuscule du nom est colorée.
struct BrandText: View {
    let text: String
    var font: Font = .system(size: 15, weight: .bold)
    var body: some View {
        var a = AttributedString(text)
        for r in Brand.lowercaseRanges(in: text) {
            if let rr = Range(r, in: text), let lo = AttributedString.Index(rr.lowerBound, within: a), let hi = AttributedString.Index(rr.upperBound, within: a) {
                a[lo..<hi].foregroundColor = Color(nsColor: BrandStyle.color)
            }
        }
        return Text(a).font(font)
    }
}

// MARK: Thème : couleurs Socle (neutres clair / sombre), accent corail de l'appli
extension Color {
    init(light: UInt32, dark: UInt32) {
        func ns(_ h: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1) }
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light) })
    }
}
enum Theme {
    static let bg = Color(light: 0xF2F2F2, dark: 0x131316)
    static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let chip = Color(light: 0xE6E6E6, dark: 0x2C2C31)
    static let text = Color(light: 0x222222, dark: 0xF5F5F7)
    static let muted = Color(light: 0x555555, dark: 0x98989F)
    static let accent = Color(light: 0xFF6B4A, dark: 0xFF6B4A)
    static let accentSoft = Color(light: 0xFFE2DA, dark: 0x3A2420)
    static let accentText = Color(light: 0xC4381B, dark: 0xFF9A82)
    static let greenSoft = Color(light: 0xE2F6EE, dark: 0x1D3A2F)
    static let greenText = Color(light: 0x1D8A64, dark: 0x5FD6A6)
    static let line = Color(light: 0xD4D4D4, dark: 0x303035)
}

struct Pill: View {
    let text: String; var green = false
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 3)
            .background(green ? Theme.greenSoft : Theme.accentSoft, in: Capsule())
            .foregroundStyle(green ? Theme.greenText : Theme.accentText)
    }
}
struct RoundButton: ButtonStyle {
    var primary = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 12, weight: primary ? .semibold : .regular)).lineLimit(1).fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(primary ? Theme.accent : Theme.chip, in: Capsule())
            .foregroundStyle(primary ? Color.white : Theme.text)
            .opacity(c.isPressed ? 0.7 : 1)
    }
}
