import Foundation

struct FetchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Lit le prix d'un produit sur la page web (idealo ou autre).
enum PriceFetcher {

    static func fetch(urlString: String) async throws -> (price: Double, title: String?) {
        guard let url = cleanURL(urlString) else {
            throw FetchError(message: "Lien invalide.")
        }

        // 1) Lecture directe de la page (rapide)
        var firstError: FetchError?
        do {
            let page = try await download(url)
            let found = extract(from: page)
            if let price = found.price { return (price, found.title) }
            firstError = FetchError(message: describeFailure(page))
        } catch let error as FetchError {
            firstError = error
        } catch {
            firstError = FetchError(message: "Connexion impossible. Vérifie ton réseau.")
        }

        // 2) Comme un vrai navigateur (le Safari intégré à l'iPhone) : passe souvent là où la lecture directe est bloquée
        do {
            let page = try await WebPageLoader.html(for: url) { extract(from: $0).price != nil }
            let found = extract(from: page)
            if let price = found.price { return (price, found.title) }
            if page.isEmpty { throw firstError ?? FetchError(message: "La page n'a pas pu être chargée.") }
            throw FetchError(message: describeFailure(page))
        } catch let error as FetchError {
            throw error
        } catch {
            throw firstError ?? FetchError(message: "Lecture de la page impossible.")
        }
    }

    // MARK: - Lien

    /// Retrouve l'adresse dans un texte collé (« Regarde ça : https://… »), enlève les caractères invisibles.
    static func cleanURL(_ raw: String) -> URL? {
        var text = raw
        for invisible in ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"] {
            text = text.replacingOccurrences(of: invisible, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = matches(#"https?://[^\s<>"']+"#, in: text).first {
            text = m[0]
        }
        guard text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") else { return nil }
        if let url = URL(string: text) { return url }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "!*'();:@&=+$,/?#[]%-._~"))
        if let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) {
            return URL(string: encoded)
        }
        return nil
    }

    // MARK: - Téléchargement direct

    private static func download(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue("fr-FR,fr;q=0.9,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError(message: "Connexion impossible. Vérifie ton réseau.")
        }
        let (data, response) = result

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 403 || http.statusCode == 429 {
                throw FetchError(message: "Le site a refusé la lecture automatique (erreur \(http.statusCode)). Utilise « Prix manuel ».")
            }
            throw FetchError(message: "Erreur \(http.statusCode) en ouvrant la page.")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Message d'erreur qui dit ce que la page contenait (utile pour comprendre).
    static func describeFailure(_ page: String) -> String {
        let lower = page.lowercased()
        if page.count < 60_000,
           lower.contains("captcha") || lower.contains("datadome") || lower.contains("access denied")
            || lower.contains("are you a robot") || lower.contains("unusual traffic") {
            return "Le site a affiché une page de vérification anti-robot. Réessaie plus tard ou utilise « Prix manuel »."
        }
        var details = "\(page.count / 1000) Ko"
        if let title = extract(from: page).title, !title.isEmpty {
            details = "« \(String(title.prefix(50))) », " + details
        }
        return "Prix introuvable sur cette page (page reçue : \(details)). Utilise « Prix manuel »."
    }

    // MARK: - Extraction

    private static let number = #"([0-9]+(?:[ \x{00A0}\x{202F}.,][0-9]+)*)"#

    static func extract(from page: String) -> (price: Double?, title: String?) {
        var title: String?
        if let m = matches(#"<meta[^>]+property="og:title"[^>]+content="([^"]+)""#, in: page).first {
            title = unescape(m[1])
        } else if let m = matches(#"<title[^>]*>(.*?)</title>"#, in: page).first {
            title = unescape(m[1])
        }

        // 1) Données structurées JSON-LD (le plus fiable)
        let blocks = matches(#"<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: page)
        for block in blocks {
            guard let data = block[1].data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let price = prices(in: json).first(where: { $0 > 0 }) {
                return (price, title)
            }
        }

        // 1 bis) JSON-LD que Swift ne sait pas décoder : on cherche quand même le prix dedans
        for block in blocks {
            if let price = firstPrice(#""(?:lowPrice|price)"\s*:\s*"?"# + number, in: block[1]) {
                return (price, title)
            }
        }

        // 2) Balises meta (dans les deux ordres d'attributs)
        let names = #"(?:product:price:amount|og:price:amount|price|lowPrice)"#
        let metaA = #"<meta[^>]+(?:property|itemprop|name)=["']"# + names + #"["'][^>]*?content=["']([^"']+)["']"#
        let metaB = #"<meta[^>]+content=["']([^"']+)["'][^>]*?(?:property|itemprop|name)=["']"# + names + #"["']"#
        for pattern in [metaA, metaB] {
            if let price = firstPrice(pattern, in: page) { return (price, title) }
        }

        // 3) Prix « le plus bas » présent n'importe où dans la page (état JSON de la page, etc.)
        if let price = firstPrice(#""(?:lowPrice|lowestPrice|minPrice)"\s*:\s*"?"# + number, in: page) {
            return (price, title)
        }

        // 4) Texte « à partir de 299,00 € », « dès 299 € », « ab 299 € »
        let text = #"\b(?:à partir de|dès|ab)\b\s*(?:<[^>]+>\s*)*"# + number + #"\s*(?:<[^>]+>\s*)*€"#
        if let price = firstPrice(text, in: page) {
            return (price, title)
        }

        return (nil, title)
    }

    private static func firstPrice(_ pattern: String, in text: String) -> Double? {
        for m in matches(pattern, in: text) {
            if let value = parseNumber(m[1]), value > 0 { return value }
        }
        return nil
    }

    private static func prices(in node: Any) -> [Double] {
        var out: [Double] = []
        if let dict = node as? [String: Any] {
            for key in ["lowPrice", "price"] {
                guard let value = dict[key] else { continue }
                if let n = value as? NSNumber {
                    out.append(n.doubleValue)
                } else if let s = value as? String, let n = parseNumber(s) {
                    out.append(n)
                }
            }
            for value in dict.values { out += prices(in: value) }
        } else if let array = node as? [Any] {
            for value in array { out += prices(in: value) }
        }
        return out
    }

    /// Convertit "1 299,99", "1299.99" ou "1.299,99" en Double.
    static func parseNumber(_ raw: String) -> Double? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in ["\u{202F}", "\u{00A0}", " ", "€", "EUR"] {
            t = t.replacingOccurrences(of: junk, with: "")
        }
        if t.contains(",") && t.contains(".") {
            if let comma = t.lastIndex(of: ","), let dot = t.lastIndex(of: "."), comma > dot {
                t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                t = t.replacingOccurrences(of: ",", with: "")
            }
        } else if t.contains(",") {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        return Double(t)
    }

    // MARK: - Utilitaires

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        let found = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return found.map { m in
            (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
