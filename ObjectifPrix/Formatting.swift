import Foundation

enum Fmt {
    static let eur: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    static func euro(_ value: Double) -> String {
        eur.string(from: NSNumber(value: value)) ?? String(format: "%.2f €", value)
    }

    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = pattern
        return f
    }

    static let monthYear = formatter("LLLL yyyy")
    static let shortDate = formatter("dd/MM")
    static let fullDate = formatter("dd/MM/yyyy")
    static let dateTime = formatter("dd/MM 'à' HH:mm")

    /// Montant saisi par l'utilisateur ("25", "12,50", "1 299,99"). nil si invalide.
    static func amount(_ raw: String) -> Double? {
        PriceFetcher.parseNumber(raw)
    }

    /// Champ facultatif : vide = 0, invalide ou négatif = nil.
    static func optionalAmount(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        guard let v = PriceFetcher.parseNumber(t), v >= 0 else { return nil }
        return v
    }

    static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value).replacingOccurrences(of: ".", with: ",")
    }
}
