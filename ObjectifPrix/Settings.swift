import SwiftUI
import UIKit
import UserNotifications

// MARK: - Langues

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, fr, en, es, de

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L.t("lang.auto")
        case .fr: return "Français"
        case .en: return "English"
        case .es: return "Español"
        case .de: return "Deutsch"
        }
    }
}

/// Traductions : L.t("clé") ou L.f("clé", "valeur1", "valeur2") pour les {1}, {2}.
enum L {
    static var code: String = "fr"

    static func resolve(_ language: AppLanguage) -> String {
        switch language {
        case .fr: return "fr"
        case .en: return "en"
        case .es: return "es"
        case .de: return "de"
        case .auto:
            let first: String = Locale.preferredLanguages.first ?? "en"
            let prefix: String = String(first.prefix(2)).lowercased()
            let supported: [String] = ["fr", "en", "es", "de"]
            return supported.contains(prefix) ? prefix : "en"
        }
    }

    static func apply(_ language: AppLanguage) {
        code = resolve(language)
    }

    static var localeID: String {
        switch code {
        case "fr": return "fr_FR"
        case "es": return "es_ES"
        case "de": return "de_DE"
        default: return "en_US"
        }
    }

    static func t(_ key: String) -> String {
        let table: [String: String] = Strings.tables[code] ?? Strings.fr
        if let value = table[key] { return value }
        if let value = Strings.fr[key] { return value }
        return key
    }

    static func f(_ key: String, _ args: String...) -> String {
        var text: String = t(key)
        var index: Int = 1
        for arg in args {
            text = text.replacingOccurrences(of: "{" + String(index) + "}", with: arg)
            index += 1
        }
        return text
    }
}

// MARK: - Choix proposés dans les réglages

enum ThemeID: String, CaseIterable, Identifiable {
    case night, ocean, aurora, forest, ember, amoled, light

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .night: return "theme.night"
        case .ocean: return "theme.ocean"
        case .aurora: return "theme.aurora"
        case .forest: return "theme.forest"
        case .ember: return "theme.ember"
        case .amoled: return "theme.amoled"
        case .light: return "theme.light"
        }
    }

    var palette: Palette {
        switch self {
        case .night:
            return Palette(bg: 0x0A0E1A, panel: 0x121829, panel2: 0x1A2340, input: 0x0D1322, border: 0x26304F,
                           text: 0xEAF0FF, muted: 0x8390B0, accent: 0x2DE2B1, secondary: 0x7C5CFF,
                           gold: 0xFFC857, bad: 0xFF5C7A, onAccent: 0x04281F, isLight: false)
        case .ocean:
            return Palette(bg: 0x06121F, panel: 0x0C1D31, panel2: 0x12294A, input: 0x08182A, border: 0x1E3A5F,
                           text: 0xE8F4FF, muted: 0x7FA0BF, accent: 0x38BDF8, secondary: 0x6366F1,
                           gold: 0xFFC857, bad: 0xFF6B81, onAccent: 0x03233A, isLight: false)
        case .aurora:
            return Palette(bg: 0x0B0A1E, panel: 0x151233, panel2: 0x201B4A, input: 0x0F0D28, border: 0x31296B,
                           text: 0xF1EEFF, muted: 0x9A93C8, accent: 0xC084FC, secondary: 0x2DE2B1,
                           gold: 0xFFC857, bad: 0xFF5C7A, onAccent: 0x2A0F45, isLight: false)
        case .forest:
            return Palette(bg: 0x08130E, panel: 0x0F2018, panel2: 0x16301F, input: 0x0B1913, border: 0x244632,
                           text: 0xE8F7EE, muted: 0x7FA690, accent: 0x4ADE80, secondary: 0xA3E635,
                           gold: 0xFFC857, bad: 0xFF6B6B, onAccent: 0x052E16, isLight: false)
        case .ember:
            return Palette(bg: 0x160A08, panel: 0x221210, panel2: 0x341A16, input: 0x1A0E0B, border: 0x4A2620,
                           text: 0xFFEFE8, muted: 0xB58B80, accent: 0xFB923C, secondary: 0xF43F5E,
                           gold: 0xFFD166, bad: 0xFF5C7A, onAccent: 0x2B1200, isLight: false)
        case .amoled:
            return Palette(bg: 0x000000, panel: 0x0A0A0A, panel2: 0x151515, input: 0x0A0A0A, border: 0x262626,
                           text: 0xFFFFFF, muted: 0x8A8A8A, accent: 0x2DE2B1, secondary: 0x7C5CFF,
                           gold: 0xFFC857, bad: 0xFF5C7A, onAccent: 0x04281F, isLight: false)
        case .light:
            return Palette(bg: 0xF3F5FA, panel: 0xFFFFFF, panel2: 0xE8ECF6, input: 0xF0F3FA, border: 0xD5DBEA,
                           text: 0x0F172A, muted: 0x5B6784, accent: 0x0EA37F, secondary: 0x6D4AFF,
                           gold: 0xD99A00, bad: 0xE11D48, onAccent: 0xFFFFFF, isLight: true)
        }
    }
}

