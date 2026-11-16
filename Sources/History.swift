import Foundation
import SwiftUI
import AppKit

struct HistoryEntry: Codable, Identifiable { var id = UUID(); var date = Date(); var src: String; var dst: String; var from: String?; var to: String; var engine: String }

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var items: [HistoryEntry] = []
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "fr.stephan.mparle")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()
    init() { if let d = try? Data(contentsOf: url), let a = try? JSONDecoder().decode([HistoryEntry].self, from: d) { items = a } }
    func add(_ e: HistoryEntry) {
        guard Prefs.history else { return }
        items.insert(e, at: 0); if items.count > 300 { items.removeLast(items.count - 300) }; save()
    }
    func clear() { items = []; save() }
    private func save() { try? JSONEncoder().encode(items).write(to: url, options: .atomic) }
}

struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    var body: some View {
        VStack(spacing: 10) {
            HStack { BrandText(text: L.t("hist.title"), font: .system(size: 17, weight: .bold)); Spacer()
                Button(L.t("hist.clear")) { store.clear() }.buttonStyle(RoundButton()) }
            if store.items.isEmpty {
                VStack(spacing: 6) { Text(L.t("hist.empty")).font(.system(size: 15, weight: .semibold)); Text(L.t("hist.empty.sub")).foregroundStyle(Theme.muted).font(.system(size: 12)) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { LazyVStack(spacing: 8) { ForEach(store.items) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Pill(text: "\(e.from.map(Langs.name) ?? "?") → \(Langs.name(e.to))"); Text(e.engine).font(.system(size: 11)).foregroundStyle(Theme.muted); Spacer()
                            Button(L.t("bubble.copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(e.dst, forType: .string) }.buttonStyle(RoundButton()) }
                        Text(e.src).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                        Text(e.dst).font(.system(size: 14)).lineLimit(4)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                } } }
            }
        }.padding(16).background(Theme.bg).foregroundStyle(Theme.text)
    }
}
