import SwiftUI

struct AccountView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncService
    @Environment(\.openURL) private var openURL

    @State private var token = ""
    @State private var busy = false
    @State private var error = ""
    @State private var confirmDisconnect = false
    @FocusState private var focused: Bool

    private let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=gist&description=Objectif%20Prix")

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        if sync.connected {
                            connectedCard
                        } else {
                            connectCard
                        }
                        privacyCard
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(L.t("tab.account"))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("common.ok")) { focused = false }
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - Pas encore connecté

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(L.t("acct.sync"))
            Text(L.t("acct.intro"))
                .font(AppFont.f(15))
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 10) {
                step("1", L.t("acct.step1"))
                step("2", L.t("acct.step2"))
                step("3", L.t("acct.step3"))
            }

            Button {
                if let url = tokenURL { openURL(url) }
            } label: {
                Label(L.t("acct.create_token"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))

            SecureField(L.t("acct.token_placeholder"), text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .font(AppFont.f(16))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Theme.accent : Theme.border, lineWidth: 1.5))

            if !error.isEmpty {
                Text(error)
                    .font(AppFont.f(13))
                    .foregroundStyle(Theme.bad)
            }

            Button {
                connect()
            } label: {
                if busy {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text(L.t("acct.connect"))
                }
            }
            .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
            .disabled(busy)
        }
        .card()
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(AppFont.f(12, .heavy))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(AppFont.f(14))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func connect() {
        focused = false
        busy = true
        error = ""
        Task {
            let result = await sync.connect(token: token)
            busy = false
            if let message = result {
                error = message
            } else {
                token = ""
            }
        }
    }

    // MARK: - Connecté

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(L.t("tab.account"))
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
                    .font(AppFont.f(22))
                Text(L.f("acct.connected_as", sync.login ?? "GitHub"))
                    .font(AppFont.f(17, .bold))
                    .foregroundStyle(Theme.text)
            }
            Text(L.t("acct.connected_info"))
                .font(AppFont.f(14))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 8) {
                if sync.isSyncing {
                    ProgressView().tint(Theme.accent)
                }
                Text(sync.status.isEmpty ? L.f("acct.goal_count", String(store.visibleGoals.count)) : sync.status)
                    .font(AppFont.f(13, .semibold))
                    .foregroundStyle(sync.isError ? Theme.bad : Theme.accent)
            }

            Button {
                Task { await sync.syncNow() }
            } label: {
                Label(L.t("acct.sync_now"), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
            .disabled(sync.isSyncing)

            Button {
                confirmDisconnect = true
            } label: {
                Text(L.t("acct.disconnect"))
            }
            .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))
        }
        .card()
        .confirmationDialog(L.t("acct.disconnect_q"), isPresented: $confirmDisconnect,
                            titleVisibility: .visible) {
            Button(L.t("acct.disconnect"), role: .destructive) { sync.disconnect() }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L.t("acct.disconnect_msg"))
        }
    }

    // MARK: - Confidentialité

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(L.t("acct.privacy_title"))
            Text(L.t("acct.privacy1"))
                .font(AppFont.f(13))
                .foregroundStyle(Theme.muted)
            Text(L.t("acct.privacy2"))
                .font(AppFont.f(13))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }
}
