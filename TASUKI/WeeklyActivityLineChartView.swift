import SwiftUI

/// Me の Activity と Run 記録で使うトレンドチャート（`WeeklyActivityChartPoint` を表示）。
struct TasukiWeeklyActivityLineChart: View {
    let points: [WeeklyActivityChartPoint]
    /// `nil` のときはブランドイエロー（Me 画面など）。指定時は他ユーザー向けの固定アクセント色。
    var lineColor: Color? = nil
    /// 指定時、選択中ポイントの週について日ごとの走行距離をツールチップに表示する。
    var runActivities: [RunActivity]? = nil
    /// 縦軸ラベル（未指定時は km 表示）。
    var yAxisValueFormatter: ((Double) -> String)? = nil
    /// 最古週の横軸ラベルを右へ寄せ、0km ラベルと重ならないようにする。
    var insetOldestWeekXAxisLabel: Bool = true
    /// true のとき日次ポイントで描画し、横軸ラベルは週始まりのみ表示。
    var usesDailyPoints: Bool = false
    /// 縦軸目盛りの刻み幅（未指定時: 距離 km は 5、それ以外はデータに応じて自動）。
    var yAxisStep: Double? = nil
    /// 縦軸ラベルの最大表示数（目盛り線は刻み幅どおり、ラベルのみ間引く）。
    var yAxisMaxLabels: Int? = nil
    @State private var selectedPointID: String?

    private var yAxisScale: TasukiChartYAxisScale {
        let dataMax = points.map(\.distanceKm).max() ?? 0
        if let yAxisStep, yAxisStep > 0 {
            return .fixed(dataMax: dataMax, step: yAxisStep)
        }
        if yAxisValueFormatter == nil {
            return .fixed(dataMax: dataMax, step: 5)
        }
        return .nice(dataMax: dataMax, targetTickCount: 6)
    }

    private var chartMaxY: Double {
        yAxisScale.axisMax
    }

    private var accent: Color {
        lineColor ?? Color.tasukiBrandYellow
    }
    
    private var lineStrokeColor: Color {
        accent.opacity(0.98)
    }
    
    private var pointFillColor: Color {
        accent.opacity(0.95)
    }

    private var lineWidth: CGFloat {
        usesDailyPoints ? 2.2 : 3.2
    }

    private var pointDiameter: CGFloat {
        usesDailyPoints ? 5 : 7
    }

    private var selectedPointDiameter: CGFloat {
        usesDailyPoints ? 7 : 10
    }
    
    private var shouldThinXAxisLabels: Bool {
        !usesDailyPoints && points.count >= 7
    }

    private func shouldShowXAxisLabel(at index: Int, point: WeeklyActivityChartPoint) -> Bool {
        if usesDailyPoints {
            return !point.label.isEmpty
        }
        guard shouldThinXAxisLabels else { return true }
        if index == 0 || index == points.count - 1 { return true }
        return index.isMultiple(of: 2)
    }

    private func formatYAxisValue(_ value: Double) -> String {
        if let yAxisValueFormatter {
            return yAxisValueFormatter(value)
        }
        return String(format: "%.0fkm", value)
    }

    private func shouldShowYAxisLabel(tickIndex: Int, tickCount: Int, tickValue: Double) -> Bool {
        if let yAxisValueFormatter, yAxisValueFormatter(tickValue) == "--" {
            return false
        }
        guard let yAxisMaxLabels, yAxisMaxLabels >= 2, tickCount > yAxisMaxLabels else {
            return true
        }
        let labelStride = max(1, Int(ceil(Double(tickCount - 1) / Double(yAxisMaxLabels - 1))))
        return tickIndex.isMultiple(of: labelStride) || tickIndex == tickCount - 1
    }

