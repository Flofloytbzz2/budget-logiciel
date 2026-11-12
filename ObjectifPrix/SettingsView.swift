import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Blocs réutilisés (réglages + tutoriel)

struct ThemeGrid: View {
    @EnvironmentObject var settings: Settings
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ThemeID.allCases) { option in
                themeButton(option)
            }
        }
    }

    private func themeButton(_ option: ThemeID) -> some View {
        let p: Palette = option.palette
        let selected: Bool = settings.theme == option
        return Button {
            Haptics.select()
            settings.theme = option
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: p.bg))
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: p.accent)).frame(width: 14, height: 14)
                        Circle().fill(Color(hex: p.secondary)).frame(width: 14, height: 14)
                        Circle().fill(Color(hex: p.panel2)).frame(width: 14, height: 14)
                    }
                }
                .frame(height: 48)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2.5 : 1))
                Text(L.t(option.labelKey))
                    .font(AppFont.f(12, .semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .buttonStyle(.plain)
    }
}

struct AccentRow: View {
    @EnvironmentObject var settings: Settings
    private let colors: [UInt32] = [
        0x2DE2B1, 0x38BDF8, 0x6366F1, 0xC084FC, 0xF472B6,
        0xFB7185, 0xFB923C, 0xFACC15, 0x4ADE80, 0xE2E8F0
    ]
    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 38), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            Button {
                Haptics.select()
                settings.accentHex = nil
            } label: {
                ZStack {
                    Circle().fill(Color(hex: settings.theme.palette.accent))
                    Image(systemName: "sparkles")
                        .font(AppFont.f(13, .bold))
                        .foregroundStyle(Color(hex: settings.theme.palette.onAccent))
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Theme.text, lineWidth: settings.accentHex == nil ? 2.5 : 0).padding(-3))
            }
            .buttonStyle(.plain)

            ForEach(colors, id: \.self) { hex in
                Button {
                    Haptics.select()
                    settings.accentHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Theme.text, lineWidth: settings.accentHex == hex ? 2.5 : 0).padding(-3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FontSizeRow: View {
    @EnvironmentObject var settings: Settings
    private let scales: [Double] = [0.85, 1.0, 1.15, 1.3, 1.4]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<scales.count, id: \.self) { index in
                let value: Double = scales[index]
                let selected: Bool = abs(settings.fontScale - value) < 0.01
                Button {
                    Haptics.select()
                    settings.fontScale = value
                } label: {
                    Text("A")
                        .font(Font.system(size: 12 + CGFloat(index) * 4, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selected ? Theme.accent : Theme.panel2))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Écran Réglages

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var store: Store
    @Environment(\.openURL) private var openURL

    @State private var backupURL: URL?
    @State private var showImport = false
    @State private var importMessage = ""
    @State private var importBad = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        previewCard
                        appearanceCard
                        languageCard
                        pricesCard
                        experienceCard
                        dataCard
                        helpCard
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(L.t("tab.settings"))
        }
        .tint(Theme.accent)
        .onAppear(perform: prepareBackup)
        .onChange(of: store.goals) { _ in prepareBackup() }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [UTType.json]) { result in
            handleImport(result)
        }
        .confirmationDialog(L.t("set.reset_q"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L.t("set.reset"), role: .destructive) { settings.resetAll() }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L.t("set.reset_msg"))
        }
    }

    // MARK: - Cartes

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(L.t("set.preview"))
            HStack(alignment: .firstTextBaseline) {
                Text("Apple Watch SE")
                    .font(AppFont.f(18, .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("62 %")
                    .font(AppFont.f(18, .heavy))
                    .foregroundStyle(Theme.accent)
            }
            Capsule()
                .fill(Theme.panel2)
                .frame(height: 8)
                .overlay(
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.violet, Theme.accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.62)
                    })
            Text(Fmt.money(184.5, settings.defaultCurrency) + " / " + Fmt.money(299, settings.defaultCurrency))
                .font(AppFont.f(13))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(L.t("set.appearance"))
            Text(L.t("set.theme")).font(AppFont.f(14, .semibold)).foregroundStyle(Theme.text)
            ThemeGrid()
            Text(L.t("set.accent")).font(AppFont.f(14, .semibold)).foregroundStyle(Theme.text)
            AccentRow()
            Divider().overlay(Theme.border)
            pickerRow(L.t("set.font")) {
                Picker("", selection: $settings.fontStyle) {
                    ForEach(FontStyle.allCases) { option in
                        Text(L.t(option.labelKey)).tag(option)
                    }
                }
            }
            Text(L.t("set.font_size")).font(AppFont.f(14, .semibold)).foregroundStyle(Theme.text)
            FontSizeRow()
            Divider().overlay(Theme.border)
            toggleRow(L.t("set.compact"), $settings.compact)
        }
        .card()
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L.t("set.language_formats"))
            pickerRow(L.t("set.language")) {
                Picker("", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            pickerRow(L.t("set.currency")) {
                Picker("", selection: $settings.defaultCurrency) {
                    ForEach(Currencies.all, id: \.self) { code in
                        Text(code + " " + Currencies.symbolText(code)).tag(code)
                    }
                }
            }
            pickerRow(L.t("set.number_format")) {
                Picker("", selection: $settings.numberFormat) {
                    ForEach(NumberFormatChoice.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            pickerRow(L.t("set.date_format")) {
                Picker("", selection: $settings.dateFormat) {
                    ForEach(DateFormatChoice.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            Text(L.t("set.currency_help"))
                .font(AppFont.f(12))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var pricesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L.t("set.prices"))
            pickerRow(L.t("set.refresh")) {
                Picker("", selection: $settings.refresh) {
                    ForEach(RefreshChoice.allCases) { option in
                        Text(L.t(option.labelKey)).tag(option)
                    }
                }
            }
            Text(L.t("set.refresh_help"))
                .font(AppFont.f(12))
                .foregroundStyle(Theme.muted)
            Divider().overlay(Theme.border)
            toggleRow(L.t("set.notifications"), $settings.notificationsOn)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Label(L.t("set.system_notifications"), systemImage: "bell.badge")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))
        }
        .card()
    }

    private var experienceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L.t("set.experience"))
            toggleRow(L.t("set.confetti"), $settings.confetti)
            toggleRow(L.t("set.animations"), $settings.animations)
            toggleRow(L.t("set.haptics"), $settings.haptics)
            toggleRow(L.t("set.confirm_delete"), $settings.confirmDelete)
            Divider().overlay(Theme.border)
            pickerRow(L.t("set.sort")) {
                Picker("", selection: $settings.sort) {
                    ForEach(SortChoice.allCases) { option in
                        Text(L.t(option.labelKey)).tag(option)
                    }
                }
            }
        }
        .card()
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L.t("set.data"))
            Text(L.t("set.data_help"))
                .font(AppFont.f(13))
                .foregroundStyle(Theme.muted)
            if let url = backupURL {
                ShareLink(item: url) {
                    Label(L.t("set.export"), systemImage: "square.and.arrow.up")
                        .font(AppFont.f(16, .bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.vertical, Prefs.compact ? 10 : 14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
                }
            }
            Button {
                importMessage = ""
                showImport = true
            } label: {
                Label(L.t("set.import"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))
            if !importMessage.isEmpty {
                Text(importMessage)
                    .font(AppFont.f(13, .semibold))
                    .foregroundStyle(importBad ? Theme.bad : Theme.accent)
            }
        }
        .card()
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L.t("set.help"))
            Button {
                settings.tab = 0
                settings.tutorialPresented = true
            } label: {
                Label(L.t("set.replay_tutorial"), systemImage: "questionmark.circle")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))
            Button {
                confirmReset = true
            } label: {
                Label(L.t("set.reset"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.bad.opacity(0.18), foreground: Theme.bad))
            Text(L.f("set.about", L.t("app.name"), appVersion))
                .font(AppFont.f(12))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    // MARK: - Lignes

    private func toggleRow(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Text(title)
                .font(AppFont.f(15))
                .foregroundStyle(Theme.text)
        }
        .tint(Theme.accent)
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder _ picker: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(AppFont.f(15))
                .foregroundStyle(Theme.text)
            Spacer()
            picker()
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }

    // MARK: - Données

    private var appVersion: String {
        let info: [String: Any] = Bundle.main.infoDictionary ?? [:]
        return info["CFBundleShortVersionString"] as? String ?? "3.0"
    }

    private func prepareBackup() {
        guard let data = store.backupData() else {
            backupURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("objectif-prix-sauvegarde.json")
        do {
            try data.write(to: url, options: .atomic)
            backupURL = url
        } catch {
            backupURL = nil
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            importBad = true
            importMessage = L.t("set.import_failed")
        case .success(let url):
            let access: Bool = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let count = store.restore(from: data) else {
                importBad = true
                importMessage = L.t("set.import_failed")
                return
            }
            importBad = false
            importMessage = L.f("set.import_ok", String(count))
        }
    }
}
