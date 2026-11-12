import SwiftUI

// MARK: - Tutoriel de premier lancement (relançable depuis les réglages)

struct TutorialView: View {
    @EnvironmentObject var settings: Settings
    @State private var step = 0
    @State private var notificationsAsked = false

    private let lastStep = 5

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    page
                        .id(step)
                        .transition(.opacity)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                bottomBar
            }
        }
    }

    // MARK: - Barres

    private var topBar: some View {
        HStack {
            Spacer()
            if step < lastStep {
                Button(L.t("tuto.skip")) { finish() }
                    .font(AppFont.f(15, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Theme.accent : Theme.panel2)
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }
            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        go(step - 1)
                    } label: {
                        Text(L.t("tuto.back"))
                    }
                    .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))
                }
                Button {
                    if step >= lastStep { finish() } else { go(step + 1) }
                } label: {
                    Text(step >= lastStep ? L.t("tuto.start") : L.t("tuto.next"))
                }
                .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 8)
    }

    private func go(_ target: Int) {
        Haptics.select()
        withAnimation(Prefs.animations ? Animation.easeInOut(duration: 0.25) : nil) {
            step = target
        }
    }

    private func finish() {
        settings.onboarded = true
        withAnimation(Prefs.animations ? Animation.easeOut(duration: 0.25) : nil) {
            settings.tutorialPresented = false
        }
        settings.tab = 0
    }

    // MARK: - Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0: welcomePage
        case 1: themePage
        case 2: linkPage
        case 3: moneyPage
        case 4: alertsPage
        default: syncPage
        }
    }

    private func header(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.violet, Theme.accent],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Image(systemName: symbol)
                    .font(AppFont.f(36, .bold))
                    .foregroundStyle(Theme.onAccent)
            }
            .padding(.top, 8)
            Text(title)
                .font(AppFont.f(28, .heavy))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(text)
                .font(AppFont.f(16))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var welcomePage: some View {
        VStack(spacing: 22) {
            header("target", L.t("tuto.welcome.title"), L.t("tuto.welcome.text"))
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(L.t("set.language"))
                ForEach(AppLanguage.allCases) { option in
                    languageButton(option)
                }
            }
            .card()
        }
    }

    private func languageButton(_ option: AppLanguage) -> some View {
        let selected: Bool = settings.language == option
        return Button {
            Haptics.select()
            settings.language = option
        } label: {
            HStack {
                Text(option.label)
                    .font(AppFont.f(16, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel2))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? Theme.accent : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var themePage: some View {
        VStack(spacing: 22) {
            header("paintpalette.fill", L.t("tuto.theme.title"), L.t("tuto.theme.text"))
            VStack(alignment: .leading, spacing: 14) {
                ThemeGrid()
                AccentRow()
            }
            .card()
        }
    }

    private var linkPage: some View {
        VStack(spacing: 22) {
            header("link.circle.fill", L.t("tuto.link.title"), L.t("tuto.link.text"))
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(L.t("tuto.link.stores"))
                let stores: [String] = ["Amazon", "idealo", "Best Buy", "Walmart", "eBay", "Fnac", "Darty", "MediaMarkt", "Google Shopping", "…"]
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(stores, id: \.self) { name in
                        Text(name)
                            .font(AppFont.f(13, .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(Theme.panel2))
                    }
                }
                Text(L.t("tuto.link.manual"))
                    .font(AppFont.f(13))
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
    }

    private var moneyPage: some View {
        VStack(spacing: 22) {
            header("plusminus.circle.fill", L.t("tuto.money.title"), L.t("tuto.money.text"))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Label(L.t("money.add"), systemImage: "plus")
                        .font(AppFont.f(16, .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
                    Label(L.t("money.remove"), systemImage: "minus")
                        .font(AppFont.f(16, .bold))
                        .foregroundStyle(Theme.bad)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bad.opacity(0.18)))
                }
                Text(L.t("tuto.money.hint"))
                    .font(AppFont.f(13))
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
    }

    private var alertsPage: some View {
        VStack(spacing: 22) {
            header("bell.badge.fill", L.t("tuto.alerts.title"), L.t("tuto.alerts.text"))
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Notifier.requestPermission()
                    notificationsAsked = true
                } label: {
                    Label(notificationsAsked ? L.t("tuto.alerts.asked") : L.t("tuto.alerts.enable"),
                          systemImage: notificationsAsked ? "checkmark" : "bell")
                }
                .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
                Text(L.t("tuto.alerts.hint"))
                    .font(AppFont.f(13))
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
    }

    private var syncPage: some View {
        VStack(spacing: 22) {
            header("arrow.triangle.2.circlepath", L.t("tuto.sync.title"), L.t("tuto.sync.text"))
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(L.t("tuto.sync.where"))
                Text(L.t("tuto.sync.hint"))
                    .font(AppFont.f(14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }
}
