// mPARLE — réglages.
import SwiftUI
import Translation
import ServiceManagement

struct SettingsView: View {
    @AppStorage("target") private var target = Prefs.target
    @AppStorage("alt") private var alt = Prefs.alt
    @AppStorage("fast") private var fast = "apple"
    @AppStorage("quality") private var quality = "deepl"
    @AppStorage("replace") private var replace = true
    @AppStorage("history") private var history = false
    @AppStorage("theme") private var theme = "system"
    @AppStorage("llmURL") private var llmURL = "http://localhost:11434"
    @AppStorage("llmModel") private var llmModel = ""
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var deeplKey = Keychain.get("deepl") ?? ""
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var trusted = Selection.trusted()
    @State private var packFrom = "en"
    @State private var packTo = Prefs.target
    @State private var packConfig: TranslationSession.Configuration?
    @State private var packStatus = ""
    @ObservedObject private var up = Updater.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack { BrandText(text: L.t("set.title"), font: .system(size: 17, weight: .bold)); Spacer() }.padding(.bottom, 4)
                row(L.t("set.target"), L.t("set.target.sub")) { langPicker($target) }
                row(L.t("set.alt"), L.t("set.alt.sub")) { langPicker($alt) }
                row(L.t("set.fast"), L.t("set.fast.sub")) { enginePicker($fast, [.apple, .google]) }
                row(L.t("set.quality"), L.t("set.quality.sub")) { enginePicker($quality, [.deepl, .google, .llm]) }
                if quality == "deepl" {
                    row(L.t("set.deeplkey"), L.t("set.deeplkey.sub")) {
                        SecureField("xxxxxxxx-…:fx", text: $deeplKey).textFieldStyle(.roundedBorder).frame(width: 200)
                            .onChange(of: deeplKey) { _, v in Keychain.set(v.trimmingCharacters(in: .whitespaces), for: "deepl") }
                    }
                }
                if quality == "llm" {
                    row(L.t("set.llm.url"), "") { TextField("", text: $llmURL).textFieldStyle(.roundedBorder).frame(width: 200) }
                    row(L.t("set.llm.model"), "") { TextField("", text: $llmModel).textFieldStyle(.roundedBorder).frame(width: 200) }
                }
                row(L.t("set.hk1"), L.t("set.hk1.sub")) { ShortcutRecorder(n: 1) }
                row(L.t("set.hk2"), "") { ShortcutRecorder(n: 2) }
                row(L.t("set.replace"), L.t("set.replace.sub")) { Toggle("", isOn: $replace).toggleStyle(.switch).tint(Theme.accent).labelsHidden() }
                row(L.t("set.history"), L.t("set.history.sub")) { Toggle("", isOn: $history).toggleStyle(.switch).tint(Theme.accent).labelsHidden() }
                row(L.t("set.login"), "") {
                    Toggle("", isOn: $login).toggleStyle(.switch).tint(Theme.accent).labelsHidden()
                        .onChange(of: login) { _, on in do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { login = !on } }
                }
                row(L.t("set.theme"), "") {
                    Picker("", selection: $theme) { Text(L.t("theme.system")).tag("system"); Text(L.t("theme.light")).tag("light"); Text(L.t("theme.dark")).tag("dark") }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                        .onChange(of: theme) { _, _ in applyTheme() }
                }
                row(L.t("set.ax"), L.t("set.ax.sub")) {
                    if trusted { Pill(text: L.t("set.ax.ok"), green: true) }
                    else { Button(L.t("set.ax.grant")) { _ = Selection.trusted(prompt: true); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { trusted = Selection.trusted() } }.buttonStyle(RoundButton(primary: true)) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("set.packs")).font(.system(size: 14, weight: .semibold))
                    Text(L.t("set.packs.sub")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    HStack { langPicker($packFrom); Image(systemName: "arrow.right"); langPicker($packTo)
                        Button(L.t("set.packs.dl")) { packStatus = ""; packConfig = .init(source: .init(identifier: packFrom), target: .init(identifier: packTo)) }.buttonStyle(RoundButton(primary: true))
                        Spacer(minLength: 0) }
                    if !packStatus.isEmpty { Text(packStatus).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .translationTask(packConfig) { session in
                    do { try await session.prepareTranslation(); packStatus = L.t("set.packs.ok") } catch { packStatus = L.t("set.packs.fail", error.localizedDescription) }
                }
                row(L.t("set.auto"), L.t("set.auto.sub")) {
                    HStack(spacing: 8) {
                        Text(updateText).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        if case .available = up.state { Button(L.t("upd.install")) { Task { await up.install() } }.buttonStyle(RoundButton(primary: true)) }
                        else { Button(L.t("set.check")) { Task { await up.check() } }.buttonStyle(RoundButton()) }
                        Toggle("", isOn: $autoUpdate).toggleStyle(.switch).tint(Theme.accent).labelsHidden()
                    }
                }
            }.padding(16)
        }
        .frame(minWidth: 560, minHeight: 600).background(Theme.bg).foregroundStyle(Theme.text)
        .onAppear { trusted = Selection.trusted(); HotKeys.shared.reload() }
    }

    private var updateText: String {
        switch up.state {
        case .idle: return ""
        case .checking: return L.t("upd.checking")
        case .upToDate: return L.t("upd.uptodate")
        case .available(let v): return L.t("upd.available", v)
        case .downloading: return L.t("upd.downloading")
        case .failed(let e): return e
        }
    }
    private func row<C: View>(_ title: String, _ sub: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
            Spacer(minLength: 12); c()
        }.padding(.horizontal, 14).padding(.vertical, 11).background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private func langPicker(_ b: Binding<String>) -> some View {
        Picker("", selection: b) { ForEach(Langs.all, id: \.self) { Text(Langs.name($0)).tag($0) } }.labelsHidden().frame(width: 150)
    }
    private func enginePicker(_ b: Binding<String>, _ list: [Engine]) -> some View {
        Picker("", selection: b) { ForEach(list) { Text($0.name).tag($0.rawValue) } }.labelsHidden().frame(width: 150)
    }
}

@MainActor func applyTheme() {
    switch Prefs.theme {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
}
