import SwiftUI

struct RootView: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        TabView(selection: $settings.tab) {
            GoalsTab()
                .id(settings.revision)
                .tabItem { Label(L.t("tab.goals"), systemImage: "target") }
                .tag(0)
            AccountView()
                .id(settings.revision)
                .tabItem { Label(L.t("tab.account"), systemImage: "person.crop.circle") }
                .tag(1)
            SettingsView()
                .tabItem { Label(L.t("tab.settings"), systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(Theme.accent)
    }
}

struct GoalsTab: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var settings: Settings
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if store.visibleGoals.isEmpty {
                    EmptyState { showNew = true }
                } else {
                    list
                }
            }
            .navigationTitle(L.t("app.name"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNew = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFont.f(22))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                GoalDetailView(goalID: id)
            }
            .sheet(isPresented: $showNew) {
                GoalEditView(goalID: nil)
            }
        }
        .tint(Theme.accent)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Prefs.compact ? 10 : 14) {
                ForEach(store.sortedGoals(settings.sort)) { goal in
                    NavigationLink(value: goal.id) {
                        GoalCard(goal: goal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable {
            for g in store.visibleGoals where !g.url.isEmpty {
                _ = await store.refresh(g.id, manual: true)
            }
        }
    }
}

struct GoalCard: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if goal.imageURL != nil {
                    ProductImage(urlString: goal.imageURL, size: 52)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.displayName)
                        .font(AppFont.f(18, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    BuyBadge(goal: goal)
                }
                Spacer()
                Text("\(Int(goal.progress * 100)) %")
                    .font(AppFont.f(18, .heavy))
                    .foregroundStyle(goal.progress >= 1 ? Theme.gold : Theme.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panel2)
                    Capsule()
                        .fill(goal.progress >= 1 ? Theme.gold : Theme.accent)
                        .frame(width: max(geo.size.width * goal.progress, goal.progress > 0 ? 6 : 0))
                }
            }
            .frame(height: 5)

            HStack {
                if let price = goal.price {
                    Text(L.f("card.saved_of", goal.money(goal.saved), goal.money(price)))
                } else {
                    Text(L.f("card.saved_unknown", goal.money(goal.saved)))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.f(12, .bold))
            }
            .font(AppFont.f(13))
            .foregroundStyle(Theme.muted)
        }
        .card()
    }
}

struct EmptyState: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.panel2, lineWidth: 8)
                Circle().trim(from: 0, to: 0.62)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 110, height: 110)
            .padding(.bottom, 8)

            Text(L.t("empty.title"))
                .font(AppFont.f(24, .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text(L.t("empty.sub"))
                .font(AppFont.f(15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Button(L.t("empty.cta"), action: action)
                .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
                .padding(.top, 10)
        }
        .padding(32)
    }
}
