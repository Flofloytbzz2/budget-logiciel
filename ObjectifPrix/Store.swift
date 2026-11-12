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
    private var refreshEvery: TimeInterval { TimeInterval(max(Prefs.refreshHours, 1)) * 3600 }
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

    /// Les objectifs affichés (ceux supprimés restent dans `goals` pour la synchro).
    var visibleGoals: [Goal] {
        goals.filter { !$0.isDeleted }
    }

    func goal(_ id: UUID) -> Goal? {
        goals.first { $0.id == id && !$0.isDeleted }
    }

    func add(_ goal: Goal) {
        goals.append(goal)
        SyncService.shared.scheduleSync()
    }

    func delete(_ id: UUID) {
        update(id) { $0.deleted = true }
    }

    /// `touch: false` pour les changements propres à cet appareil (dernière tentative, erreur…).
    func update(_ id: UUID, touch: Bool = true, _ body: (inout Goal) -> Void) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        var copy = goals[index]
        body(&copy)
        if touch { copy.touch() }
        goals[index] = copy
        if touch { SyncService.shared.scheduleSync() }
    }

    /// Applique le résultat d'une synchro (sans relancer de synchro).
    func applyRemote(_ merged: [Goal]) {
        goals = merged
    }

    /// Retourne true si le lien a changé.
    @discardableResult
    func edit(_ id: UUID, name: String, url: String, monthly: Double, alert: Double, currency: String) -> Bool {
        var urlChanged = false
        update(id) { g in
            urlChanged = (g.url != url)
            g.name = name
            g.url = url
            g.monthly = monthly
            g.alertBelow = alert
            g.currency = currency
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

    // MARK: - Sauvegarde

    /// Fichier JSON de sauvegarde (même format que la synchro).
    func backupData() -> Data? {
        let doc = WireDoc(goals: goals.map { $0.wire() })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(doc)
    }

    /// Fusionne une sauvegarde avec les objectifs actuels. Retourne le nombre d'objectifs lus, ou nil si le fichier est illisible.
    @discardableResult
    func restore(from data: Data) -> Int? {
        guard let doc = try? JSONDecoder().decode(WireDoc.self, from: data), !doc.goals.isEmpty else { return nil }
        let incoming: [Goal] = doc.goals.compactMap { Goal(wire: $0) }
        guard !incoming.isEmpty else { return nil }
        goals = SyncMerge.merge(local: goals, remote: incoming)
        SyncService.shared.scheduleSync()
        return incoming.filter { !$0.isDeleted }.count
    }

    /// Objectifs visibles, dans l'ordre choisi dans les réglages.
    func sortedGoals(_ choice: SortChoice) -> [Goal] {
        let list = visibleGoals
        switch choice {
        case .added: return list
        case .progress: return list.sorted { $0.progress > $1.progress }
        case .remaining: return list.sorted { ($0.remaining ?? .greatestFiniteMagnitude) < ($1.remaining ?? .greatestFiniteMagnitude) }
        case .price: return list.sorted { ($0.price ?? .greatestFiniteMagnitude) < ($1.price ?? .greatestFiniteMagnitude) }
        case .name: return list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
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
                messages.append(L.f("notif.drop", x.money(o), x.money(rounded)))
            }
            if x.alertBelow > 0 {
                if rounded <= x.alertBelow, x.alertedPrice != rounded {
                    messages.append(L.f("notif.below", x.money(x.alertBelow)))
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
        update(id, touch: false) { $0.lastAttempt = Date() }

        do {
            let result = try await PriceFetcher.fetch(urlString: g.url)
            let current = goal(id)
            let firstReading: Bool = (current?.price == nil) && (current?.history.isEmpty ?? true)
            if let found = result.currency {
                if firstReading {
                    update(id) { x in x.currency = found }
                } else if result.explicit, found != (current?.cur ?? found) {
                    let message = L.f("err.currency_mismatch", found, current?.cur ?? "")
                    update(id, touch: false) { $0.lastError = message }
                    return message
                }
            }
            update(id) { x in
                if x.name.isEmpty, let t = result.title { x.name = String(t.prefix(60)) }
            }
            recordPrice(id, result.price)
            return nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            update(id, touch: false) { $0.lastError = message }
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
        for g in visibleGoals where !g.url.isEmpty && isDue(g) {
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
    /// `askPermission: false` pendant le tutoriel : la permission est demandée à l'étape dédiée.
    static func setup(askPermission: Bool) {
        let center = UNUserNotificationCenter.current()
        center.delegate = ForegroundNotifier.shared
        if askPermission { requestPermission() }
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func send(title: String, body: String) {
        guard Prefs.notificationsOn else { return }
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
                _ = Settings.shared
                await SyncService.shared.syncNow()
                await Store.shared.refreshDue()
                await SyncService.shared.syncNow()
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(max(min(Prefs.refreshHours, 12), 3)) * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
