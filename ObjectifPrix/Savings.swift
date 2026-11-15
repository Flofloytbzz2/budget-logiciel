import Foundation
import UserNotifications

// MARK: - Épargne régulière : rappels et ajout automatique (réglages propres à cet appareil)

enum SavingMode: String, Codable, CaseIterable, Identifiable {
    case off, weekly, monthly, auto

    var id: String { rawValue }
    var labelKey: String { "save.mode." + rawValue }
}

struct SavingRule: Codable, Equatable {
    var mode: SavingMode = .off
    var amount: Double = 0
    var day: Int = 1
    var lastAuto: String = ""     // dernier mois traité, "2026-11"
}

@MainActor
final class SavingRules: ObservableObject {
    static let shared = SavingRules()

    private let key = "saving.rules.v1"
    @Published private(set) var rules: [String: SavingRule] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: SavingRule].self, from: data) {
            rules = decoded
        }
    }

    func rule(for id: UUID) -> SavingRule {
        rules[id.uuidString] ?? SavingRule()
    }

    func set(_ rule: SavingRule, for id: UUID) {
        var updated: SavingRule = rule
        let old: SavingRule? = rules[id.uuidString]
        if updated.mode == .auto {
            let changed: Bool = (old?.mode != .auto) || (old?.day != updated.day)
            if changed || (old?.lastAuto ?? "").isEmpty {
                // pas de rattrapage : on part du dernier passage prévu
                updated.lastAuto = Self.monthKey(Self.lastScheduled(day: updated.day, now: Date()))
            } else {
                updated.lastAuto = old?.lastAuto ?? updated.lastAuto
            }
        }
        if updated.mode == .off {
            rules.removeValue(forKey: id.uuidString)
        } else {
            rules[id.uuidString] = updated
        }
        persist()
    }

    func remove(_ id: UUID) {
        guard rules[id.uuidString] != nil else { return }
        rules.removeValue(forKey: id.uuidString)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Ajout automatique

    /// Ajoute l'épargne des mois écoulés depuis le dernier passage (12 mois maximum d'un coup).
    func applyAuto(store: Store) {
        let cal: Calendar = Calendar.current
        let now: Date = Date()
        var changed = false

        for goal in store.visibleGoals {
            var current: SavingRule = rule(for: goal.id)
            guard current.mode == .auto, current.amount > 0 else { continue }

            guard var cursor = Self.parseKey(current.lastAuto) else {
                current.lastAuto = Self.monthKey(Self.lastScheduled(day: current.day, now: now))
                rules[goal.id.uuidString] = current
                changed = true
                continue
            }

            var applied = 0
            while applied < 12 {
                guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
                let parts: DateComponents = cal.dateComponents([.year, .month], from: next)
                let target: DateComponents = DateComponents(year: parts.year, month: parts.month,
                                                            day: min(max(current.day, 1), 28), hour: 9)
                guard let when = cal.date(from: target), when <= now else { break }
                _ = store.moveMoney(goal.id, amount: current.amount, note: L.t("save.auto_note"), sign: 1)
                cursor = next
                current.lastAuto = Self.monthKey(next)
                applied += 1
            }
            if applied > 0 {
                rules[goal.id.uuidString] = current
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: - Dates

    static func monthKey(_ date: Date) -> String {
        let parts: DateComponents = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 1970, parts.month ?? 1)
    }

    static func parseKey(_ key: String) -> Date? {
        let pieces: [String] = key.split(separator: "-").map { String($0) }
        guard pieces.count == 2, let year = Int(pieces[0]), let month = Int(pieces[1]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))
    }

    /// Date du dernier passage prévu (le `day` du mois en cours s'il est déjà passé, sinon celui du mois précédent).
    static func lastScheduled(day: Int, now: Date) -> Date {
        let cal: Calendar = Calendar.current
        let parts: DateComponents = cal.dateComponents([.year, .month], from: now)
        let target: DateComponents = DateComponents(year: parts.year, month: parts.month,
                                                    day: min(max(day, 1), 28), hour: 9)
        if let thisMonth = cal.date(from: target), thisMonth <= now { return thisMonth }
        if let thisMonth = cal.date(from: target), let previous = cal.date(byAdding: .month, value: -1, to: thisMonth) {
            return previous
        }
        return now
    }
}

// MARK: - Rappels (notifications locales répétées)

@MainActor
enum Reminders {
    private struct Item {
        let id: String
        let mode: SavingMode
        let amount: Double
        let day: Int
        let name: String
        let amountText: String
    }

    static func reschedule(store: Store) {
        let center: UNUserNotificationCenter = UNUserNotificationCenter.current()

        let add: UNNotificationAction = UNNotificationAction(identifier: "ADD", title: L.t("rem.add_action"), options: [])
        let category: UNNotificationCategory = UNNotificationCategory(identifier: "SAVE", actions: [add],
                                                                       intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])

        var items: [Item] = []
        if Prefs.notificationsOn {
            for goal in store.visibleGoals {
                let rule: SavingRule = SavingRules.shared.rule(for: goal.id)
                guard rule.mode == .weekly || rule.mode == .monthly else { continue }
                items.append(Item(id: goal.id.uuidString, mode: rule.mode, amount: rule.amount, day: rule.day,
                                  name: goal.displayName, amountText: goal.money(rule.amount)))
            }
        }
        let title: String = L.t("app.name")

        center.getPendingNotificationRequests { pending in
            let old: [String] = pending.map { $0.identifier }.filter { $0.hasPrefix("rem-") }
            center.removePendingNotificationRequests(withIdentifiers: old)

            for item in items {
                var parts = DateComponents()
                parts.hour = 10
                parts.minute = 0
                if item.mode == .weekly {
                    parts.weekday = 1
                } else {
                    parts.day = min(max(item.day, 1), 28)
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.sound = .default
                if item.amount > 0 {
                    content.body = L.f("rem.body", item.amountText, item.name)
                    content.categoryIdentifier = "SAVE"
                } else {
                    content.body = L.f("rem.body_generic", item.name)
                }
                content.userInfo = ["goal": item.id, "amount": item.amount]
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
                let request = UNNotificationRequest(identifier: "rem-" + item.id, content: content, trigger: trigger)
                center.add(request)
            }
        }
    }
}
