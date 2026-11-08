import Foundation

struct FetchError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Lit le prix d'un produit directement sur la page (idealo ou autre).
enum PriceFetcher {

    static func fetch(urlString: String) async throws -> (price: Double, title: String?) {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw FetchError(message: "Lien invalide.")
        }

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

        let page = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let extracted = extract(from: page)
        guard let price = extracted.price else {
            throw FetchError(message: "Prix introuvable sur cette page. Vérifie le lien ou utilise « Prix manuel ».")
        }
        return (price, extracted.title)
    }

    // MARK: - Extraction

    static func extract(from page: String) -> (price: Double?, title: String?) {
        var title: String?
        if let m = matches(#"<meta[^>]+property="og:title"[^>]+content="([^"]+)""#, in: page).first {
            title = unescape(m[1])
        } else if let m = matches(#"<title[^>]*>(.*?)</title>"#, in: page).first {
            title = unescape(m[1])
        }

        // 1) Données structurées JSON-LD (le plus fiable)
        for block in matches(#"<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: page) {
            guard let data = block[1].data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let price = prices(in: json).first(where: { $0 > 0 }) {
                return (price, title)
            }
        }

        // 2) Balises meta
        let metaPattern = #"<meta[^>]+(?:property|itemprop|name)=["'](?:product:price:amount|price|lowPrice)["'][^>]+content=["']([^"']+)["']"#
        if let m = matches(metaPattern, in: page).first, let p = parseNumber(m[1]), p > 0 {
            return (p, title)
        }

        // 3) Texte « à partir de 299,00 € »
        let textPattern = #"à partir de\s*(?:<[^>]+>\s*)*([\d\s\x{202F}\x{00A0}.,]+?)\s*(?:<[^>]+>\s*)*€"#
        if let m = matches(textPattern, in: page).first, let p = parseNumber(m[1]), p > 0 {
            return (p, title)
        }

        return (nil, title)
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
