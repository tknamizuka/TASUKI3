import SwiftUI

/// 他ユーザーを表示するときのプロフィール本文（`MyProfileView` と同じセクション・項目構成）。
/// `remoteActivities` が空のときは Firestore プロフィール項目（`avgPace` / `monthlyDistance` 等）をサマリーに表示。
struct UserPublicProfileScrollContent: View {
    let user: User
    let activityChartPoints: [WeeklyActivityChartPoint]
    let remoteActivities: [RunActivity]
    let isLoadingRemoteActivities: Bool
    let heroAccessory: HeroAccessory

    enum HeroAccessory {
        /// パートナー画面: オンライン表示
        case partnerOnline
        /// Find など: マッチ度バッジ
        case findMatchRate(Int)
        case none
    }

    init(
        user: User,
        activityChartPoints: [WeeklyActivityChartPoint] = [],
        remoteActivities: [RunActivity] = [],
        isLoadingRemoteActivities: Bool = false,
        heroAccessory: HeroAccessory
    ) {
        self.user = user
        self.activityChartPoints = activityChartPoints
        self.remoteActivities = remoteActivities
        self.isLoadingRemoteActivities = isLoadingRemoteActivities
        self.heroAccessory = heroAccessory
    }

    private var activityStats: RunActivityCollectionStats {
        RunActivityCollectionStats(activities: remoteActivities)
    }

    private var hasRemoteActivityStats: Bool {
        !remoteActivities.isEmpty
    }

    private var weeklyDistanceStatDisplay: String {
        if hasRemoteActivityStats {
            return String(format: "%.1f km", activityStats.weeklyDistanceKm())
        }
        guard let last = activityChartPoints.last else { return "—" }
        return String(format: "%.1f km", last.distanceKm)
    }

    private var weeklyRunCountStatDisplay: String {
        if hasRemoteActivityStats {
            return "\(activityStats.weeklyRunCount()) 回"
        }
        guard !activityChartPoints.isEmpty else { return "—" }
        var h = Hasher()
        h.combine(user.name)
        h.combine(user.monthlyGpsActivityCount)
        let n = (abs(h.finalize()) % 5) + 2
        return "\(n) 回"
    }

    private var monthlyDistanceStatDisplay: String {
        if hasRemoteActivityStats {
            return String(format: "%.1f km", activityStats.monthlyDistanceKm())
        }
        return String(format: "%.1f km", user.monthlyDistance)
    }

    private var paceSummaryDisplay: String {
        if hasRemoteActivityStats {
            return activityStats.monthlyAveragePaceDisplayLabel()
        }
        let trimmed = user.avgPace.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "--:--/km" : trimmed
    }

    private var monthlyRunCountSummaryDisplay: String {
        if hasRemoteActivityStats {
            return "\(activityStats.monthlyRunCount()) 回"
        }
        if let count = user.monthlyGpsActivityCount, count > 0 {
            return "\(count) 回"
        }
        return "0 回"
    }

    private var caloriesSummaryDisplay: String {
        if hasRemoteActivityStats {
            return activityStats.monthlyTotalCaloriesDisplayLabel()
        }
        return "-- kcal"
    }

    private var resolvedWeeklyDistanceChartPoints: [WeeklyActivityChartPoint] {
        if hasRemoteActivityStats {
            return activityStats.dailyActivityChartPoints()
        }
        return activityChartPoints
    }

    private var areaDisplay: String {
        let p = user.prefecture.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = user.area.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty && !a.isEmpty { return "\(p), \(a)" }
        if !a.isEmpty { return a }
        if !p.isEmpty { return p }
        return "—"
    }

