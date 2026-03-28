//
//  HomeView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

struct HomeView: View {
    // 目標管理用のデータ（currentDistance は HealthKit から取得）
    @State private var currentDistance: Double
    @State private var goalDistance: Double
    @State private var isHealthKitLoading: Bool
    @State private var healthKitError: String?
    
    /// プレビュー用: true のときは onAppear で HealthKit を読まない
    private let usePreviewData: Bool
    
    @State private var showRunHistory = false
    @State private var showPracticeCalendar = false
    @State private var showDailyCheckIn = false
    @State private var showRestAcknowledged = false
    @ObservedObject private var activityStore = RunActivityStore.shared
    @EnvironmentObject private var unreadProvider: UnreadCountProviderBase
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    @AppStorage("runningDataSource") private var runningDataSourceRaw: String = RunningDataSource.all.rawValue
    @AppStorage("myRank") private var myRank: String = "Rank E"
    @AppStorage("reduceRankingPressure") private var reduceRankingPressure: Bool = false
    init(
        currentDistance: Double = 0.0,
        goalDistance: Double = 100.0,
        isHealthKitLoading: Bool = true,
        healthKitError: String? = nil,
        usePreviewData: Bool = false
    ) {
        _currentDistance = State(initialValue: currentDistance)
        _goalDistance = State(initialValue: goalDistance)
        _isHealthKitLoading = State(initialValue: isHealthKitLoading)
        _healthKitError = State(initialValue: healthKitError)
        self.usePreviewData = usePreviewData
    }
    
    // 進捗率（0.0〜1.0）
    var progress: CGFloat {
        return CGFloat(min(currentDistance / goalDistance, 1.0))
    }
    
    // 進捗率（%整数）
    var progressPercent: Int {
        return Int((currentDistance / goalDistance) * 100)
    }

    private var selectedRunningDataSource: RunningDataSource {
        RunningDataSource(rawValue: runningDataSourceRaw) ?? .all
    }

    private var sameRankUsers: [User] {
        var users = [mockUser] + mockUsers
        var me = users[0]
        me.rank = myRank
        me.totalPoints = PointService.shared.currentTotalPoints()
        users[0] = me
        return users
            .filter { $0.rank == myRank }
            .sorted { $0.totalPoints > $1.totalPoints }
    }

    private var sameRankPosition: Int {
        guard let idx = sameRankUsers.firstIndex(where: { $0.id == mockUser.id }) else { return 1 }
        return idx + 1
    }

    private var sameRankTotal: Int {
        max(sameRankUsers.count, 1)
    }

