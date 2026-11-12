import Foundation

struct PricePoint: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var price: Double
}

struct MoneyEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double   // positif = ajout, négatif = retrait
    var note: String
}

enum Trend {
    case down, up, flat, none
}

extension Date {
    /// Maintenant, arrondi à la seconde (même précision que le fichier partagé avec le PC).
    static var nowSeconds: Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }
}

struct Goal: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var price: Double?
    var saved: Double = 0
    var monthly: Double = 0
    var alertBelow: Double = 0
    var lastCheck: Date?
    var lastAttempt: Date?
    var lastError: String?
    var alertedPrice: Double?
    var history: [PricePoint] = []
    var log: [MoneyEntry] = []
    var currency: String?     // devise de l'objectif (nil = devise par défaut)
    var updatedAt: Date?      // dernière modification, sert à la synchro
    var deleted: Bool?        // supprimé (la trace est gardée pour l'autre appareil)

    init(name: String, url: String, monthly: Double = 0, alertBelow: Double = 0) {
        self.name = name
        self.url = url
        self.monthly = monthly
        self.alertBelow = alertBelow
        self.currency = Prefs.defaultCurrency
        self.updatedAt = Date.nowSeconds
    }

    /// Devise utilisée pour afficher les montants de cet objectif.
    var cur: String { currency ?? Prefs.defaultCurrency }

    func money(_ value: Double) -> String { Fmt.money(value, cur) }

    var stamp: Date { updatedAt ?? .distantPast }
    var isDeleted: Bool { deleted ?? false }

    /// Marque l'objectif comme modifié (toujours strictement plus récent que sa version précédente).
    mutating func touch() {
        let now = Date.nowSeconds
        updatedAt = now > stamp ? now : stamp.addingTimeInterval(1)
    }

    var displayName: String { name.isEmpty ? L.t("goal.unnamed") : name }

    var host: String {
        guard !url.isEmpty else { return L.t("goal.manual_price") }
        return URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? L.t("goal.link")
    }

    var progress: Double {
        guard let p = price, p > 0 else { return 0 }
        return min(max(saved / p, 0), 1)
    }

    var remaining: Double? {
        guard let p = price else { return nil }
        return max(p - saved, 0)
    }

    var sortedHistory: [PricePoint] {
        history.sorted { $0.date < $1.date }
    }

    func variationInfo() -> (text: String, trend: Trend) {
        guard price != nil else { return (L.t("var.none"), .none) }
        let h = sortedHistory
        guard h.count >= 2 else { return (L.t("var.first"), .none) }
        let diff = h[h.count - 1].price - h[h.count - 2].price
        if abs(diff) < 0.005 { return (L.t("var.stable"), .flat) }
        let since = Fmt.shortDate(h[h.count - 2].date)
        let arrow = diff < 0 ? "▼ " : "▲ "
        return (arrow + L.f("var.since", money(abs(diff)), since), diff < 0 ? .down : .up)
    }

    func estimate() -> (value: String, sub: String) {
        guard let rem = remaining else { return ("—", L.t("est.unknown_price")) }
        if rem <= 0 { return (L.t("est.reached"), L.t("est.can_buy")) }
        guard monthly > 0 else { return ("—", L.t("est.set_monthly")) }
        let months = rem / monthly
        let days = Int((months * 30.44).rounded())
        let target = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let label = Fmt.monthYear(target).capitalized
        return (label, L.f("est.months", String(Int(months.rounded(.up))), money(monthly)))
    }
}
