import Foundation
import Security

// MARK: - Format commun iPhone / PC (le même que dans la version Linux)

struct WirePoint: Codable {
    var t: String
    var price: Double
}

struct WireEntry: Codable {
    var t: String
    var amount: Double
    var note: String
}

struct WireGoal: Codable {
    var id: String
    var name: String
    var url: String
    var price: Double?
    var saved: Double
    var monthly: Double
    var alertBelow: Double
    var lastCheck: String?
    var history: [WirePoint]
    var log: [WireEntry]
    var currency: String?
    var updatedAt: String
    var deleted: Bool
}

/// Décode un élément sans faire échouer toute la liste s'il est abîmé.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct WireDoc: Codable {
    var app: String?
    var version: Int?
    var goals: [WireGoal]

    enum CodingKeys: String, CodingKey {
        case app, version, goals
    }

    init(goals: [WireGoal]) {
        self.app = "objectif-prix"
        self.version = 1
        self.goals = goals
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app)
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        let items = try c.decodeIfPresent([Lossy<WireGoal>].self, forKey: .goals) ?? []
        goals = items.compactMap { $0.value }
    }
}

enum Iso {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(_ date: Date) -> String {
        plain.string(from: date)
    }

    static func date(_ text: String?) -> Date? {
        guard let text = text else { return nil }
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}

extension Goal {
    func wire() -> WireGoal {
        WireGoal(
            id: id.uuidString.lowercased(),
            name: name,
            url: url,
            price: price,
            saved: saved,
            monthly: monthly,
            alertBelow: alertBelow,
            lastCheck: lastCheck.map { Iso.string($0) },
            history: sortedHistory.map { WirePoint(t: Iso.string($0.date), price: $0.price) },
            log: log.map { WireEntry(t: Iso.string($0.date), amount: $0.amount, note: $0.note) },
            currency: currency,
            updatedAt: Iso.string(stamp),
            deleted: isDeleted)
    }

    init?(wire w: WireGoal) {
        guard let uuid = UUID(uuidString: w.id) else { return nil }
        self.init(name: w.name, url: w.url, monthly: w.monthly, alertBelow: w.alertBelow)
        id = uuid
        price = w.price
        saved = w.saved
        lastCheck = Iso.date(w.lastCheck)
        history = w.history
            .compactMap { p in Iso.date(p.t).map { PricePoint(date: $0, price: p.price) } }
            .sorted { $0.date < $1.date }
        log = w.log.compactMap { e in Iso.date(e.t).map { MoneyEntry(date: $0, amount: e.amount, note: e.note) } }
        currency = Currencies.normalize(w.currency) ?? "EUR"
        updatedAt = Iso.date(w.updatedAt) ?? Date.distantPast
        deleted = w.deleted
    }
}

// MARK: - Fusion : pour chaque objectif, la version modifiée en dernier gagne

enum SyncMerge {
    static func merge(local: [Goal], remote: [Goal]) -> [Goal] {
        var byID: [UUID: Goal] = [:]
        var order: [UUID] = []
        for g in local {
            byID[g.id] = g
            order.append(g.id)
        }
        for r in remote {
            if let l = byID[r.id] {
                if r.stamp > l.stamp {
                    var winner = r
                    winner.lastAttempt = l.lastAttempt      // infos propres à cet appareil
                    winner.lastError = l.lastError
                    winner.alertedPrice = l.alertedPrice
                    byID[r.id] = winner
                }
            } else {
                byID[r.id] = r
                order.append(r.id)
            }
        }
        let cutoff = Date().addingTimeInterval(-60 * 86_400)
        return order
            .compactMap { byID[$0] }
            .filter { !($0.isDeleted && $0.stamp < cutoff) }
    }

    static func differs(_ a: [Goal], _ b: [Goal]) -> Bool {
        stamps(a) != stamps(b)
    }

    static func needsPush(merged: [Goal], remote: [Goal]) -> Bool {
        let known = stamps(remote)
        return merged.contains { known[$0.id] != $0.stamp }
    }

    private static func stamps(_ goals: [Goal]) -> [UUID: Date] {
        Dictionary(goals.map { ($0.id, $0.stamp) }, uniquingKeysWith: { _, last in last })
    }
}

// MARK: - Client GitHub (gist secret)

struct GistClient {
    let token: String
    static let fileName = "objectif-prix.json"
    static let gistDescription = "Objectif Prix (données synchronisées)"
    private static let base = "https://api.github.com"

