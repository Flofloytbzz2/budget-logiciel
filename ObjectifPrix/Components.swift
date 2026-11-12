import SwiftUI
import Charts

// MARK: - Anneau de progression

struct RingView: View {
    let progress: Double   // 0...1
    @State private var shown: Double = 0

    private var reached: Bool { progress >= 0.9995 }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.panel2, lineWidth: 18)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(shown, 0), 1)))
                .stroke(
                    AngularGradient(
                        colors: reached ? [Theme.gold, Theme.accent, Theme.gold] : [Theme.violet, Theme.accent],
                        center: .center),
                    style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (reached ? Theme.gold : Theme.accent).opacity(0.35), radius: 10)
            VStack(spacing: 2) {
                Text("\(Int(progress * 100)) %")
                    .font(AppFont.f(38, .heavy))
                    .foregroundStyle(reached ? Theme.gold : Theme.text)
                Text(L.t("ring.of_goal"))
                    .font(AppFont.f(13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .onAppear {
            withAnimation(Prefs.animations ? Animation.easeOut(duration: 1.0) : nil) { shown = progress }
        }
        .onChange(of: progress) { newValue in
            withAnimation(Prefs.animations ? Animation.easeOut(duration: 0.8) : nil) { shown = newValue }
        }
    }
}

// MARK: - Tuile de chiffre

struct StatTile: View {
    let label: String
    let value: String
    let sub: String
    var subColor: Color = Theme.muted

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(AppFont.f(10, .bold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(AppFont.f(20, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub)
                .font(AppFont.f(11))
                .foregroundStyle(subColor)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel2))
    }
}

// MARK: - Confettis

struct ConfettiView: View {
    private struct Piece {
        let x: CGFloat
        let fall: CGFloat
        let color: Int
        let size: CGFloat
        let rotation: Double
    }

    private static let colors: [Color] = [Theme.accent, Theme.violet, Theme.gold, Theme.bad, .white]
    private let pieces: [Piece] = (0..<60).map { _ in
        Piece(x: CGFloat.random(in: -1...1),
              fall: CGFloat.random(in: 0.35...1),
              color: Int.random(in: 0..<5),
              size: CGFloat.random(in: 6...11),
              rotation: Double.random(in: 0...360))
    }
    @State private var go = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<pieces.count, id: \.self) { i in
                    let p = pieces[i]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.colors[p.color])
                        .frame(width: p.size, height: p.size * 0.6)
                        .rotationEffect(.degrees(go ? p.rotation + 540 : p.rotation))
                        .offset(x: go ? p.x * geo.size.width / 2 : 0,
                                y: go ? geo.size.height * p.fall : -30)
                        .opacity(go ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(Prefs.animations ? Animation.easeOut(duration: 2.4) : nil) { go = true }
        }
    }
}

// MARK: - Graphique du prix

struct PriceChart: View {
    let goal: Goal
    @State private var selected: PricePoint?

    var body: some View {
        let points = goal.sortedHistory
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(L.t("chart.title"))
                Spacer()
                if let low = points.map(\.price).min(), let high = points.map(\.price).max() {
                    Text(L.f("chart.range", goal.money(low), goal.money(high)))
                        .font(AppFont.f(11))
                        .foregroundStyle(Theme.muted)
                }
            }
            if points.isEmpty {
                VStack(spacing: 6) {
                    Text(L.t("chart.empty_title"))
                        .font(AppFont.f(15, .semibold))
                        .foregroundStyle(Theme.text)
                    Text(L.t("chart.empty_sub"))
                        .font(AppFont.f(13))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                chart(points)
            }
        }
        .card()
    }

    @ViewBuilder
    private func chart(_ points: [PricePoint]) -> some View {
        let prices = points.map(\.price)
        let lo = prices.min() ?? 0
        let hi = prices.max() ?? 1
        let pad = (hi - lo) > 0 ? (hi - lo) * 0.25 : max(hi * 0.05, 1)
        let floorValue = lo - pad
        let ceilValue = hi + pad
        let showSaved = goal.saved > floorValue && goal.saved < ceilValue

        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date),
                         yStart: .value("Base", floorValue),
                         yEnd: .value("Prix", p.price))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", p.date), y: .value("Prix", p.price))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", p.date), y: .value("Prix", p.price))
                    .foregroundStyle(Theme.accent)
                    .opacity(points.count > 30 ? 0 : 1)
            }
            if showSaved {
                RuleMark(y: .value("Savings", goal.saved))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Theme.gold)
                    .annotation(position: .top, alignment: .trailing) {
                        Text(L.t("chart.my_savings"))
                            .font(AppFont.f(10))
                            .foregroundStyle(Theme.gold)
                    }
            }
            if let s = selected {
                RuleMark(x: .value("Date", s.date))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                    .annotation(position: .top, spacing: 4) {
                        Text(Fmt.shortDate(s.date) + "  " + goal.money(s.price))
                            .font(AppFont.f(12, .bold))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel2))
                    }
                PointMark(x: .value("Date", s.date), y: .value("Prix", s.price))
                    .symbolSize(120)
                    .foregroundStyle(.white)
            }
        }
        .chartYScale(domain: floorValue...ceilValue)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                AxisValueLabel().foregroundStyle(Theme.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month().locale(Locale(identifier: L.localeID)))
                    .foregroundStyle(Theme.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - geo[proxy.plotAreaFrame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selected = points.min {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }
                                }
                            }
                            .onEnded { _ in selected = nil })
            }
        }
        .frame(height: 210)
    }
}
