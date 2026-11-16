// mPARLE — moteurs de traduction : Apple (local), Google, DeepL, modèle local (API compatible OpenAI).
import Foundation
import NaturalLanguage
import Translation

enum Engine: String, CaseIterable, Identifiable {
    case apple, google, deepl, llm
    var id: String { rawValue }
    var name: String { L.t("eng.\(rawValue)") }
}

enum Langs {
    /// Langues prises en charge par Apple Translation (les moteurs en ligne en gèrent au moins autant).
    static let all = ["ar", "zh-Hans", "zh-Hant", "nl", "en", "fr", "de", "hi", "id", "it", "ja", "ko", "pl", "pt", "ru", "es", "th", "tr", "uk", "vi"]
    static func name(_ code: String) -> String {
        let n = Locale(identifier: L.lang).localizedString(forIdentifier: code) ?? code
        return n.prefix(1).uppercased() + n.dropFirst()
    }
    static func detect(_ text: String) -> String? {
        let r = NLLanguageRecognizer(); r.processString(String(text.prefix(1000)))
        guard let l = r.dominantLanguage?.rawValue else { return nil }
        if all.contains(l) { return l }
        if l == "zh" { return "zh-Hans" }
        return String(l.prefix(2)).isEmpty ? nil : (all.contains(String(l.prefix(2))) ? String(l.prefix(2)) : nil)
    }
    /// Langue de destination : la cible, ou l'alternative quand le texte est déjà dans la cible.
    static func destination(for source: String?) -> String {
        if let s = source, s == Prefs.target { return Prefs.alt }
        return Prefs.target
    }
}

struct TranslationOutput {
    var text: String; var source: String?; var engine: Engine; var ms: Int; var note: String?
}

enum EngineError: LocalizedError {
    case notInstalled, noKey, badResponse, noLLM, http(Int)
    var errorDescription: String? {
        switch self {
        case .notInstalled: return L.t("err.notInstalled")
        case .noKey: return L.t("err.noKey")
        case .badResponse: return L.t("err.badResponse")
        case .noLLM: return L.t("err.noLLM")
        case .http(let c): return "HTTP \(c)"
        }
    }
}

enum Translator {
    /// Traduit avec le moteur demandé ; en cas d'échec d'Apple (langue absente) ou de clé DeepL manquante, repli sur Google.
    static func run(_ text: String, from: String?, to: String, engine: Engine) async throws -> TranslationOutput {
        let t0 = Date()
        func ms() -> Int { Int(Date().timeIntervalSince(t0) * 1000) }
        var note: String?
        var eng = engine
        if eng == .apple, from == nil || from == to { eng = .google }
        for _ in 0..<2 {
            do {
                switch eng {
                case .apple:
                    let r = try await apple(text, from: from!, to: to)
                    return .init(text: r, source: from, engine: .apple, ms: ms(), note: note)
                case .google:
                    let (r, s) = try await google(text, from: from, to: to)
                    return .init(text: r, source: from ?? s, engine: .google, ms: ms(), note: note)
                case .deepl:
                    let (r, s) = try await deepl(text, from: from, to: to)
                    return .init(text: r, source: from ?? s, engine: .deepl, ms: ms(), note: note)
                case .llm:
                    let r = try await llm(text, from: from, to: to)
                    return .init(text: r, source: from, engine: .llm, ms: ms(), note: note)
                }
            } catch EngineError.noKey where eng == .deepl { note = L.t("err.noKey"); eng = .google }
            catch EngineError.notInstalled where eng == .apple { eng = .google }
        }
        throw EngineError.badResponse
    }

    // MARK: Apple
    private static var sessions: [String: TranslationSession] = [:]
    static func apple(_ text: String, from: String, to: String) async throws -> String {
        let src = Locale.Language(identifier: from), tgt = Locale.Language(identifier: to)
        guard await LanguageAvailability().status(from: src, to: tgt) == .installed else { throw EngineError.notInstalled }
        let key = "\(from)>\(to)"
        let session: TranslationSession
        if let s = sessions[key] { session = s } else { session = TranslationSession(installedSource: src, target: tgt); sessions[key] = session }
        return try await session.translate(text).targetText
    }

    // MARK: Google (point d'accès public sans clé)
    static func google(_ text: String, from: String?, to: String) async throws -> (String, String?) {
        func g(_ c: String) -> String { c == "zh-Hans" ? "zh-CN" : c == "zh-Hant" ? "zh-TW" : c }
        var req = URLRequest(url: URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&sl=\(from.map(g) ?? "auto")&tl=\(g(to))")!)
        req.httpMethod = "POST"; req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "&+=?#")
        req.httpBody = "q=\(text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")".data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let c = (resp as? HTTPURLResponse)?.statusCode, c != 200 { throw EngineError.http(c) }
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [Any], let parts = arr.first as? [[Any]] else { throw EngineError.badResponse }
        let out = parts.compactMap { $0.first as? String }.joined()
        let det = arr.count > 2 ? arr[2] as? String : nil
        return (out, det)
    }

    // MARK: DeepL
    static func deepl(_ text: String, from: String?, to: String) async throws -> (String, String?) {
        guard let key = Keychain.get("deepl"), !key.isEmpty else { throw EngineError.noKey }
        func tgt(_ c: String) -> String { switch c { case "en": return "EN-US"; case "pt": return "PT-PT"; case "zh-Hans": return "ZH-HANS"; case "zh-Hant": return "ZH-HANT"; default: return c.uppercased() } }
        func src(_ c: String) -> String { c.hasPrefix("zh") ? "ZH" : c.uppercased() }
        let host = key.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        var req = URLRequest(url: URL(string: "https://\(host)/v2/translate")!)
        req.httpMethod = "POST"; req.timeoutInterval = 15
        req.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": [text], "target_lang": tgt(to)]
        if let f = from { body["source_lang"] = src(f) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let c = (resp as? HTTPURLResponse)?.statusCode, c != 200 { throw EngineError.http(c) }
        guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = (j["translations"] as? [[String: Any]])?.first,
              let s = t["text"] as? String else { throw EngineError.badResponse }
        return (s, (t["detected_source_language"] as? String)?.lowercased())
    }

    // MARK: Modèle local (Ollama, LM Studio… : /v1/chat/completions)
    static func llm(_ text: String, from: String?, to: String) async throws -> String {
        guard !Prefs.llmModel.isEmpty, let url = URL(string: Prefs.llmURL + "/v1/chat/completions") else { throw EngineError.noLLM }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let sys = "You are a translation engine. Translate the user's text\(from.map { " from \(Langs.name($0))" } ?? "") into \(Langs.name(to)). Output only the translation, keeping the formatting."
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": Prefs.llmModel, "temperature": 0,
            "messages": [["role": "system", "content": sys], ["role": "user", "content": text]]] as [String: Any])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let m = ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String else { throw EngineError.badResponse }
            return m.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let e as EngineError { throw e } catch { throw EngineError.noLLM }
    }
}