    private var runningSpotTags: [String] {
        user.spotName.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            heroSection
                .padding(.bottom, 28)
            activitySection
                .padding(.bottom, 28)
            statsSection
                .padding(.bottom, 28)
            profileSection
                .padding(.bottom, 28)
            if !user.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aboutSection
                    .padding(.bottom, 28)
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            UserProfileAvatarView(user: user, size: 140)

            HStack(spacing: 8) {
                Text(user.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
                if let tier = PointBadgeHelper.tier(forTotalPoints: user.totalPoints) {
                    HStack(spacing: 4) {
                        Image(systemName: tier.iconName)
                        Text(tier.displayName)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                }
            }

            Text(user.rank)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)

            switch heroAccessory {
            case .partnerOnline:
                Text("\(user.age)歳 · \(user.gender)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
            case .findMatchRate(let rate):
                Text("\(user.age)歳 · \(user.gender)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("マッチ度: \(rate)%")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.06))
                )
            case .none:
                EmptyView()
            }

            HStack(spacing: 5) {
                Text("保有ポイント")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                Text("\(user.totalPoints)pt")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
            }

            if case .partnerOnline = heroAccessory {
                HStack(spacing: 6) {
                    Circle()
                        .fill(user.isOnline ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(user.isOnline ? "オンライン" : "オフライン")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity")
                .font(.system(size: 14, weight: .bold))
                .tracking(1.1)
                .foregroundColor(.black)

            HStack(spacing: 14) {
                graphStatActivity(title: "今週距離", value: weeklyDistanceStatDisplay)
                graphStatActivity(title: "今週回数", value: weeklyRunCountStatDisplay)
                graphStatActivity(title: "今月距離", value: monthlyDistanceStatDisplay)
            }

            if isLoadingRemoteActivities {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.08))
                    ProgressView()
                }
                .frame(height: 190)
                .padding(.horizontal, 4)
            } else if resolvedWeeklyDistanceChartPoints.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.08))
                    Text("週次の走行記録がまだありません")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(height: 190)
                .padding(.horizontal, 4)
            } else {
                TasukiWeeklyActivityLineChart(
                    points: resolvedWeeklyDistanceChartPoints,
                    lineColor: user.tasukiStableChartAccentColor,
                    usesDailyPoints: hasRemoteActivityStats
                )
                .frame(height: 190)
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionEyebrow("RUNNING STATS")

            VStack(spacing: 14) {
                TasukiRunningStatTrendChartCard(
                    title: "平均ペース",
                    summaryValue: paceSummaryDisplay,
                    points: hasRemoteActivityStats
                        ? activityStats.dailyAveragePaceChartPoints()
                        : [],
                    yAxisValueFormatter: { TasukiChartPaceFormat.yAxisLabel(secondsPerKm: $0) },
                    yAxisStep: 60,
                    yAxisMaxLabels: 5
                )
                TasukiRunningStatTrendChartCard(
                    title: "今月距離",
                    summaryValue: monthlyDistanceStatDisplay,
                    points: hasRemoteActivityStats
                        ? activityStats.dailyActivityChartPoints()
                        : [],
                    yAxisValueFormatter: { String(format: "%.0f", $0) },
                    yAxisStep: 5
                )
                TasukiRunningStatTrendChartCard(
                    title: "走行回数",
                    summaryValue: monthlyRunCountSummaryDisplay,
                    points: hasRemoteActivityStats
                        ? activityStats.dailyRunCountChartPoints()
                        : [],
                    yAxisValueFormatter: { String(format: "%.0f", $0) },
                    yAxisStep: 1
                )
                TasukiRunningStatTrendChartCard(
                    title: "消費カロリー",
                    summaryValue: caloriesSummaryDisplay,
                    points: hasRemoteActivityStats
                        ? activityStats.dailyCaloriesChartPoints()
                        : [],
                    yAxisValueFormatter: { String(format: "%.0f", $0) },
                    yAxisStep: 100
                )
            }
            .overlay {
                if isLoadingRemoteActivities {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkBackground.opacity(0.55))
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("PROFILE")

            HStack {
                Image(systemName: "mappin.and.ellipse")
                Text(areaDisplay)
            }
            .font(.subheadline)
            .foregroundColor(.black)

            if !user.purpose.isEmpty {
                tagView(text: user.purpose, isPrimary: true)
            }

            if !runningSpotTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(runningSpotTags, id: \.self) { spot in
                        tagView(text: spot, isPrimary: false)
                    }
                }
            }

            VStack(spacing: 0) {
                if !user.personalBest.isEmpty {
                    infoRow(icon: "trophy.fill", title: "Personal Best", value: user.personalBest)
                }
                infoRow(icon: "calendar", title: "Schedule", value: user.schedule)
                if !user.nextRace.isEmpty {
                    infoRow(icon: "flag.fill", title: "Next Race", value: user.nextRace)
                }
                if !user.targetTime.isEmpty {
                    infoRow(icon: "scope", title: "Target", value: user.targetTime)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionEyebrow("ABOUT ME")
            Text(user.bio)
                .font(.system(size: 15))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.black)
    }

    private func graphStatActivity(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagView(text: String, isPrimary: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
            .foregroundColor(.black)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}