    private var companionSuggestion: CompanionSuggestion {
        CompanionSuggestionEngine.suggestion(
            checkIn: DailyCheckInStore.savedCheckInConditionForToday(),
            daysSinceLastRun: activityStore.daysSinceLastRun(),
            monthlyGoalKm: goalDistance,
            monthToDateKm: currentDistance
        )
    }
    
    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            VStack(spacing: 10) {
                VStack(alignment: .center, spacing: 4) {
                    Text("RUN DASHBOARD")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundColor(Color.tasukiMutedText)
                    ZStack {
                        Image("runner")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 70)
                            .opacity(0.22)
                        Text("TASUKI")
                            .font(.system(size: 32, weight: .heavy))
                            .tracking(4)
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                companionCard

                Button {
                    if !isHealthKitLoading { showRunHistory = true }
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("MONTHLY GOAL")
                                .font(.caption)
                                .fontWeight(.bold)
                                .tracking(1.5)
                                .foregroundColor(Color.tasukiMutedText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(Color.tasukiMutedText)
                        }

                        HStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                                    .frame(width: 104, height: 104)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.tasukiAccentOrange, Color.royalBlue],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                    )
                                    .frame(width: 104, height: 104)
                                    .rotationEffect(.degrees(-90))
                                Text("\(progressPercent)%")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(Color.tasukiPrimary)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                if isHealthKitLoading {
                                    ProgressView()
                                    Text("同期中...")
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                } else {
                                    Text(String(format: "%.1fkm", currentDistance))
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(Color.tasukiPrimary)
                                    Text("目標 \(Int(goalDistance))km")
                                        .font(.subheadline)
                                        .foregroundColor(Color.tasukiMutedText)
                                    Text("ソース: \(selectedRunningDataSource.displayName)")
                                        .font(.caption2)
                                        .foregroundColor(Color.tasukiMutedText)
                                }
                            }
                            Spacer()
                        }

                        if let error = healthKitError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Color.tasukiAccentOrange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isHealthKitLoading)

                HStack(spacing: 12) {
                    quickMetricCard(
                        title: "TOTAL POINTS",
                        value: "\(PointService.shared.currentTotalPoints())",
                        suffix: "pt",
                        icon: "flame.fill"
                    )
                    NavigationLink(destination: CoachView()) {
                        quickActionCard(
                            title: "COACH",
                            subtitle: "あなたのパーソナルコーチ",
                            icon: "graduationcap.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    NavigationLink(destination: RunRecordingView()) {
                        quickActionCard(
                            title: "RUN RECORDER",
                            subtitle: "走行を開始して記録",
                            icon: "figure.run"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: ChallengeHubView()) {
                        quickActionCard(
                            title: "CHALLENGES",
                            subtitle: "進捗は参考。休んだ日も歴史の一部",
                            icon: "flag.checkered.2.crossed"
                        )
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink(destination: WeeklyReflectionView()) {
                    weeklyReflectionShortcutCard
                }
                .buttonStyle(.plain)

                if !reduceRankingPressure {
                    NavigationLink(destination: RankingView()) {
                        rankingShortcutCard
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 80)
        }
        .sheet(isPresented: $showRunHistory) {
            RunHistoryListView()
        }
        .sheet(isPresented: $showPracticeCalendar) {
            PracticeScheduleCalendarView(store: joinedPracticesStore)
        }
        .sheet(isPresented: $showDailyCheckIn) {
            DailyCheckInSheet { condition in
                DailyCheckInStore.saveCheckIn(condition)
            }
        }
        .alert("今日は休みましょう", isPresented: $showRestAcknowledged) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("休む判断もトレーニングの一部です。また戻ってきてくださいね。")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showPracticeCalendar = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "calendar")
                            .font(.system(size: 20))
                            .foregroundColor(Color.tasukiPrimary)
                        if joinedPracticesStore.scheduledCount > 0 {
                            Text("\(min(joinedPracticesStore.scheduledCount, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(Color.tasukiAccentOrange))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: MessageListView()) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.tasukiPrimary)
                        if unreadProvider.unreadCount > 0 {
                            Text("\(min(unreadProvider.unreadCount, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(Color.tasukiAccentOrange))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
            }
        }
        .onAppear {
            let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            if !usePreviewData, !isPreview {
                loadDistanceFromHealthKit()
            } else if isPreview {
                isHealthKitLoading = false
            }
            unreadProvider.refreshUnreadCount()
            activityStore.refreshFromRemote()
        }
    }

    private var companionCard: some View {
        let s = companionSuggestion
        return VStack(alignment: .leading, spacing: 12) {
            Text("TODAY · 伴走")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.5)
                .foregroundColor(Color.tasukiMutedText)
            Text(s.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.reason)
                .font(.footnote)
                .foregroundColor(Color.tasukiMutedText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if s.plan == .checkInNeeded {
                    Button {
                        showDailyCheckIn = true
                    } label: {
                        companionButtonLabel(s.primaryCTALabel, style: .primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(destination: RunRecordingView()) {
                        companionButtonLabel(s.primaryCTALabel, style: .primary)
                    }
                    .buttonStyle(.plain)
                }

                if let secondary = s.secondaryCTALabel {
                    Button {
                        handleCompanionSecondary(plan: s.plan, label: secondary)
                    } label: {
                        companionButtonLabel(secondary, style: .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if DailyCheckInStore.hasCheckedInToday() {
                Button {
                    showDailyCheckIn = true
                } label: {
                    Text("コンディションを記録し直す")
                        .font(.caption)
                        .foregroundColor(Color.tasukiAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    private enum CompanionButtonStyle {
        case primary
        case secondary
    }

    private func companionButtonLabel(_ title: String, style: CompanionButtonStyle) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(style == .primary ? .white : Color.tasukiPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(style == .primary ? Color.tasukiPrimary : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.tasukiDarkCardSecondary, lineWidth: style == .primary ? 0 : 1)
                    )
            )
    }

    private func handleCompanionSecondary(plan: TodayPlan, label: String) {
        if label.contains("休む") || plan == .rest {
            EngagementSignals.touchSignificantInteraction()
            showRestAcknowledged = true
            RealityMiningManager.shared.trackEvent(name: "companion_rest_chosen", properties: [:])
            return
        }
        if label.contains("歩く") || plan == .microWalk {
            RealityMiningManager.shared.trackEvent(name: "companion_micro_walk_hint", properties: [:])
        }
    }

    private var weeklyReflectionShortcutCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.tasukiAccent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("今週の振り返り")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("回数・休息も含めて振り返る")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.tasukiMutedText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    private func quickMetricCard(title: String, value: String, suffix: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color.tasukiAccentOrange)
            Text(title)
                .font(.caption2)
                .foregroundColor(Color.tasukiMutedText)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.caption)
                        .foregroundColor(Color.tasukiMutedText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    private func quickActionCard(title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.tasukiAccent)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(Color.tasukiMutedText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }

    private var rankingShortcutCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.tasukiAccent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("RANKING")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("総合ランキング · 現在 \(myRank) · 同ランク内 \(sameRankPosition)/\(sameRankTotal)（順位はあくまで参考）")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.tasukiMutedText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }
    
    /// HealthKit から今月の走行距離を取得して currentDistance に反映
    private func loadDistanceFromHealthKit() {
        HealthKitManager.shared.requestAuthorization { success, error in
            if !success {
                isHealthKitLoading = false
                healthKitError = "HealthKit の利用を許可してください"
                return
            }
            HealthKitManager.shared.fetchRunningDistanceThisMonth(dataSource: selectedRunningDataSource) { result in
                isHealthKitLoading = false
                switch result {
                case .success(let km):
                    currentDistance = km
                    if km == 0, selectedRunningDataSource != .all {
                        healthKitError = "\(selectedRunningDataSource.displayName) の記録が見つかりません"
                    } else {
                        healthKitError = nil
                    }
                    // 距離ベースのランク昇格判定
                    RankPromotionManager.shared.evaluateMonthlyDistancePromotion(monthlyKm: km)
                case .failure(let err):
                    healthKitError = err.localizedDescription
                }
            }
        }
    }
}

// MARK: - Daily check-in

private struct DailyCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Condition) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("今日のコンディション")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("ひとつだけ選べばOKです")
                    .font(.subheadline)
                    .foregroundColor(Color.tasukiMutedText)

                VStack(spacing: 10) {
                    ForEach(Condition.allCases, id: \.self) { condition in
                        Button {
                            onPick(condition)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: condition.icon)
                                    .foregroundColor(Color(hex: condition.colorHex))
                                Text(condition.rawValue)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.tasukiSurface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(20)
            .background(Color.tasukiDarkBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

#Preview("通常（読み込み中）") {
    NavigationStack {
        HomeView()
    }
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
}

#Preview("サンプル値") {
    NavigationStack {
        HomeView(
            currentDistance: 45.2,
            goalDistance: 100.0,
            isHealthKitLoading: false,
            usePreviewData: true
        )
    }
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
}

#Preview("未読・参加予定バッジあり") {
    let store = JoinedPracticesStore()
    store.add(JoinedPracticeItem(id: "1", practiceId: "p1", title: "皇居ラン", location: "皇居", date: Date(), chatId: nil))
    return NavigationStack {
        HomeView(
            currentDistance: 45.2,
            goalDistance: 100.0,
            isHealthKitLoading: false,
            usePreviewData: true
        )
    }
    .environmentObject(PreviewUnreadProvider(unreadCount: 3) as UnreadCountProviderBase)
    .environmentObject(store)
}
