import SwiftUI

// MARK: - Calculs : conseil d'achat, statistiques, jalons

enum BuyVerdict {
    case unknown, stable, lowest, good, average, high
}

struct BuyAdvice {
    var verdict: BuyVerdict
    var position: Double    // 0 = au plus bas, 1 = au plus haut
    var low: Double
    var high: Double
}

struct GoalStats {
    var savedThisMonth: Double
    var averagePerMonth: Double
    var depositCount: Int
    var streakWeeks: Int
    var firstDate: Date?
}

extension Goal {
    static let milestones: [Double] = [0.25, 0.5, 0.75, 1.0]

    func buyAdvice() -> BuyAdvice {
        let prices: [Double] = sortedHistory.map { $0.price }
        guard let current = price, prices.count >= 3,
              let lo = prices.min(), let hi = prices.max() else {
            return BuyAdvice(verdict: .unknown, position: 0.5, low: price ?? 0, high: price ?? 0)
        }
        if hi - lo < 0.005 {
            return BuyAdvice(verdict: .stable, position: 0.5, low: lo, high: hi)
        }
        let position: Double = min(max((current - lo) / (hi - lo), 0), 1)
        let verdict: BuyVerdict
        if current <= lo + 0.005 {
            verdict = .lowest
        } else if position < 0.25 {
            verdict = .good
        } else if position < 0.65 {
            verdict = .average
        } else {
            verdict = .high
        }
        return BuyAdvice(verdict: verdict, position: position, low: lo, high: hi)
    }

    func stats(now: Date = Date()) -> GoalStats {
        let cal: Calendar = Calendar.current

        var thisMonth: Double = 0
        for entry in log where cal.isDate(entry.date, equalTo: now, toGranularity: .month) {
            thisMonth += entry.amount
        }

        let deposits: Int = log.filter { $0.amount > 0 }.count

        let first: Date? = log.map { $0.date }.min()
        var average: Double = 0
        if let start = first {
            let days: Int = cal.dateComponents([.day], from: start, to: now).day ?? 0
            let months: Double = max(Double(days) / 30.44, 1)
            average = saved / months
        }

        // Série : semaines consécutives avec au moins un versement
        var weeks = Set<Date>()
        for entry in log where entry.amount > 0 {
            if let start = cal.dateInterval(of: .weekOfYear, for: entry.date)?.start {
                weeks.insert(start)
            }
        }
        var streak: Int = 0
        if var cursor = cal.dateInterval(of: .weekOfYear, for: now)?.start {
            if !weeks.contains(cursor), let previous = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) {
                cursor = previous
            }
            while weeks.contains(cursor) {
                streak += 1
                guard let previous = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
                cursor = previous
            }
        }

        return GoalStats(savedThisMonth: thisMonth, averagePerMonth: average,
                         depositCount: deposits, streakWeeks: streak, firstDate: first)
    }
}

// MARK: - Carte « Bon moment pour acheter ? »

struct BuyAdviceCard: View {
    let goal: Goal

    var body: some View {
        let advice: BuyAdvice = goal.buyAdvice()
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(L.t("advice.title"))
            if advice.verdict == .unknown {
                Text(L.t("advice.need_data"))
                    .font(AppFont.f(14))
                    .foregroundStyle(Theme.muted)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: icon(advice.verdict))
                        .font(AppFont.f(22, .bold))
                        .foregroundStyle(color(advice.verdict))
                    Text(L.t(textKey(advice.verdict)))
                        .font(AppFont.f(16, .bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if advice.verdict != .stable {
                    gauge(advice)
                }
            }
        }
        .card()
    }

    private func gauge(_ advice: BuyAdvice) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accent, Theme.gold, Theme.bad],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                    Circle()
                        .fill(Theme.text)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                        .offset(x: max(0, min(geo.size.width - 18, geo.size.width * advice.position - 9)))
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            HStack {
                Text(L.t("advice.min") + " " + goal.money(advice.low))
                Spacer()
                Text(L.t("advice.max") + " " + goal.money(advice.high))
            }
            .font(AppFont.f(12))
            .foregroundStyle(Theme.muted)
        }
    }

    private func textKey(_ v: BuyVerdict) -> String {
        switch v {
        case .lowest: return "advice.lowest"
        case .good: return "advice.good"
        case .average: return "advice.average"
        case .high: return "advice.high"
        case .stable: return "advice.stable"
        case .unknown: return "advice.need_data"
        }
    }

    private func icon(_ v: BuyVerdict) -> String {
        switch v {
        case .lowest, .good: return "arrow.down.circle.fill"
        case .high: return "arrow.up.circle.fill"
        default: return "equal.circle.fill"
        }
    }

    private func color(_ v: BuyVerdict) -> Color {
        switch v {
        case .lowest, .good: return Theme.accent
        case .average: return Theme.gold
        case .high: return Theme.bad
        default: return Theme.muted
        }
    }
}

// MARK: - Petit badge pour la liste

struct BuyBadge: View {
    let goal: Goal

    var body: some View {
        let verdict: BuyVerdict = goal.buyAdvice().verdict
        if verdict == .lowest || verdict == .good || verdict == .high {
            let isGood: Bool = verdict != .high
            let key: String = verdict == .lowest ? "advice.badge.great" : (verdict == .good ? "advice.badge.good" : "advice.badge.high")
            Text(L.t(key))
                .font(AppFont.f(11, .bold))
                .foregroundStyle(isGood ? Theme.onAccent : Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isGood ? Theme.accent : Theme.bad))
        }
    }
}

// MARK: - Carte « Statistiques » + jalons

struct StatsCard: View {
    let goal: Goal

    var body: some View {
        let stats: GoalStats = goal.stats()
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(L.t("stats.title"))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatTile(label: L.t("stats.this_month"),
                         value: goal.money(stats.savedThisMonth),
                         sub: Fmt.monthYear(Date()).capitalized)
                StatTile(label: L.t("stats.avg_month"),
                         value: goal.money(stats.averagePerMonth),
                         sub: stats.firstDate.map { L.f("stats.since", Fmt.shortDate($0)) } ?? "—")
                StatTile(label: L.t("stats.deposits"),
                         value: String(stats.depositCount),
                         sub: L.t("stats.deposits_sub"))
                StatTile(label: L.t("stats.streak"),
                         value: L.f("stats.weeks", String(stats.streakWeeks)),
                         sub: L.t("stats.streak_sub"))
            }

            SectionLabel(L.t("stats.milestones"))
            HStack(spacing: 10) {
                ForEach(Goal.milestones, id: \.self) { step in
                    milestone(step)
                }
            }
        }
        .card()
    }

    private func milestone(_ step: Double) -> some View {
        let reached: Bool = goal.progress >= step - 0.0005
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(reached ? Theme.accent : Theme.panel2)
                    .frame(width: 40, height: 40)
                Image(systemName: reached ? "checkmark" : "flag.fill")
                    .font(AppFont.f(15, .bold))
                    .foregroundStyle(reached ? Theme.onAccent : Theme.muted)
            }
            Text(String(Int(step * 100)) + " %")
                .font(AppFont.f(12, .semibold))
                .foregroundStyle(reached ? Theme.text : Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Photo du produit

struct ProductImage: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let text = urlString, let url = URL(string: text) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(size * 0.06)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Theme.panel2
            Image(systemName: "photo")
                .foregroundStyle(Theme.muted)
        }
    }
}
