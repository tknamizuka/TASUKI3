import SwiftUI

/// Me の Activity と Run 記録で同一の週次距離チャート（`WeeklyActivityChartPoint` を表示）。
struct TasukiWeeklyActivityLineChart: View {
    let points: [WeeklyActivityChartPoint]

    private var maxY: Double {
        max(points.map(\.distanceKm).max() ?? 0, 1)
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
                        .fill(Color.tasukiBrandYellow)
                        .overlay(
                            Circle()
                                .stroke(Color.tasukiOnBrandYellow.opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: 7, height: 7)
                        .position(x: x, y: y)

                    Text(point.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                        .position(x: x, y: height - 12)
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
}
