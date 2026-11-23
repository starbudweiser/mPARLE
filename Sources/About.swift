import AppKit
import SwiftUI

/// Aplat de couleur dynamique (suit le thème clair/sombre de l'appli).
private final class FillView: NSView {
    let fill: NSColor
    init(_ fill: NSColor) { self.fill = fill; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = fill.cgColor } }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

@MainActor
enum About {
    private static var window: NSWindow?
    private static let sideMargin: CGFloat = 28, textWidth: CGFloat = 300

    static func show() {
        if window == nil { window = makeWindow() }
        window?.center(); window?.present()
    }
    private static func label(_ text: String, size: CGFloat = 12, bold: Bool = false, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        let p = NSMutableParagraphStyle(); p.alignment = .center
        field.attributedStringValue = BrandStyle.colored(NSAttributedString(string: text, attributes: [
            .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size), .paragraphStyle: p,
            .foregroundColor: secondary ? NSColor(Theme.muted) : NSColor(Theme.text)]))
        field.alignment = .center; field.preferredMaxLayoutWidth = textWidth; field.isSelectable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth).isActive = true
        return field
    }
    private static func makeWindow() -> NSWindow {
        let info = Bundle.main.infoDictionary ?? [:]
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown; icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 84).isActive = true
        let views: [NSView] = [icon, label(Brand.name, size: 17, bold: true),
            label(L.t("about.version", info["CFBundleShortVersionString"] as? String ?? "?", info["CFBundleVersion"] as? String ?? "?"), secondary: true),
            label(L.t("about.tagline")), label(L.t("about.authors"), bold: true), label(L.t("about.license")),
            label(L.t("about.disclaimer"), secondary: true), label(L.t("about.credit"), secondary: true),
            label(L.t("about.collection"), secondary: true)]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 12
        stack.setCustomSpacing(6, after: views[1]); stack.setCustomSpacing(18, after: views[2])
        stack.edgeInsets = NSEdgeInsets(top: 28, left: sideMargin, bottom: 28, right: sideMargin)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: textWidth + 2 * sideMargin).isActive = true
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = L.t("about.menu"); w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true; w.standardWindowButton(.zoomButton)?.isHidden = true
        w.backgroundColor = NSColor(Theme.bg)
        let content = FillView(NSColor(Theme.bg))
        // Barre de titre façon Socle : 30 px de fond « carte », filet dessous
        let bar = FillView(NSColor(Theme.card)); bar.translatesAutoresizingMaskIntoConstraints = false
        let rule = FillView(NSColor(Theme.line)); rule.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack); content.addSubview(bar); bar.addSubview(rule)
        NSLayoutConstraint.activate([bar.topAnchor.constraint(equalTo: content.topAnchor), bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 30),
            rule.leadingAnchor.constraint(equalTo: bar.leadingAnchor), rule.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bar.bottomAnchor), rule.heightAnchor.constraint(equalToConstant: 1),
            stack.topAnchor.constraint(equalTo: bar.bottomAnchor), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        w.contentView = content
        content.layoutSubtreeIfNeeded(); content.layoutSubtreeIfNeeded()
        w.setContentSize(content.fittingSize)
        return w
    }
}
