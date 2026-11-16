// mPARLE — bulle de traduction flottante près du curseur (panneau sans prise de focus).
import AppKit
import SwiftUI
import AVFoundation

@MainActor
final class BubbleModel: ObservableObject {
    enum State { case loading, done, error(String) }
    @Published var state: State = .loading
    @Published var original = ""
    @Published var result = ""
    @Published var source: String?
    @Published var target = Prefs.target
    @Published var engine: Engine = .apple
    @Published var ms = 0
    @Published var note: String?
    @Published var copied = false
    @Published var usedQuality = false
    var editable: Bool?
    var onClose: () -> Void = {}
    private var task: Task<Void, Never>?
    private let synth = AVSpeechSynthesizer()

    func start(_ text: String, editable: Bool?) {
        original = text; self.editable = editable
        source = Langs.detect(text)
        target = Langs.destination(for: source)
        translate(engine: Prefs.fast)
    }
    func translate(engine e: Engine) {
        task?.cancel(); state = .loading; copied = false; note = nil
        usedQuality = e == Prefs.quality && e != Prefs.fast
        let text = original, from = source, to = target
        task = Task {
            do {
                let r = try await Translator.run(text, from: from, to: to, engine: e)
                if Task.isCancelled { return }
                result = r.text; source = r.source ?? from; engine = r.engine; ms = r.ms; note = r.note; state = .done
                HistoryStore.shared.add(.init(src: text, dst: r.text, from: source, to: to, engine: r.engine.name))
            } catch { if !Task.isCancelled { state = .error(L.t("err.fail", error.localizedDescription)) } }
        }
    }
    func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(result, forType: .string); copied = true }
    func speak() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate); return }
        let u = AVSpeechUtterance(string: result)
        u.voice = AVSpeechSynthesisVoice(language: target == "zh-Hans" ? "zh-CN" : target == "zh-Hant" ? "zh-TW" : target)
        synth.speak(u)
    }
    func replace() { let t = result; onClose(); Task { try? await Task.sleep(nanoseconds: 120_000_000); await Selection.paste(t) } }
}

struct BubbleView: View {
    @ObservedObject var m: BubbleModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Pill(text: m.source.map { L.t("bubble.auto", Langs.name($0)) } ?? "Auto", green: true)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                Menu {
                    ForEach(Langs.all, id: \.self) { c in Button(Langs.name(c)) { m.target = c; m.translate(engine: m.engine) } }
                } label: { Pill(text: Langs.name(m.target)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                Spacer()
                if case .done = m.state { Text("\(m.engine.name) · \(String(format: "%.1f", Double(m.ms) / 1000)) s").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                Button { m.onClose() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help(L.t("bubble.close"))
            }
            switch m.state {
            case .loading: HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L.t("bubble.translating")).foregroundStyle(Theme.muted) }.font(.system(size: 13))
            case .error(let e): Text(e).font(.system(size: 13)).foregroundStyle(Theme.accentText)
            case .done:
                ScrollView { Text(m.result).font(.system(size: 15)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 220).fixedSize(horizontal: false, vertical: true)
                if let n = m.note { Text(n).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                HStack(spacing: 6) {
                    if Prefs.replace, m.editable != false { Button(L.t("bubble.replace")) { m.replace() }.buttonStyle(RoundButton(primary: true)) }
                    Button(m.copied ? L.t("bubble.copied") : L.t("bubble.copy")) { m.copy() }.buttonStyle(RoundButton(primary: !(Prefs.replace && m.editable != false)))
                    Button(L.t("bubble.speak")) { m.speak() }.buttonStyle(RoundButton())
                    if Prefs.quality != m.engine { Button(L.t("bubble.quality")) { m.translate(engine: Prefs.quality) }.buttonStyle(RoundButton()) }
                }
            }
        }
        .padding(14).frame(width: 360)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(Theme.text)
    }
}

/// Panneau flottant : ne prend pas le focus de l'appli en cours, se ferme au clic ailleurs ou sur Échap.
@MainActor
final class BubbleController {
    static let shared = BubbleController()
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private let model = BubbleModel()
    private var topLeft = NSPoint.zero

    func show(text: String, editable: Bool?) {
        close()
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.level = .popUpMenu; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true
        p.hidesOnDeactivate = false; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = NSHostingController(rootView: BubbleView(m: model))
        host.sizingOptions = [.preferredContentSize]
        p.contentViewController = host
        model.onClose = { [weak self] in self?.close() }
        panel = p
        model.start(text, editable: editable)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let vf = screen.visibleFrame
        topLeft = NSPoint(x: min(max(mouse.x - 24, vf.minX + 8), vf.maxX - 368), y: max(mouse.y - 18, vf.minY + 140))
        reposition()
        p.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.reposition() } }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in MainActor.assumeIsolated { self?.close() } } as Any,
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in if e.keyCode == 53 { MainActor.assumeIsolated { self?.close() } } } as Any,
        ]
    }
    private func reposition() {
        guard let p = panel else { return }
        let h = p.frame.height
        p.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - h))
    }
    func close() {
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors = []
        if let p = panel { NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: p); p.orderOut(nil) }
        panel = nil
    }
    func showMessage(_ msg: String) {
        show(text: "", editable: false)
        model.state = .error(msg)
    }
}
