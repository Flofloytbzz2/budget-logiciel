import Foundation

struct FetchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Résultat de la lecture d'une page (prix éventuel, titre, devise éventuelle).
struct PriceResult {
    var price: Double?
    var title: String?
    var currency: String?
    var explicit: Bool      // devise lue clairement (code ou symbole sans ambiguïté), pas devinée avec « $ »
}

struct FetchedPrice {
    var price: Double
    var title: String?
    var currency: String?
    var explicit: Bool
}

/// Lit le prix d'un produit sur la page web de n'importe quelle boutique (idealo, Amazon, Best Buy…).
enum PriceFetcher {

    static func fetch(urlString: String) async throws -> FetchedPrice {
        guard let url = cleanURL(urlString) else {
            throw FetchError(message: L.t("fetch.invalid_link"))
        }

        // 1) Lecture directe de la page (rapide)
        var firstError: FetchError?
        do {
            let page = try await download(url)
            let found = extract(from: page)
            if let price = found.price {
                return FetchedPrice(price: price, title: found.title, currency: found.currency, explicit: found.explicit)
            }
            firstError = FetchError(message: describeFailure(page))
        } catch let error as FetchError {
            firstError = error
        } catch {
            firstError = FetchError(message: L.t("err.network"))
        }

        // 2) Comme un vrai navigateur (le Safari intégré à l'iPhone) : passe souvent là où la lecture directe est bloquée
        do {
            let page = try await WebPageLoader.html(for: url) { extract(from: $0).price != nil }
            let found = extract(from: page)
            if let price = found.price {
                return FetchedPrice(price: price, title: found.title, currency: found.currency, explicit: found.explicit)
            }
            if page.isEmpty { throw firstError ?? FetchError(message: L.t("fetch.page_failed")) }
            throw FetchError(message: describeFailure(page))
        } catch let error as FetchError {
            throw error
        } catch {
            throw firstError ?? FetchError(message: L.t("fetch.read_failed"))
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

    private static func acceptLanguage() -> String {
        switch L.code {
        case "fr": return "fr-FR,fr;q=0.9,en;q=0.5"
        case "es": return "es-ES,es;q=0.9,en;q=0.5"
        case "de": return "de-DE,de;q=0.9,en;q=0.5"
        default: return "en-US,en;q=0.9"
        }
    }

    private static func download(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage(), forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError(message: L.t("err.network"))
        }
        let (data, response) = result

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 403 || http.statusCode == 429 {
                throw FetchError(message: L.f("fetch.refused", String(http.statusCode)))
            }
            throw FetchError(message: L.f("fetch.http", String(http.statusCode)))
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Message d'erreur qui dit ce que la page contenait (utile pour comprendre).
    static func describeFailure(_ page: String) -> String {
        let lower = page.lowercased()
        if page.count < 60_000,
           lower.contains("captcha") || lower.contains("datadome") || lower.contains("access denied")
            || lower.contains("are you a robot") || lower.contains("unusual traffic") {
            return L.t("fetch.robot")
        }
        var details = String(page.count / 1000) + " KB"
        if let title = extract(from: page).title, !title.isEmpty {
            details = "« " + String(title.prefix(50)) + " », " + details
        }
        return L.f("fetch.notfound", details)
    }

    // MARK: - Extraction

    private static let number = #"([0-9]+(?:[ \x{00A0}\x{202F}.,][0-9]+)*)"#
    private static let currencyMarks = #"(?:€|\$|£|EUR|USD|GBP|CHF)"#

    static func extract(from page: String) -> PriceResult {
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
            let offers = offersIn(json)
            if let first = offers.first(where: { $0.price > 0 }) {
                return finish(first.price, title, first.currency, snippet: nil, page: page)
            }
        }

        // 1 bis) JSON-LD que Swift ne sait pas décoder : on cherche quand même le prix dedans
        for block in blocks {
            if let price = firstPrice(#""(?:lowPrice|price)"\s*:\s*"?"# + number, in: block[1]) {
                return finish(price, title, nil, snippet: nil, page: page)
            }
        }

        // 2) Balises meta (dans les deux ordres d'attributs)
        let names = #"(?:product:price:amount|og:price:amount|price|lowPrice)"#
        let metaA = #"<meta[^>]+(?:property|itemprop|name)=["']"# + names + #"["'][^>]*?content=["']([^"']+)["']"#
        let metaB = #"<meta[^>]+content=["']([^"']+)["'][^>]*?(?:property|itemprop|name)=["']"# + names + #"["']"#
        for pattern in [metaA, metaB] {
            if let price = firstPrice(pattern, in: page) {
                return finish(price, title, nil, snippet: nil, page: page)
            }
        }

        // 3) Prix présent dans l'état JSON de la page (le plus bas d'abord)
        let state = #""\\?(?:lowPrice|lowestPrice|minPrice|priceAmount|currentPrice|salePrice|finalPrice)\\?"\s*:\s*\\?"?"# + number
        if let price = firstPrice(state, in: page) {
            return finish(price, title, nil, snippet: nil, page: page)
        }

        // 4) Amazon et boutiques voisines : le prix est dans un texte caché pour les lecteurs d'écran
        for m in matches(#"class="a-offscreen"[^>]*>\s*([^<]{1,40}?)\s*<"#, in: page) {
            if let price = parsePrice(firstNumber(in: m[1]) ?? ""), price > 0 {
                return finish(price, title, nil, snippet: m[1], page: page)
            }
        }

        // 5) Texte « à partir de 299,00 € », « from $299 », « ab 299 € »
        let words = #"\b(?:à partir de|dès|ab|ab nur|from|starting at|desde|a partir de)\b"#
        let before = words + #"\s*(?:<[^>]+>\s*)*[€$£]\s*"# + number
        let after = words + #"\s*(?:<[^>]+>\s*)*"# + number + #"\s*(?:<[^>]+>\s*)*"# + currencyMarks
        for pattern in [before, after] {
            for m in matches(pattern, in: page) {
                if let price = parsePrice(m[1]), price > 0 {
                    return finish(price, title, nil, snippet: m[0], page: page)
                }
            }
        }

        return PriceResult(price: nil, title: title, currency: pageCurrency(page), explicit: pageCurrency(page) != nil)
    }

    private static func finish(_ price: Double, _ title: String?, _ currency: String?,
                               snippet: String?, page: String) -> PriceResult {
        if let c = Currencies.normalize(currency) {
            return PriceResult(price: price, title: title, currency: c, explicit: true)
        }
        if let c = pageCurrency(page) {
            return PriceResult(price: price, title: title, currency: c, explicit: true)
        }
        if let text = snippet {
            if let c = Currencies.fromUnambiguousSymbol(text) {
                return PriceResult(price: price, title: title, currency: c, explicit: true)
            }
            if let c = Currencies.fromSymbol(text) {
                return PriceResult(price: price, title: title, currency: c, explicit: false)
            }
        }
        return PriceResult(price: price, title: title, currency: nil, explicit: false)
    }

    /// Devise annoncée par la page (balises meta ou données structurées).
    private static func pageCurrency(_ page: String) -> String? {
        let metaNames = #"(?:product:price:currency|og:price:currency|priceCurrency)"#
        let patterns: [String] = [
            #"<meta[^>]+(?:property|itemprop|name)=["']"# + metaNames + #"["'][^>]*?content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]*?(?:property|itemprop|name)=["']"# + metaNames + #"["']"#,
            #"\\?"priceCurrency\\?"\s*:\s*\\?"([A-Za-z]{3})"#,
            #"\\?"currencyCode\\?"\s*:\s*\\?"([A-Za-z]{3})"#,
            #"itemprop=["']priceCurrency["'][^>]*content=["']([A-Za-z]{3})["']"#
        ]
        for pattern in patterns {
            for m in matches(pattern, in: page) {
                if let c = Currencies.normalize(m[1]) { return c }
            }
        }
        return nil
    }

    private static func firstPrice(_ pattern: String, in text: String) -> Double? {
        for m in matches(pattern, in: text) {
            if let value = parsePrice(m[1]), value > 0 { return value }
        }
        return nil
    }

    private static func firstNumber(in text: String) -> String? {
        matches(number, in: text).first?[1]
    }

    private static func offersIn(_ node: Any) -> [(price: Double, currency: String?)] {
        var out: [(price: Double, currency: String?)] = []
        if let dict = node as? [String: Any] {
            let cur: String? = Currencies.normalize(dict["priceCurrency"] as? String)
            for key in ["lowPrice", "price"] {
                guard let value = dict[key] else { continue }
                if let n = value as? NSNumber {
                    out.append((price: n.doubleValue, currency: cur))
                } else if let s = value as? String, let n = parsePrice(s) {
                    out.append((price: n, currency: cur))
                }
            }
            for value in dict.values { out += offersIn(value) }
        } else if let array = node as? [Any] {
            for value in array { out += offersIn(value) }
        }
        return out
    }

    /// Convertit "1 299,99", "1299.99", "1.299,99" ou "1,299.99" en Double (saisie de l'utilisateur).
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

    /// Comme parseNumber, mais pour les prix lus sur une page : « 1,299 » est mille deux cent quatre-vingt-dix-neuf.
    static func parsePrice(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains(","), !t.contains(".") {
            let parts: [String] = t.components(separatedBy: ",")
            if let last = parts.last, last.count == 3, let first = parts.first, first != "0", !first.isEmpty {
                return Double(parts.joined())
            }
        }
        return parseNumber(t)
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
