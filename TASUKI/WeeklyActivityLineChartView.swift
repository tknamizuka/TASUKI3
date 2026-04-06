import SwiftUI

/// Me の Activity と Run 記録で同一の週次距離チャート（`WeeklyActivityChartPoint` を表示）。
struct TasukiWeeklyActivityLineChart: View {
    let points: [WeeklyActivityChartPoint]
    @State private var selectedPointID: String?

    private var maxY: Double {
        max(points.map(\.distanceKm).max() ?? 0, 1)
    }

    private var selectedPoint: WeeklyActivityChartPoint? {
        guard let selectedPointID else { return nil }
        return points.first(where: { $0.id == selectedPointID })
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let leftPadding: CGFloat = 30
            let bottomPadding: CGFloat = 28
            let topPadding: CGFloat = 10
            let plotWidth = max(1, width - leftPadding)
            let plotHeight = max(1, height - bottomPadding - topPadding)
            let count = max(points.count, 2)

            ZStack {
                ForEach(0..<4, id: \.self) { row in
                    let ratio = CGFloat(row) / 3
                    let y = topPadding + plotHeight * ratio
                    Path { path in
                        path.move(to: CGPoint(x: leftPadding, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                Path { path in
                    guard !points.isEmpty else { return }
                    for (index, point) in points.enumerated() {
                        let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                        let normalized = CGFloat(point.distanceKm / maxY)
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
                            Color.tasukiBrandYellow.opacity(0.42),
                            Color.tasukiBrandYellow.opacity(0.14),
                            Color.tasukiBrandYellow.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                        let normalized = CGFloat(point.distanceKm / maxY)
                        let y = topPadding + (1 - normalized) * plotHeight
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.tasukiBrandYellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                    let normalized = CGFloat(point.distanceKm / maxY)
                    let y = topPadding + (1 - normalized) * plotHeight

                    Circle()
                        .fill(selectedPointID == point.id ? Color.tasukiAccent : Color.tasukiBrandYellow)
                        .overlay(
                            Circle()
                                .stroke(Color.tasukiOnBrandYellow.opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: selectedPointID == point.id ? 10 : 7, height: selectedPointID == point.id ? 10 : 7)
                        .position(x: x, y: y)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedPointID = selectedPointID == point.id ? nil : point.id
                            }
                        }

                    Text(point.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedPointID == point.id ? Color.tasukiAccent : .black)
                        .position(x: x, y: height - 12)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedPointID = selectedPointID == point.id ? nil : point.id
                            }
                        }
                }

                if let selectedPoint,
                   let selectedIndex = points.firstIndex(where: { $0.id == selectedPoint.id }) {
                    let x = leftPadding + plotWidth * CGFloat(selectedIndex) / CGFloat(count - 1)
                    let normalized = CGFloat(selectedPoint.distanceKm / maxY)
                    let y = topPadding + (1 - normalized) * plotHeight
                    let bubbleX = min(max(x, 78), width - 78)
                    let bubbleY = max(18, y - 34)

                    tooltipView(point: selectedPoint)
                        .position(x: bubbleX, y: bubbleY)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%.0fkm", maxY))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                    Spacer()
                    Text("0km")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                }
                .padding(.top, topPadding - 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func tooltipView(point: WeeklyActivityChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.tooltipDateFormatter.string(from: point.weekAnchor))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.tasukiMutedText)
            Text(String(format: "%.1f km", point.distanceKm))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tasukiDarkCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.tasukiMutedText.opacity(0.25), lineWidth: 1)
        )
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(E) HH:mm"
        return formatter
    }()
}