enum FontStyle: String, CaseIterable, Identifiable {
    case standard, rounded, serif, mono

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .standard: return "font.standard"
        case .rounded: return "font.rounded"
        case .serif: return "font.serif"
        case .mono: return "font.mono"
        }
    }
}

enum NumberFormatChoice: String, CaseIterable, Identifiable {
    case auto, fr, en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L.t("fmt.auto")
        case .fr: return "1 234,56"
        case .en: return "1,234.56"
        }
    }
}

enum DateFormatChoice: String, CaseIterable, Identifiable {
    case auto, dmy, mdy, ymd

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L.t("fmt.auto")
        case .dmy: return "31/12/2026"
        case .mdy: return "12/31/2026"
        case .ymd: return "2026-12-31"
        }
    }
}

enum RefreshChoice: Int, CaseIterable, Identifiable {
    case h6 = 6
    case h12 = 12
    case h24 = 24
    case h48 = 48
    case manual = 0

    var id: Int { rawValue }

    var labelKey: String {
        switch self {
        case .h6: return "refresh.h6"
        case .h12: return "refresh.h12"
        case .h24: return "refresh.h24"
        case .h48: return "refresh.h48"
        case .manual: return "refresh.manual"
        }
    }
}

enum SortChoice: String, CaseIterable, Identifiable {
    case added, progress, remaining, price, name

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .added: return "sort.added"
        case .progress: return "sort.progress"
        case .remaining: return "sort.remaining"
        case .price: return "sort.price"
        case .name: return "sort.name"
        }
    }
}

// MARK: - Valeurs lues partout (sans passer par l'acteur principal)

struct Palette {
    let bg: UInt32
    let panel: UInt32
    let panel2: UInt32
    let input: UInt32
    let border: UInt32
    let text: UInt32
    let muted: UInt32
    let accent: UInt32
    let secondary: UInt32
    let gold: UInt32
    let bad: UInt32
    let onAccent: UInt32
    let isLight: Bool
}

enum Prefs {
    static var palette: Palette = ThemeID.night.palette
    static var accentHex: UInt32? = nil
    static var fontStyle: FontStyle = .rounded
    static var fontScale: Double = 1.0
    static var compact: Bool = false
    static var animations: Bool = true
    static var haptics: Bool = true
    static var confetti: Bool = true
    static var confirmDelete: Bool = true
    static var notificationsOn: Bool = true
    static var refreshHours: Int = 24
    static var numberFormat: NumberFormatChoice = .auto
    static var dateFormat: DateFormatChoice = .auto
    static var defaultCurrency: String = "EUR"
}

