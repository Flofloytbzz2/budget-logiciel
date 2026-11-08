import Foundation
import SwiftUI
import UserNotifications
import BackgroundTasks

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var goals: [Goal] = [] {
        didSet { save() }
    }
    @Published var fetching: Set<UUID> = []

    private let fileURL: URL
    private let refreshEvery: TimeInterval = 24 * 3600
    private let retryAfterFailure: TimeInterval = 3 * 3600

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("objectif-prix.json")
        load()
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([Goal].self, from: data) {
            goals = saved
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(goals) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Objectifs

    func goal(_ id: UUID) -> Goal? {
        goals.first { $0.id == id }
    }

    func add(_ goal: Goal) {
        goals.append(goal)
    }

    func delete(_ id: UUID) {
        goals.removeAll { $0.id == id }
    }

    func update(_ id: UUID, _ body: (inout Goal) -> Void) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        var copy = goals[index]
        body(&copy)
        goals[index] = copy
    }

    /// Retourne true si le lien a changé.
    @discardableResult
    func edit(_ id: UUID, name: String, url: String, monthly: Double, alert: Double) -> Bool {
        var urlChanged = false
        update(id) { g in
            urlChanged = (g.url != url)
            g.name = name
            g.url = url
            g.monthly = monthly
            g.alertBelow = alert
            if urlChanged {
                g.lastCheck = nil
                g.lastAttempt = nil
                g.lastError = nil
                g.alertedPrice = nil
                if !url.isEmpty {
                    g.price = nil
                    g.history = []
                }
            }
        }
        return urlChanged
    }

    // MARK: - Argent

    /// sign = +1 pour ajouter, -1 pour retirer. Retourne false s'il n'y a rien à faire.
    @discardableResult
    func moveMoney(_ id: UUID, amount: Double, note: String, sign: Double) -> Bool {
        guard amount > 0, let g = goal(id) else { return false }
        let applied = sign < 0 ? min(amount, g.saved) : amount
        guard applied > 0 else { return false }
        update(id) { x in
            x.saved = max(((x.saved + sign * applied) * 100).rounded() / 100, 0)
            x.log.append(MoneyEntry(date: Date(), amount: sign * applied, note: note))
            if x.log.count > 200 { x.log.removeFirst(x.log.count - 200) }
        }
        return true
    }

    // MARK: - Prix

    func recordPrice(_ id: UUID, _ price: Double, notify: Bool = true) {
        guard let current = goal(id) else { return }
        let old = current.price
        let rounded = (price * 100).rounded() / 100
        var messages: [String] = []

        update(id) { x in
            x.price = rounded
            x.lastCheck = Date()
            x.lastError = nil
            if let last = x.history.last, Calendar.current.isDateInToday(last.date) {
                x.history[x.history.count - 1].price = rounded
            } else {
                x.history.append(PricePoint(date: Date(), price: rounded))
            }
            if x.history.count > 365 { x.history.removeFirst(x.history.count - 365) }

            if let o = old, rounded < o - 0.004 {
                messages.append("Baisse de prix : \(Fmt.euro(o)) → \(Fmt.euro(rounded))")
            }
            if x.alertBelow > 0 {
                if rounded <= x.alertBelow, x.alertedPrice != rounded {
                    messages.append("Sous ton seuil de \(Fmt.euro(x.alertBelow))")
                    x.alertedPrice = rounded
                } else if rounded > x.alertBelow {
                    x.alertedPrice = nil
                }
            }
        }

        if notify, !messages.isEmpty {
            Notifier.send(title: current.displayName, body: messages.joined(separator: " · "))
        }
    }

    /// Relève le prix. Retourne un message d'erreur, ou nil si tout s'est bien passé.
    func refresh(_ id: UUID, manual: Bool) async -> String? {
        guard let g = goal(id), !g.url.isEmpty, !fetching.contains(id) else { return nil }
        fetching.insert(id)
        defer { fetching.remove(id) }
        update(id) { $0.lastAttempt = Date() }

        do {
            let result = try await PriceFetcher.fetch(urlString: g.url)
            update(id) { x in
                if x.name.isEmpty, let t = result.title { x.name = String(t.prefix(60)) }
            }
            recordPrice(id, result.price)
            return nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            update(id) { $0.lastError = message }
            return message
        }
    }

    func isDue(_ g: Goal) -> Bool {
        let now = Date()
        if let attempt = g.lastAttempt, attempt > (g.lastCheck ?? .distantPast),
           now.timeIntervalSince(attempt) < retryAfterFailure {
            return false
        }
        guard let last = g.lastCheck else { return true }
        return now.timeIntervalSince(last) >= refreshEvery
    }

    func refreshDue() async {
        for g in goals where !g.url.isEmpty && isDue(g) {
            _ = await refresh(g.id, manual: false)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

// MARK: - Notifications

final class ForegroundNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotifier()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum Notifier {
    static func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = ForegroundNotifier.shared
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Relevé en arrière-plan (au mieux : c'est iOS qui décide de l'heure)

enum BackgroundRefresh {
    static let identifier = "com.objectifprix.app.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            let work = Task { @MainActor in
                await Store.shared.refreshDue()
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
