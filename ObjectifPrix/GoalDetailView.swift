import SwiftUI

struct GoalDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID

    @State private var amount = ""
    @State private var note = ""
    @State private var showEdit = false
    @State private var showManual = false
    @State private var toastText: String?
    @State private var toastBad = false
    @State private var confettiID: UUID?
    @FocusState private var focused: Bool

    private var goal: Goal? { store.goal(goalID) }

    var body: some View {
        ZStack {
            AppBackground()
            if let g = goal {
                ScrollView {
                    VStack(spacing: 16) {
                        header(g)
                        heroCard(g)
                        moneyCard(g)
                        PriceChart(goal: g)
                        activityCard(g)
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await refresh() }
            }
            if confettiID != nil {
                ConfettiView()
                    .id(confettiID)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .navigationTitle(goal?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if store.fetching.contains(goalID) {
                    ProgressView().tint(Theme.accent)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                Menu {
                    Button {
                        showManual = true
                    } label: {
                        Label("Prix manuel", systemImage: "pencil")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label("Modifier l'objectif", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focused = false }
            }
        }
        .sheet(isPresented: $showEdit) { GoalEditView(goalID: goalID) }
        .sheet(isPresented: $showManual) { ManualPriceView(goalID: goalID) }
        .onChange(of: goal == nil) { gone in
            if gone { dismiss() }
        }
        .overlay(alignment: .bottom) { toastView }
        .animation(.spring(), value: toastText)
    }

    // MARK: - Sections

    private func header(_ g: Goal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(g.displayName)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
            if let error = g.lastError {
                Text("Dernier relevé échoué : \(error)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.bad)
            } else {
                Text(subtitle(g))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func subtitle(_ g: Goal) -> String {
        var parts = [g.host]
        if let last = g.lastCheck {
            parts.append("mis à jour le " + Fmt.dateTime.string(from: last))
        }
        return parts.joined(separator: "  ·  ")
    }

    private func heroCard(_ g: Goal) -> some View {
        let variation = g.variationInfo()
        let variationColor: Color = {
            switch variation.trend {
            case .down: return Theme.accent
            case .up: return Theme.bad
            default: return Theme.muted
            }
        }()
        let estimate = g.estimate()
        let low = g.history.map(\.price).min()
        let remainingText: String = {
            guard let r = g.remaining else { return "—" }
            return r <= 0 ? "Atteint !" : Fmt.euro(r)
        }()

        return VStack(spacing: 20) {
            RingView(progress: g.progress)
                .frame(width: 180, height: 180)
                .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(label: "Prix actuel",
                         value: g.price.map(Fmt.euro) ?? "—",
                         sub: variation.text,
                         subColor: variationColor)
                StatTile(label: "Épargné",
                         value: Fmt.euro(g.saved),
                         sub: "\(Int(g.progress * 100)) % de l'objectif")
                StatTile(label: "Il manque",
                         value: remainingText,
                         sub: low.map { "Plus bas : \(Fmt.euro($0))" } ?? "En attente d'un relevé")
                StatTile(label: "Date estimée",
                         value: estimate.value,
                         sub: estimate.sub)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func moneyCard(_ g: Goal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Mon argent")

            HStack(spacing: 10) {
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("€")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.input))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(focused ? Theme.accent : Theme.border, lineWidth: 1.5))

            TextField("Note facultative (prime, cadeau…)", text: $note)
                .focused($focused)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.input))

            HStack(spacing: 12) {
                Button {
                    move(+1)
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))

                Button {
                    move(-1)
                } label: {
                    Label("Retirer", systemImage: "minus")
                }
                .buttonStyle(PillButtonStyle(fill: Theme.bad.opacity(0.18), foreground: Theme.bad))
            }
        }
        .card()
    }

    private func activityCard(_ g: Goal) -> some View {
        let entries = Array(g.log.suffix(8).reversed())
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Activité")
            if entries.isEmpty {
                Text("Aucun mouvement pour l'instant.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(entries) { e in
                    HStack {
                        Text((e.amount > 0 ? "+ " : "− ") + Fmt.euro(abs(e.amount)))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(e.amount > 0 ? Theme.accent : Theme.bad)
                        Spacer()
                        Text(e.note.isEmpty
                             ? Fmt.shortDate.string(from: e.date)
                             : Fmt.shortDate.string(from: e.date) + "  ·  " + e.note)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Actions

    private func move(_ sign: Double) {
        guard let value = Fmt.amount(amount), value > 0 else {
            show("Montant invalide (ex : 25 ou 12,50)", bad: true)
            return
        }
        let before = goal?.progress ?? 0
        guard store.moveMoney(goalID, amount: value, note: note.trimmingCharacters(in: .whitespaces), sign: sign) else {
            show("Il n'y a rien à retirer", bad: true)
            return
        }
        amount = ""
        note = ""
        focused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let after = store.goal(goalID)?.progress ?? 0
        if before < 1 && after >= 1 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let id = UUID()
            confettiID = id
            Task {
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                if confettiID == id { confettiID = nil }
            }
        }
    }

    private func refresh() async {
        guard let g = goal else { return }
        if g.url.isEmpty {
            show("Pas de lien pour cet objectif : utilise « Prix manuel »", bad: true)
            return
        }
        if let error = await store.refresh(goalID, manual: true) {
            show(error, bad: true)
        } else {
            show("Prix mis à jour")
        }
    }

    private func show(_ text: String, bad: Bool = false) {
        toastBad = bad
        toastText = text
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if toastText == text { toastText = nil }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let text = toastText {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(toastBad ? Color.white : Theme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(toastBad ? Theme.bad : Theme.accent))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
