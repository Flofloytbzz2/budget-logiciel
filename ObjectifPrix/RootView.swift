import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if store.goals.isEmpty {
                    EmptyState { showNew = true }
                } else {
                    list
                }
            }
            .navigationTitle("Objectif Prix")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showNew = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
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
            LazyVStack(spacing: 14) {
                ForEach(store.goals) { goal in
                    NavigationLink(value: goal.id) {
                        GoalCard(goal: goal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .refreshable {
            for g in store.goals where !g.url.isEmpty {
                _ = await store.refresh(g.id, manual: true)
            }
        }
    }
}

struct GoalCard: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.displayName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Spacer()
                Text("\(Int(goal.progress * 100)) %")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(goal.progress >= 1 ? Theme.gold : Theme.accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panel2)
                    Capsule()
                        .fill(LinearGradient(
                            colors: goal.progress >= 1 ? [Theme.gold, Theme.accent] : [Theme.violet, Theme.accent],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * goal.progress, goal.progress > 0 ? 8 : 0))
                }
            }
            .frame(height: 8)

            HStack {
                if let price = goal.price {
                    Text("\(Fmt.euro(goal.saved)) sur \(Fmt.euro(price))")
                } else {
                    Text("\(Fmt.euro(goal.saved)) · prix inconnu")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
            }
            .font(.system(size: 13))
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
                Circle().stroke(Theme.panel2, lineWidth: 14)
                Circle().trim(from: 0, to: 0.62)
                    .stroke(AngularGradient(colors: [Theme.violet, Theme.accent], center: .center),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 110, height: 110)
            .padding(.bottom, 8)

            Text("Aucun objectif pour l'instant")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            Text("Colle le lien d'un produit idealo et commence à épargner pour l'avoir.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)

            Button("Créer mon premier objectif", action: action)
                .buttonStyle(PillButtonStyle(fill: Theme.accent, foreground: Theme.onAccent))
                .padding(.top, 10)
        }
        .padding(32)
    }
}
