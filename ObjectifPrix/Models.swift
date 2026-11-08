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

    init(name: String, url: String, monthly: Double = 0, alertBelow: Double = 0) {
        self.name = name
        self.url = url
        self.monthly = monthly
        self.alertBelow = alertBelow
    }

    var displayName: String { name.isEmpty ? "Sans nom" : name }

    var host: String {
        guard !url.isEmpty else { return "Prix saisi à la main" }
        return URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Lien"
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
        guard price != nil else { return ("Aucun prix relevé", .none) }
        let h = sortedHistory
        guard h.count >= 2 else { return ("Premier relevé", .none) }
        let diff = h[h.count - 1].price - h[h.count - 2].price
        if abs(diff) < 0.005 { return ("Stable", .flat) }
        let since = Fmt.shortDate.string(from: h[h.count - 2].date)
        let arrow = diff < 0 ? "▼ " : "▲ "
        return (arrow + Fmt.euro(abs(diff)) + " depuis le " + since, diff < 0 ? .down : .up)
    }

    func estimate() -> (value: String, sub: String) {
        guard let rem = remaining else { return ("—", "Prix inconnu") }
        if rem <= 0 { return ("Atteint !", "Tu peux l'acheter") }
        guard monthly > 0 else { return ("—", "Fixe une épargne mensuelle") }
        let months = rem / monthly
        let days = Int((months * 30.44).rounded())
        let target = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let label = Fmt.monthYear.string(from: target).capitalized
        return (label, "\(Int(months.rounded(.up))) mois à \(Fmt.euro(monthly))/mois")
    }
}
