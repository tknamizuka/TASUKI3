import SwiftUI

/// 距離だけでなく「続いた・休んだ・戻ってきた」を肯定する週次サマリー。
struct WeeklyReflectionView: View {
    @ObservedObject private var activityStore = RunActivityStore.shared

    private var weekInterval: DateInterval? {
        Calendar.tasukiActivityWeekCalendar.dateInterval(of: .weekOfYear, for: Date())
    }

    /// Me / Run 記録の Activity と同じ `RunActivityStore` 集計。
    private var runsThisWeek: [RunActivity] {
        activityStore.activitiesInCurrentWeek()
    }

    private var runCount: Int { activityStore.weeklyRunCount() }
    private var weekKm: Double { activityStore.weeklyDistanceKm() }

    private var restDays: Int {
        guard let weekInterval else { return 0 }
        let cal = Calendar.tasukiActivityWeekCalendar
        var count = 0
        var day = weekInterval.start
        while day < weekInterval.end {
            let hasRun = runsThisWeek.contains { cal.isDate($0.startedAt, inSameDayAs: day) }
            if !hasRun { count += 1 }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statsGrid
                messageCard
            }
            .padding(16)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("今週の振り返り")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            activityStore.refreshFromRemote()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THIS WEEK")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.5)
                .foregroundColor(Color.tasukiMutedText)
            Text("走れた日も、休んだ日も、どちらも継続の一部です")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tasukiCard()
    }

    private var statsGrid: some View {
        VStack(spacing: 10) {
            statRow(title: "記録した回数", value: "\(runCount) 回", hint: "ゼロでも責めなくてOK")
            statRow(title: "合計距離", value: String(format: "%.1f km", weekKm), hint: "少しでも前に進めていれば十分")
            statRow(title: "走らなかった日（概算）", value: "\(restDays) 日", hint: "休養も次の走りの準備です")
        }
    }

    private func statRow(title: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.tasukiMutedText)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
            Text(hint)
                .font(.footnote)
                .foregroundColor(Color.tasukiMutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tasukiCard()
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
