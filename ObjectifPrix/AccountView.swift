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
            .navigationTitle("Compte")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { focused = false }
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - Pas encore connecté

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Synchronisation")
            Text("Retrouve les mêmes objectifs sur ton iPhone et sur ton ordinateur, avec ton compte GitHub. Rien d'autre à créer.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 10) {
                step("1", "Touche le bouton ci-dessous : GitHub ouvre la création d'un jeton déjà réglé sur « gist ».")
                step("2", "Mets « No expiration » dans Expiration, puis touche « Generate token » tout en bas.")
                step("3", "Copie le jeton (il commence par ghp_) et colle-le ici.")
            }

            Button {
                if let url = tokenURL { openURL(url) }
            } label: {
                Label("Créer mon jeton GitHub", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))

            SecureField("Jeton GitHub (ghp_…)", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.input))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Theme.accent : Theme.border, lineWidth: 1.5))

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.bad)
            }

            Button {
                connect()
            } label: {
                if busy {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text("Se connecter")
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
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.system(size: 14))
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
            SectionLabel("Compte")
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 22))
                Text("Connecté en tant que \(sync.login ?? "GitHub")")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            Text("Tes objectifs, ton épargne et ton historique sont les mêmes sur ton iPhone et sur ton ordinateur. Connecte l'autre appareil avec le même compte GitHub.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 8) {
                if sync.isSyncing {
                    ProgressView().tint(Theme.accent)
                }
                Text(sync.status.isEmpty ? "\(store.visibleGoals.count) objectif(s)" : sync.status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(sync.isError ? Theme.bad : Theme.accent)
            }

            Button {
                Task { await sync.syncNow() }
            } label: {
                Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
            .disabled(sync.isSyncing)

            Button {
                confirmDisconnect = true
            } label: {
                Text("Se déconnecter")
            }
            .buttonStyle(PillButtonStyle(fill: Theme.panel2, foreground: Theme.text))
        }
        .card()
        .confirmationDialog("Se déconnecter du compte ?", isPresented: $confirmDisconnect,
                            titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) { sync.disconnect() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes objectifs restent sur ce téléphone, mais ne seront plus synchronisés.")
        }
    }

    // MARK: - Confidentialité

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Où sont mes données ?")
            Text("Elles sont stockées dans un « gist secret » de ton compte GitHub : il n'est pas listé publiquement, mais toute personne qui aurait son lien pourrait le lire. Il ne contient que les noms, prix et montants de tes objectifs. Ton jeton reste dans le trousseau de ton iPhone.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            Text("Si tu modifies le même objectif sur deux appareils en même temps, la modification la plus récente l'emporte.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }
}