    private var selectedPoint: WeeklyActivityChartPoint? {
        guard let selectedPointID else { return nil }
        return points.first(where: { $0.id == selectedPointID })
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let yAxisWidth: CGFloat = 30
            let leftPadding: CGFloat = yAxisWidth + 6
            let bottomPadding: CGFloat = 28
            let topPadding: CGFloat = 10
            let plotWidth = max(1, width - leftPadding)
            let plotHeight = max(1, height - bottomPadding - topPadding)
            let count = max(points.count, 2)

            ZStack {
                let yTicks = yAxisScale.ticks
                ForEach(Array(yTicks.enumerated()), id: \.offset) { tickIndex, tickValue in
                    let ratio = chartMaxY > 0 ? CGFloat(tickValue / chartMaxY) : 0
                    let y = topPadding + plotHeight * (1 - ratio)

                    Path { path in
                        path.move(to: CGPoint(x: leftPadding, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.gray.opacity(tickIndex == 0 ? 0.28 : 0.2), style: StrokeStyle(lineWidth: 1, dash: tickIndex == 0 ? [] : [4, 3]))
                    .allowsHitTesting(false)

                    if shouldShowYAxisLabel(tickIndex: tickIndex, tickCount: yTicks.count, tickValue: tickValue) {
                        Text(formatYAxisValue(tickValue))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color.tasukiMutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(width: yAxisWidth, alignment: .leading)
                            .position(x: yAxisWidth / 2, y: y)
                            .allowsHitTesting(false)
                    }
                }

                Path { path in
                    guard !points.isEmpty else { return }
                    for (index, point) in points.enumerated() {
                        let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                        let normalized = chartMaxY > 0 ? CGFloat(point.distanceKm / chartMaxY) : 0
                        let y = topPadding + (1 - normalized) * plotHeight
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    let lastIndex = points.count - 1
                    let lastX = leftPadding + plotWidth * CGFloat(lastIndex) / CGFloat(count - 1)
                    let firstX = leftPadding
                    let bottomY = topPadding + plotHeight
                    path.addLine(to: CGPoint(x: lastX, y: bottomY))
                    path.addLine(to: CGPoint(x: firstX, y: bottomY))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.78),
                            accent.opacity(0.52),
                            accent.opacity(0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)

                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                        let normalized = chartMaxY > 0 ? CGFloat(point.distanceKm / chartMaxY) : 0
                        let y = topPadding + (1 - normalized) * plotHeight
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineStrokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                    let normalized = chartMaxY > 0 ? CGFloat(point.distanceKm / chartMaxY) : 0
                    let y = topPadding + (1 - normalized) * plotHeight
                    let showPoint = !usesDailyPoints || point.distanceKm > 0.001

                    if showPoint {
                        Circle()
                            .fill(selectedPointID == point.id ? Color.tasukiAccent : pointFillColor)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(lineColor == nil ? 0.35 : 0.5), lineWidth: 1)
                            )
                            .frame(
                                width: selectedPointID == point.id ? selectedPointDiameter : pointDiameter,
                                height: selectedPointID == point.id ? selectedPointDiameter : pointDiameter
                            )
                            .position(x: x, y: y)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedPointID = selectedPointID == point.id ? nil : point.id
                                }
                            }
                    }

                    if shouldShowXAxisLabel(at: index, point: point) {
                        let labelX: CGFloat = {
                            guard insetOldestWeekXAxisLabel, index == 0 else { return x }
                            return min(x + 14, leftPadding + plotWidth - 8)
                        }()
                        Text(point.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(selectedPointID == point.id ? Color.tasukiAccent : .black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .position(x: labelX, y: height - 12)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedPointID = selectedPointID == point.id ? nil : point.id
                                }
                            }
                    }
                }

                if let selectedPoint,
                   let selectedIndex = points.firstIndex(where: { $0.id == selectedPoint.id }) {
                    let x = leftPadding + plotWidth * CGFloat(selectedIndex) / CGFloat(count - 1)
                    let normalized = chartMaxY > 0 ? CGFloat(selectedPoint.distanceKm / chartMaxY) : 0
                    let y = topPadding + (1 - normalized) * plotHeight
                    let bubbleX = min(max(x, 78), width - 78)
                    let bubbleY = max(18, y - 34)

                    tooltipView(point: selectedPoint)
                        .position(x: bubbleX, y: bubbleY)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private func tooltipView(point: WeeklyActivityChartPoint) -> some View {
        let dailyLines = Self.dailyDistanceLines(for: point, activities: runActivities)
        VStack(alignment: .leading, spacing: 4) {
            if usesDailyPoints {
                Text(Self.tooltipDayFormatter.string(from: point.weekAnchor))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
                Text(tooltipValueLabel(for: point))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                if let runActivities, !runActivities.isEmpty {
                    let dayActs = runActivities.filter {
                        Calendar.tasukiActivityWeekCalendar.isDate($0.startedAt, inSameDayAs: point.weekAnchor)
                    }
                    if !dayActs.isEmpty {
                        Text("\(dayActs.count) 件の記録")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.92))
                    }
                }
            } else {
                Text(Self.tooltipWeekRangeLabel(for: point.weekAnchor))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
                Text(String(format: "週合計 %.1f km", point.distanceKm))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                if !dailyLines.isEmpty {
                    ForEach(Array(dailyLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.92))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tasukiDarkCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.tasukiMutedText.opacity(0.25), lineWidth: 1)
        )
    }

