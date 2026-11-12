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
                        Label(L.t("menu.manual_price"), systemImage: "pencil")
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Label(L.t("menu.edit_goal"), systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L.t("common.ok")) { focused = false }
            }
        }
        .sheet(isPresented: $showEdit) { GoalEditView(goalID: goalID) }
        .sheet(isPresented: $showManual) { ManualPriceView(goalID: goalID) }
        .onChange(of: goal == nil) { gone in
            if gone { dismiss() }
        }
        .overlay(alignment: .bottom) { toastView }
        .animation(Prefs.animations ? Animation.spring() : nil, value: toastText)
    }

    // MARK: - Sections

    private func header(_ g: Goal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(g.displayName)
                .font(AppFont.f(28, .heavy))
                .foregroundStyle(Theme.text)
            if let error = g.lastError {
                Text(L.f("detail.last_failed", error))
                    .font(AppFont.f(13))
                    .foregroundStyle(Theme.bad)
            } else {
                Text(subtitle(g))
                    .font(AppFont.f(13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func subtitle(_ g: Goal) -> String {
        var parts = [g.host]
        if let last = g.lastCheck {
            parts.append(L.f("detail.updated_on", Fmt.dateTime(last)))
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
            return r <= 0 ? L.t("est.reached") : g.money(r)
        }()

        return VStack(spacing: 20) {
            RingView(progress: g.progress)
                .frame(width: 180, height: 180)
                .padding(.top, 6)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(label: L.t("stat.current_price"),
                         value: g.price.map { g.money($0) } ?? "—",
                         sub: variation.text,
                         subColor: variationColor)
                StatTile(label: L.t("stat.saved"),
                         value: g.money(g.saved),
                         sub: L.f("stat.percent_of_goal", String(Int(g.progress * 100))))
                StatTile(label: L.t("stat.missing"),
                         value: remainingText,
                         sub: low.map { L.f("stat.lowest", g.money($0)) } ?? L.t("stat.waiting"))
                StatTile(label: L.t("stat.estimated_date"),
                         value: estimate.value,
                         sub: estimate.sub)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func moneyCard(_ g: Goal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(L.t("money.title"))

            HStack(spacing: 10) {
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .font(AppFont.f(30, .bold))
                    .foregroundStyle(Theme.text)
                Text(Currencies.symbolText(g.cur))
                    .font(AppFont.f(26, .bold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.input))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(focused ? Theme.accent : Theme.border, lineWidth: 1.5))

            TextField(L.t("money.note_placeholder"), text: $note)
                .focused($focused)
                .font(AppFont.f(15))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.input))

            HStack(spacing: 12) {
                Button {
                    move(+1)
                } label: {
                    Label(L.t("money.add"), systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))

                Button {
                    move(-1)
                } label: {
                    Label(L.t("money.remove"), systemImage: "minus")
                }
                .buttonStyle(PillButtonStyle(fill: Theme.bad.opacity(0.18), foreground: Theme.bad))
            }
        }
        .card()
    }

    private func activityCard(_ g: Goal) -> some View {
        let entries = Array(g.log.suffix(8).reversed())
        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L.t("activity.title"))
            if entries.isEmpty {
                Text(L.t("activity.empty"))
                    .font(AppFont.f(14))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(entries) { e in
                    HStack {
                        Text((e.amount > 0 ? "+ " : "− ") + g.money(abs(e.amount)))
                            .font(AppFont.f(16, .bold))
                            .foregroundStyle(e.amount > 0 ? Theme.accent : Theme.bad)
                        Spacer()
                        Text(e.note.isEmpty
                             ? Fmt.shortDate(e.date)
                             : Fmt.shortDate(e.date) + "  ·  " + e.note)
                            .font(AppFont.f(13))
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
            show(L.t("money.invalid"), bad: true)
            return
        }
        let before = goal?.progress ?? 0
        guard store.moveMoney(goalID, amount: value, note: note.trimmingCharacters(in: .whitespaces), sign: sign) else {
            show(L.t("money.nothing_to_remove"), bad: true)
            return
        }
        amount = ""
        note = ""
        focused = false
        Haptics.tap()

        let after = store.goal(goalID)?.progress ?? 0
        if before < 1 && after >= 1 && Prefs.confetti {
            Haptics.success()
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
            show(L.t("detail.no_link"), bad: true)
            return
        }
        if let error = await store.refresh(goalID, manual: true) {
            show(error, bad: true)
        } else {
            show(L.t("detail.price_updated"))
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
                .font(AppFont.f(14, .semibold))
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