    private func call(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: Self.base + path) else { throw FetchError(message: L.t("err.bad_address")) }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("objectif-prix-ios", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError(message: L.t("err.network"))
        }
        let (data, response) = result

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401:
                throw FetchError(message: L.t("sync.err.token"))
            case 403:
                throw FetchError(message: L.t("sync.err.forbidden"))
            case 404:
                throw FetchError(message: L.t("sync.err.notfound"))
            default:
                throw FetchError(message: L.f("sync.err.http", String(http.statusCode)))
            }
        }
        return data
    }

    func whoami() async throws -> String {
        let data = try await call("GET", "/user")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let login = object["login"] as? String else {
            throw FetchError(message: L.t("sync.err.unexpected"))
        }
        return login
    }

    /// Id du plus ancien gist « Objectif Prix » du compte, ou nil s'il n'y en a pas encore.
    func findGist() async throws -> String? {
        var best: (id: String, created: String)?
        for page in 1...5 {
            let data = try await call("GET", "/gists?per_page=100&page=\(page)")
            guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { break }
            for item in items {
                let files = item["files"] as? [String: Any] ?? [:]
                let description = item["description"] as? String ?? ""
                guard files[Self.fileName] != nil,
                      description.hasPrefix("Objectif Prix"),
                      let id = item["id"] as? String else { continue }
                let created = item["created_at"] as? String ?? ""
                if best == nil || created < (best?.created ?? "") {
                    best = (id, created)
                }
            }
            if items.count < 100 { break }
        }
        return best?.id
    }

    func create(_ doc: WireDoc) async throws -> String {
        let content = try encode(doc)
        let payload: [String: Any] = [
            "description": Self.gistDescription,
            "public": false,
            "files": [Self.fileName: ["content": content]],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await call("POST", "/gists", body: body)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String else {
            throw FetchError(message: L.t("sync.err.unexpected"))
        }
        return id
    }

    func read(_ id: String) async throws -> WireDoc {
        let data = try await call("GET", "/gists/\(id)")
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = object["files"] as? [String: Any],
              let file = files[Self.fileName] as? [String: Any] else {
            throw FetchError(message: L.t("sync.err.nofile"))
        }
        var content = file["content"] as? String ?? ""
        if (file["truncated"] as? Bool) == true,
           let raw = file["raw_url"] as? String,
           raw.hasPrefix("https://gist.githubusercontent.com/"),
           let rawURL = URL(string: raw) {
            let (rawData, _) = try await URLSession.shared.data(from: rawURL)
            content = String(decoding: rawData, as: UTF8.self)
        }
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return WireDoc(goals: [])
        }
        guard let docData = content.data(using: .utf8),
              let doc = try? JSONDecoder().decode(WireDoc.self, from: docData) else {
            throw FetchError(message: L.t("sync.err.unreadable"))
        }
        return doc
    }

    func write(_ id: String, _ doc: WireDoc) async throws {
        let content = try encode(doc)
        let payload: [String: Any] = ["files": [Self.fileName: ["content": content]]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await call("PATCH", "/gists/\(id)", body: body)
    }

    private func encode(_ doc: WireDoc) throws -> String {
        String(decoding: try JSONEncoder().encode(doc), as: UTF8.self)
    }
}

// MARK: - Jeton : trousseau iOS (avec repli si le trousseau refuse)

enum Secrets {
    private static let service = "com.objectifprix.app"
    private static let account = "github-token"
    private static let fallbackKey = "githubTokenFallback"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func saveToken(_ token: String) {
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: fallbackKey)
        } else {
            UserDefaults.standard.set(token, forKey: fallbackKey)
        }
    }

    static func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data,
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return UserDefaults.standard.string(forKey: fallbackKey)
    }

    static func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
    }
}

// MARK: - Moteur de synchronisation

@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published private(set) var connected = false
    @Published private(set) var login: String?
    @Published private(set) var status = ""
    @Published private(set) var isError = false
    @Published private(set) var isSyncing = false

    private var token: String?
    private var gistID: String?
    private var again = false
    private var pending: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private init() {
        token = Secrets.loadToken()
        gistID = defaults.string(forKey: "syncGistID")
        login = defaults.string(forKey: "syncLogin")
        connected = (token != nil && gistID != nil)
    }

    /// Retourne un message d'erreur, ou nil si la connexion a réussi.
    func connect(token newToken: String) async -> String? {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L.t("sync.paste_token") }
        let client = GistClient(token: trimmed)
        do {
            let name = try await client.whoami()
            var id = try await client.findGist()
            if id == nil {
                id = try await client.create(WireDoc(goals: Store.shared.goals.map { $0.wire() }))
            }
            Secrets.saveToken(trimmed)
            defaults.set(id, forKey: "syncGistID")
            defaults.set(name, forKey: "syncLogin")
            token = trimmed
            gistID = id
            login = name
            connected = true
            status = L.t("sync.connected_status")
            isError = false
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        await syncNow()
        return nil
    }

    func disconnect() {
        pending?.cancel()
        Secrets.deleteToken()
        defaults.removeObject(forKey: "syncGistID")
        defaults.removeObject(forKey: "syncLogin")
        token = nil
        gistID = nil
        login = nil
        connected = false
        status = ""
        isError = false
    }

    /// À appeler après une modification : envoie les changements quelques secondes plus tard.
    func scheduleSync(after seconds: Double = 4) {
        guard connected else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let token = token, let gistID = gistID else { return }
        if isSyncing {
            again = true
            return
        }
        isSyncing = true
        isError = false
        status = L.t("sync.syncing")
        let client = GistClient(token: token)
        do {
            let doc = try await client.read(gistID)
            let remote = doc.goals.compactMap { Goal(wire: $0) }
            let store = Store.shared
            let merged = SyncMerge.merge(local: store.goals, remote: remote)
            if SyncMerge.differs(merged, store.goals) {
                store.applyRemote(merged)
            }
            if SyncMerge.needsPush(merged: merged, remote: remote) {
                try await client.write(gistID, WireDoc(goals: merged.map { $0.wire() }))
            }
            status = L.f("sync.synced_at", Fmt.clock(Date()))
        } catch {
            isError = true
            status = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSyncing = false
        if again {
            again = false
            scheduleSync(after: 1)
        }
    }
}
