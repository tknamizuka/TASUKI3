import SwiftUI

/// 今週の振り返り。`MyProfileView` の Activity と同一の `RunActivityStore` で集計する。
struct WeeklyReflectionView: View {
    @ObservedObject private var activityStore = RunActivityStore.shared

    private var runCount: Int { activityStore.weeklyRunCount() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                activitySection
                messageCard
            }
            .padding(16)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("今週の振り返り")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            activityStore.refreshFromRemote()
        }
    }

    /// `MyProfileView` の Activity と同じメソッドで今週・今月・週次チャートを表示する。
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity")
                .font(.system(size: 14, weight: .bold))
                .tracking(1.1)
                .foregroundColor(Color.tasukiPrimary)

            HStack(spacing: 14) {
                graphStatActivity(title: "今週距離", value: String(format: "%.1f km", activityStore.weeklyDistanceKm()))
                graphStatActivity(title: "今週回数", value: "\(activityStore.weeklyRunCount()) 回")
                graphStatActivity(title: "今月距離", value: String(format: "%.1f km", activityStore.monthlyDistanceKm()))
            }

            TasukiWeeklyActivityLineChart(
                points: activityStore.weeklyActivityChartPoints(),
                runActivities: activityStore.activities
            )
                .frame(height: 190)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tasukiCard()
    }

    private func graphStatActivity(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.tasukiMutedText)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ひとこと")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Color.tasukiMutedText)
            Text(weeklyMessage)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.tasukiPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tasukiCard()
    }

    private var weeklyMessage: String {
        if runCount == 0 {
            return "今週はまだ記録がありません。また走り出したくなったら、ホームの伴走カードから短く始められます。"
        }
        if runCount >= 4 {
            return "週に\(runCount)回も記録できています。このリズムを自分に合う範囲で保てば十分です。"
        }
        return "今週は\(runCount)回だけでも積み上がっています。次の一歩は「昨日より責めないこと」で大丈夫です。"
    }
}

#Preview {
    NavigationStack {
        WeeklyReflectionView()
    }
}
