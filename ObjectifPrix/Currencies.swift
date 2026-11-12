import Foundation

enum Currencies {
    static let all: [String] = [
        "EUR", "USD", "GBP", "CAD", "CHF", "AUD", "JPY", "SEK", "NOK", "DKK",
        "PLN", "CZK", "MXN", "BRL", "INR", "CNY"
    ]

    static func guessFromLocale() -> String {
        if let code = Locale.current.currency?.identifier, all.contains(code) {
            return code
        }
        return "EUR"
    }

    /// Devise sûre à partir d'un symbole (sans ambiguïté). nil si le symbole peut désigner plusieurs devises.
    static func fromUnambiguousSymbol(_ text: String) -> String? {
        if text.contains("€") { return "EUR" }
        if text.contains("£") { return "GBP" }
        if text.contains("₹") { return "INR" }
        if text.contains("zł") { return "PLN" }
        if text.contains("CHF") { return "CHF" }
        return nil
    }

    /// Devise probable à partir d'un symbole ($ → USD par défaut).
    static func fromSymbol(_ text: String) -> String? {
        if let sure = fromUnambiguousSymbol(text) { return sure }
        if text.contains("$") { return "USD" }
        return nil
    }

    /// Code à trois lettres (EUR, usd…) mis en majuscules, ou nil.
    static func normalize(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 3, code.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return nil }
        return code
    }

    /// Symbole court pour les champs de saisie (€, $, £… sinon le code).
    static func symbolText(_ code: String) -> String {
        switch code {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "INR": return "₹"
        default: return code
        }
    }
}
