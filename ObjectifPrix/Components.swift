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
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(reached ? Theme.gold : Theme.text)
                Text("de l'objectif")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { shown = progress }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.easeOut(duration: 0.8)) { shown = newValue }
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
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 11))
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
            withAnimation(.easeOut(duration: 2.4)) { go = true }
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
                SectionLabel("Évolution du prix")
                Spacer()
                if let low = points.map(\.price).min(), let high = points.map(\.price).max() {
                    Text("bas \(Fmt.euro(low)) · haut \(Fmt.euro(high))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
            }
            if points.isEmpty {
                VStack(spacing: 6) {
                    Text("Pas encore de relevé de prix")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Le graphique se construit au fil des jours.")
                        .font(.system(size: 13))
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
                RuleMark(y: .value("Épargne", goal.saved))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Theme.gold)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("mon épargne")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.gold)
                    }
            }
            if let s = selected {
                RuleMark(x: .value("Date", s.date))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(Fmt.shortDate.string(from: s.date))  \(Fmt.euro(s.price))")
                            .font(.system(size: 12, weight: .bold))
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
                AxisValueLabel(format: .dateTime.day().month())
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
