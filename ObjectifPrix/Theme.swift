import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// Couleurs de l'appli : elles suivent le thème choisi dans les réglages.
enum Theme {
    static var bg: Color { Color(hex: Prefs.palette.bg) }
    static var panel: Color { Color(hex: Prefs.palette.panel) }
    static var panel2: Color { Color(hex: Prefs.palette.panel2) }
    static var input: Color { Color(hex: Prefs.palette.input) }
    static var border: Color { Color(hex: Prefs.palette.border) }
    static var text: Color { Color(hex: Prefs.palette.text) }
    static var muted: Color { Color(hex: Prefs.palette.muted) }
    static var accent: Color { Color(hex: Prefs.accentHex ?? Prefs.palette.accent) }
    static var violet: Color { accent }
    static var gold: Color { Color(hex: Prefs.palette.gold) }
    static var bad: Color { Color(hex: Prefs.palette.bad) }
    static var onAccent: Color {
        if let hex = Prefs.accentHex {
            return Color(hex: ColorHex.readableText(on: hex))
        }
        return Color(hex: Prefs.palette.onAccent)
    }
    static var scheme: ColorScheme { Prefs.palette.isLight ? .light : .dark }
}

/// Police de l'appli : style et taille choisis dans les réglages.
enum AppFont {
    static func f(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let design: Font.Design
        switch Prefs.fontStyle {
        case .editorial: design = size >= 20 ? .serif : .default
        case .standard: design = .default
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        }
        let adjusted: Font.Weight = (design == .serif && weight == .heavy) ? .bold : weight
        return Font.system(size: size * CGFloat(Prefs.fontScale), weight: adjusted, design: design)
    }
}

struct AppBackground: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat? = nil
    func body(content: Content) -> some View {
        let pad: CGFloat = padding ?? (Prefs.compact ? 12 : 18)
        content
            .padding(pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.border.opacity(0.7), lineWidth: 0.5)))
    }
}

extension View {
    func card(padding: CGFloat? = nil) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.f(16, .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, Prefs.compact ? 10 : 13)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(AppFont.f(13, .semibold))
            .foregroundStyle(Theme.muted)
    }
}
