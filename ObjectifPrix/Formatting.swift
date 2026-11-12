import Foundation

enum Fmt {
    /// Langue des nombres selon le réglage (automatique = langue de l'appli).
    static func numberLocale() -> Locale {
        switch Prefs.numberFormat {
        case .fr: return Locale(identifier: "fr_FR")
        case .en: return Locale(identifier: "en_US")
        case .auto: return Locale(identifier: L.localeID)
        }
    }

    static func money(_ value: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = numberLocale()
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f %@", value, currency)
    }

    private static func dateFormatter(pattern: String?, template: String) -> DateFormatter {
        let f = DateFormatter()
        let locale = Locale(identifier: L.localeID)
        f.locale = locale
        if let pattern = pattern {
            f.dateFormat = pattern
        } else {
            f.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) ?? "dd/MM"
        }
        return f
    }

    static func shortDate(_ date: Date) -> String {
        let pattern: String?
        switch Prefs.dateFormat {
        case .auto: pattern = nil
        case .dmy: pattern = "dd/MM"
        case .mdy: pattern = "MM/dd"
        case .ymd: pattern = "MM-dd"
        }
        return dateFormatter(pattern: pattern, template: "ddMM").string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        let pattern: String?
        switch Prefs.dateFormat {
        case .auto: pattern = nil
        case .dmy: pattern = "dd/MM/yyyy"
        case .mdy: pattern = "MM/dd/yyyy"
        case .ymd: pattern = "yyyy-MM-dd"
        }
        return dateFormatter(pattern: pattern, template: "ddMMyyyy").string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        dateFormatter(pattern: nil, template: "LLLLyyyy").string(from: date)
    }

    static func clock(_ date: Date) -> String {
        dateFormatter(pattern: "HH:mm", template: "HHmm").string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        shortDate(date) + " " + clock(date)
    }

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