// MARK: - Réglages (enregistrés sur cet appareil, non synchronisés)

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var language: AppLanguage { didSet { changed() } }
    @Published var theme: ThemeID { didSet { changed() } }
    @Published var accentHex: UInt32? { didSet { changed() } }
    @Published var fontStyle: FontStyle { didSet { changed() } }
    @Published var fontScale: Double { didSet { changed() } }
    @Published var compact: Bool { didSet { changed() } }
    @Published var defaultCurrency: String { didSet { changed() } }
    @Published var numberFormat: NumberFormatChoice { didSet { changed() } }
    @Published var dateFormat: DateFormatChoice { didSet { changed() } }
    @Published var refresh: RefreshChoice { didSet { changed() } }
    @Published var notificationsOn: Bool { didSet { changed() } }
    @Published var confetti: Bool { didSet { changed() } }
    @Published var animations: Bool { didSet { changed() } }
    @Published var haptics: Bool { didSet { changed() } }
    @Published var confirmDelete: Bool { didSet { changed() } }
    @Published var sort: SortChoice { didSet { changed() } }
    @Published var onboarded: Bool { didSet { changed() } }

    /// Le tutoriel est-il affiché en ce moment ? (pas enregistré)
    @Published var tutorialPresented: Bool = false
    /// Onglet affiché (pas enregistré).
    @Published var tab: Int = 0
    /// Augmente à chaque changement de réglage : sert à redessiner les écrans avec le nouveau thème.
    @Published var revision: Int = 0

    /// Taille du texte système (formulaires, etc.) déduite de l'échelle choisie.
    var typeSize: DynamicTypeSize {
        if fontScale >= 1.3 { return .xxxLarge }
        if fontScale >= 1.15 { return .xLarge }
        if fontScale <= 0.9 { return .small }
        return .large
    }

    private static func key(_ name: String) -> String { "set." + name }

    private init() {
        let d = UserDefaults.standard
        language = AppLanguage(rawValue: d.string(forKey: Settings.key("language")) ?? "") ?? .auto
        theme = ThemeID(rawValue: d.string(forKey: Settings.key("theme")) ?? "") ?? .night
        if let value = d.object(forKey: Settings.key("accent")) as? Int {
            accentHex = UInt32(truncatingIfNeeded: value)
        } else {
            accentHex = nil
        }
        fontStyle = FontStyle(rawValue: d.string(forKey: Settings.key("font")) ?? "") ?? .rounded
        let scale: Double = d.object(forKey: Settings.key("fontScale")) as? Double ?? 1.0
        fontScale = min(max(scale, 0.85), 1.4)
        compact = d.object(forKey: Settings.key("compact")) as? Bool ?? false

        let storedCurrency: String? = d.string(forKey: Settings.key("currency"))
        if let c = storedCurrency, Currencies.all.contains(c) {
            defaultCurrency = c
        } else {
            defaultCurrency = Currencies.guessFromLocale()
        }

        numberFormat = NumberFormatChoice(rawValue: d.string(forKey: Settings.key("numfmt")) ?? "") ?? .auto
        dateFormat = DateFormatChoice(rawValue: d.string(forKey: Settings.key("datefmt")) ?? "") ?? .auto
        let hours: Int = d.object(forKey: Settings.key("refresh")) as? Int ?? 24
        refresh = RefreshChoice(rawValue: hours) ?? .h24
        notificationsOn = d.object(forKey: Settings.key("notifs")) as? Bool ?? true
        confetti = d.object(forKey: Settings.key("confetti")) as? Bool ?? true
        animations = d.object(forKey: Settings.key("animations")) as? Bool ?? true
        haptics = d.object(forKey: Settings.key("haptics")) as? Bool ?? true
        confirmDelete = d.object(forKey: Settings.key("confirmDelete")) as? Bool ?? true
        sort = SortChoice(rawValue: d.string(forKey: Settings.key("sort")) ?? "") ?? .added
        onboarded = d.object(forKey: Settings.key("onboarded")) as? Bool ?? false

        applyGlobals()
    }

    private func applyGlobals() {
        L.apply(language)
        Prefs.palette = theme.palette
        Prefs.accentHex = accentHex
        Prefs.fontStyle = fontStyle
        Prefs.fontScale = fontScale
        Prefs.compact = compact
        Prefs.animations = animations
        Prefs.haptics = haptics
        Prefs.confetti = confetti
        Prefs.confirmDelete = confirmDelete
        Prefs.notificationsOn = notificationsOn
        Prefs.refreshHours = refresh.rawValue
        Prefs.numberFormat = numberFormat
        Prefs.dateFormat = dateFormat
        Prefs.defaultCurrency = defaultCurrency
    }

    private func changed() {
        applyGlobals()
        revision += 1
        let d = UserDefaults.standard
        d.set(language.rawValue, forKey: Settings.key("language"))
        d.set(theme.rawValue, forKey: Settings.key("theme"))
        if let hex = accentHex {
            d.set(Int(hex), forKey: Settings.key("accent"))
        } else {
            d.removeObject(forKey: Settings.key("accent"))
        }
        d.set(fontStyle.rawValue, forKey: Settings.key("font"))
        d.set(fontScale, forKey: Settings.key("fontScale"))
        d.set(compact, forKey: Settings.key("compact"))
        d.set(defaultCurrency, forKey: Settings.key("currency"))
        d.set(numberFormat.rawValue, forKey: Settings.key("numfmt"))
        d.set(dateFormat.rawValue, forKey: Settings.key("datefmt"))
        d.set(refresh.rawValue, forKey: Settings.key("refresh"))
        d.set(notificationsOn, forKey: Settings.key("notifs"))
        d.set(confetti, forKey: Settings.key("confetti"))
        d.set(animations, forKey: Settings.key("animations"))
        d.set(haptics, forKey: Settings.key("haptics"))
        d.set(confirmDelete, forKey: Settings.key("confirmDelete"))
        d.set(sort.rawValue, forKey: Settings.key("sort"))
        d.set(onboarded, forKey: Settings.key("onboarded"))
    }

    /// Remet les réglages d'origine (le tutoriel déjà vu reste vu).
    func resetAll() {
        language = .auto
        theme = .night
        accentHex = nil
        fontStyle = .rounded
        fontScale = 1.0
        compact = false
        defaultCurrency = Currencies.guessFromLocale()
        numberFormat = .auto
        dateFormat = .auto
        refresh = .h24
        notificationsOn = true
        confetti = true
        animations = true
        haptics = true
        confirmDelete = true
        sort = .added
    }
}

// MARK: - Retour haptique

@MainActor
enum Haptics {
    static func tap() {
        guard Prefs.haptics else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        guard Prefs.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func select() {
        guard Prefs.haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Conversion couleur <-> nombre (pour le sélecteur de couleur)

enum ColorHex {
    static func value(of color: Color) -> UInt32? {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let ri: UInt32 = UInt32(max(0, min(255, (r * 255).rounded())))
        let gi: UInt32 = UInt32(max(0, min(255, (g * 255).rounded())))
        let bi: UInt32 = UInt32(max(0, min(255, (b * 255).rounded())))
        return (ri << 16) | (gi << 8) | bi
    }

    /// Texte lisible (sombre ou blanc) sur un fond de cette couleur.
    static func readableText(on hex: UInt32) -> UInt32 {
        let r: Double = Double((hex >> 16) & 0xFF) / 255.0
        let g: Double = Double((hex >> 8) & 0xFF) / 255.0
        let b: Double = Double(hex & 0xFF) / 255.0
        let luminance: Double = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? 0x0B1220 : 0xFFFFFF
    }
}
