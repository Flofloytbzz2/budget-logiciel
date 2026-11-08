import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let bg = Color(hex: 0x0A0E1A)
    static let panel = Color(hex: 0x121829)
    static let panel2 = Color(hex: 0x1A2340)
    static let input = Color(hex: 0x0D1322)
    static let border = Color(hex: 0x26304F)
    static let text = Color(hex: 0xEAF0FF)
    static let muted = Color(hex: 0x8390B0)
    static let accent = Color(hex: 0x2DE2B1)
    static let violet = Color(hex: 0x7C5CFF)
    static let gold = Color(hex: 0xFFC857)
    static let bad = Color(hex: 0xFF5C7A)
    static let onAccent = Color(hex: 0x04281F)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.violet.opacity(0.22), .clear],
                           center: .topLeading, startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Theme.accent.opacity(0.12), .clear],
                           center: .bottomTrailing, startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

struct PillButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
            .foregroundStyle(Theme.muted)
    }
}