    private static let tooltipDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f
    }()

    private static func tooltipWeekRangeLabel(for weekStart: Date) -> String {
        let cal = Calendar.tasukiActivityWeekCalendar
        guard let interval = cal.dateInterval(of: .weekOfYear, for: weekStart) else {
            return tooltipDayFormatter.string(from: weekStart)
        }
        let lastInclusive = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        let lastDay = cal.startOfDay(for: lastInclusive)
        let firstDay = cal.startOfDay(for: interval.start)
        return "\(tooltipDayFormatter.string(from: firstDay))〜\(tooltipDayFormatter.string(from: lastDay))"
    }

    /// その週の暦日ごとの合計距離（記録なしは 0.0 km）。
    private static func dailyDistanceLines(for point: WeeklyActivityChartPoint, activities: [RunActivity]?) -> [String] {
        guard let activities else { return [] }
        let cal = Calendar.tasukiActivityWeekCalendar
        guard let interval = cal.dateInterval(of: .weekOfYear, for: point.weekAnchor) else { return [] }
        var byDay: [Date: Double] = [:]
        for a in activities where interval.contains(a.startedAt) {
            let day = cal.startOfDay(for: a.startedAt)
            byDay[day, default: 0] += a.distanceKm
        }
        var lines: [String] = []
        var day = cal.startOfDay(for: interval.start)
        while day < interval.end {
            let km = byDay[day] ?? 0
            lines.append("\(tooltipDayFormatter.string(from: day))　\(String(format: "%.1f km", km))")
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = cal.startOfDay(for: next)
        }
        return lines
    }

    private func tooltipValueLabel(for point: WeeklyActivityChartPoint) -> String {
        if let yAxisValueFormatter {
            return yAxisValueFormatter(point.distanceKm)
        }
        return String(format: "%.1f km", point.distanceKm)
    }
}

/// 週次トレンド＋今月サマリー（Activity グラフと同じ高さ）。
struct TasukiRunningStatTrendChartCard: View {
    let title: String
    let summaryValue: String
    let points: [WeeklyActivityChartPoint]
    var lineColor: Color? = nil
    var yAxisValueFormatter: ((Double) -> String)? = nil
    var yAxisStep: Double? = nil
    var yAxisMaxLabels: Int? = nil
    var chartHeight: CGFloat = 190
    var usesDailyPoints: Bool = true

    private var accent: Color {
        lineColor ?? Color.tasukiPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(Color.tasukiMutedText)
                Spacer(minLength: 8)
                Text(summaryValue)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            TasukiWeeklyActivityLineChart(
                points: points,
                lineColor: accent,
                yAxisValueFormatter: yAxisValueFormatter,
                usesDailyPoints: usesDailyPoints,
                yAxisStep: yAxisStep,
                yAxisMaxLabels: yAxisMaxLabels
            )
            .frame(height: chartHeight)
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum TasukiChartPaceFormat {
    static func yAxisLabel(secondsPerKm: Double) -> String {
        guard secondsPerKm > 0 else { return "--" }
        let m = Int(secondsPerKm) / 60
        let s = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// 縦軸の固定刻み（例: 5km ごと）と上限値。
struct TasukiChartYAxisScale {
    let step: Double
    let axisMax: Double

    var ticks: [Double] {
        guard step > 0, axisMax > 0 else { return [0] }
        var values: [Double] = []
        var v = 0.0
        while v <= axisMax + step * 0.001 {
            values.append(v)
            v += step
        }
        return values
    }

    static func fixed(dataMax: Double, step: Double) -> TasukiChartYAxisScale {
        let safeStep = max(step, 0.001)
        let clampedMax = max(dataMax, 0)
        guard clampedMax > 0 else {
            return TasukiChartYAxisScale(step: safeStep, axisMax: safeStep)
        }

        var top = ceil(clampedMax / safeStep) * safeStep
        // データが現在の上限目盛りに達したら、刻み幅を保ったまま次の段階へ拡張（例: 15km → 20km）。
        if clampedMax >= top - safeStep * 0.001 {
            top += safeStep
        }
        return TasukiChartYAxisScale(step: safeStep, axisMax: top)
    }

    static func nice(dataMax: Double, targetTickCount: Int = 6) -> TasukiChartYAxisScale {
        let safeMax = max(dataMax, 1)
        let roughStep = safeMax / Double(max(targetTickCount - 1, 1))
        let magnitude = pow(10, floor(log10(max(roughStep, 1e-9))))
        let normalized = roughStep / magnitude
        let niceNormalized: Double
        if normalized <= 1 { niceNormalized = 1 }
        else if normalized <= 2 { niceNormalized = 2 }
        else if normalized <= 5 { niceNormalized = 5 }
        else { niceNormalized = 10 }
        let step = niceNormalized * magnitude
        return fixed(dataMax: dataMax, step: step)
    }
}
