// mPARLE — fenêtre de saisie rapide.
import AppKit
import SwiftUI

@MainActor
final class QuickModel: ObservableObject {
    @Published var input = "" { didSet { schedule() } }
    @Published var output = ""
    @Published var source = "auto"      // "auto" ou code
    @Published var target = Prefs.target { didSet { schedule() } }
    @Published var info = ""
    private var task: Task<Void, Never>?
    func schedule() {
        task?.cancel()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { output = ""; info = ""; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let from = source == "auto" ? Langs.detect(text) : source
            let to = source == "auto" && from == target ? Prefs.alt : target
            do {
                let r = try await Translator.run(text, from: from, to: to, engine: Prefs.fast)
                if Task.isCancelled { return }
                output = r.text; info = r.engine.name
                HistoryStore.shared.add(.init(src: text, dst: r.text, from: r.source, to: to, engine: r.engine.name))
            } catch { if !Task.isCancelled { output = L.t("err.fail", error.localizedDescription); info = "" } }
        }
    }
    func swap() { if source != "auto" { let s = source; source = target; target = s }; input = output; }
}

struct QuickView: View {
    @StateObject var m = QuickModel()
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Picker("", selection: $m.source) { Text(L.t("quick.detect")).tag("auto"); Divider(); ForEach(Langs.all, id: \.self) { Text(Langs.name($0)).tag($0) } }
                    .labelsHidden().frame(maxWidth: .infinity)
                Button { m.swap() } label: { Image(systemName: "arrow.left.arrow.right") }.buttonStyle(RoundButton()).help(L.t("quick.swap"))
                Picker("", selection: $m.target) { ForEach(Langs.all, id: \.self) { Text(Langs.name($0)).tag($0) } }
                    .labelsHidden().frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                box(title: L.t("quick.source")) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $m.input).scrollContentBackground(.hidden).font(.system(size: 15))
                        if m.input.isEmpty { Text(L.t("quick.placeholder")).foregroundStyle(Theme.muted).font(.system(size: 15)).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                    }
                }
                box(title: L.t("quick.result", m.info)) {
                    VStack(alignment: .leading) {
                        ScrollView { Text(m.output).font(.system(size: 15)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        if !m.output.isEmpty { Button(L.t("bubble.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.output, forType: .string) }.buttonStyle(RoundButton()) }
                    }
                }
            }
        }.padding(16).frame(minWidth: 620, minHeight: 300).background(Theme.bg).foregroundStyle(Theme.text)
    }
    private func box<C: View>(title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 11)).foregroundStyle(Theme.muted); c() }
            .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
