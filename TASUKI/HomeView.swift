//
//  HomeView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI
import Combine

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
    @State private var showMessageHubSheet = false
    @State private var messageHubSheetInitialTab: MessageListTab = .chat
    @ObservedObject private var activityStore = RunActivityStore.shared
    @ObservedObject private var runTracker = RunTracker.shared
    @EnvironmentObject private var mainTabRouter: MainTabRouter
    /// 子画面（シート内 `MessageListView` など）が `pushHiddenContext` でタブを隠すための共有状態。
    /// ルートの下部メニュー表示は `MainTabView.shouldShowMenuBar`（Home タブかつ非ネスト時のみ）と組み合わさる（`TASUKI_demo` と同じ）。
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @EnvironmentObject private var unreadProvider: UnreadCountProviderBase
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    @AppStorage("runningDataSource") private var runningDataSourceRaw: String = RunningDataSource.all.rawValue
    @AppStorage("myRank") private var myRank: String = "Rank E"
    @AppStorage("reduceRankingPressure") private var reduceRankingPressure: Bool = false
    @State private var runBannerTick = Date()
    private let runBannerTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
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
    
    /// アクティビティから即時計算する今月距離（Home の進捗率連動用）
    private var activityMonthlyDistanceKm: Double {
        activityStore.monthlyDistanceKm()
    }

    /// 円グラフ表示用の距離。読み込み中は実データと誤認しないよう 0 表示にする。
    private var ringShowsSampleWhileLoading: Bool {
        isHealthKitLoading && !usePreviewData && activityMonthlyDistanceKm <= 0
    }

    private var ringCurrentKm: Double {
        if ringShowsSampleWhileLoading {
            return 0
        }
        let fromActivities: Double
        if selectedRunningDataSource.usesHealthKitForQueries {
            fromActivities = activityMonthlyDistanceKm
        } else {
            fromActivities = activityStore.monthlyDistanceKm(matching: selectedRunningDataSource)
        }
        // 活動記録がある場合は HealthKit / 集計より先に Home 進捗へ即反映する
        return max(currentDistance, fromActivities)
    }

    private var ringGoalKm: Double {
        goalDistance
    }

    private var ringProgress: CGFloat {
        CGFloat(min(ringCurrentKm / max(ringGoalKm, 0.001), 1.0))
    }

    private var ringProgressPercent: Int {
        Int((ringCurrentKm / max(ringGoalKm, 0.001)) * 100)
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

    private var formattedTotalPoints: String {
        let n = PointService.shared.currentTotalPoints()
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return (f.string(from: NSNumber(value: n)) ?? "\(n)") + " pt"
    }

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TasukiBrandedHeroHeader(title: "TASUKI")

                    if runTracker.isTracking {
                        activeRunHomeBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    GeometryReader { geo in
                        let ringSize = min(geo.size.width * 0.58, 260)
                        let ringLine = max(14, ringSize * 0.065)
                        let pctFont = ringSize * 0.26
                        let subFont = max(13, ringSize * 0.078)

                        Button {
                            if !isHealthKitLoading { showRunHistory = true }
                        } label: {
                            VStack(spacing: 20) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.22), lineWidth: ringLine)
                                        .frame(width: ringSize, height: ringSize)
                                    Circle()
                                        .trim(from: 0, to: ringProgress)
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.tasukiBrandYellow, Color.tasukiAccent],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            style: StrokeStyle(lineWidth: ringLine, lineCap: .round)
                                        )
                                        .frame(width: ringSize, height: ringSize)
                                        .rotationEffect(.degrees(-90))

                                    VStack(spacing: 8) {
                                        Text(ringShowsSampleWhileLoading ? "—" : "\(ringProgressPercent)%")
                                            .font(.system(size: pctFont, weight: .bold))
                                            .foregroundColor(.black)
                                        Text(ringShowsSampleWhileLoading ? "走行データを取得中" : String(format: "%.1f / %.0f km", ringCurrentKm, ringGoalKm))
                                            .font(.system(size: subFont, weight: .medium))
                                            .foregroundColor(Color.tasukiMutedText)
                                        if ringShowsSampleWhileLoading {
                                            Text(selectedRunningDataSource.usesHealthKitForQueries ? "HealthKit から取得中…" : "記録を読み込み中…")
                                                .font(.system(size: max(11, subFont * 0.75), weight: .medium))
                                                .foregroundColor(Color.tasukiMutedText)
                                        }
                                    }
                                }
                                .frame(width: ringSize, height: ringSize)

                                Text("MONTHLY GOAL（タップで履歴）")
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.2)
                                    .foregroundColor(Color.tasukiMutedText)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(isHealthKitLoading)
                        .frame(width: geo.size.width, height: ringSize + 100)
                    }
                    .frame(height: 360)

                    VStack(alignment: .center, spacing: 10) {
                        Text("TOTAL POINTS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(Color.tasukiMutedText)
                            .multilineTextAlignment(.center)
                        Text(formattedTotalPoints)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                    .padding(.bottom, 28)

                    if !isHealthKitLoading {
                        Text("ソース: \(selectedRunningDataSource.displayName)")
                            .font(.caption)
                            .foregroundColor(Color.tasukiMutedText.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 20)
                    }

                    if let error = healthKitError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Color.tasukiAccentOrange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 28)
                            .padding(.bottom, 12)
                    }

                    VStack(spacing: 0) {
                    }
                    .padding(.horizontal, 20)

                    if !reduceRankingPressure {
                        NavigationLink(destination: RankingView()) {
                            TasukiFlatHubRow(
                                title: "RANKING",
                                subtitle: "総合ランキング · 現在 \(myRank) · 同ランク内 \(sameRankPosition)/\(sameRankTotal)（参考）",
                                systemImage: "crown.fill",
                                iconFontSize: 20,
                                hStackSpacing: 12,
                                titleSubtitleSpacing: 4
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showRunHistory) {
            RunHistoryListView()
                .environmentObject(mainTabRouter)
        }
        .sheet(isPresented: $showPracticeCalendar) {
            PracticeScheduleCalendarView(store: joinedPracticesStore)
        }
        .sheet(isPresented: $showMessageHubSheet) {
            NavigationStack {
                MessageListView(initialTab: messageHubSheetInitialTab, embedNavigationStack: false)
            }
            .environmentObject(tabBarVisibility)
        }
        .navigationTitle("")
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
                                .foregroundColor(Color.tasukiOnBrandYellow)
                                .padding(4)
                                .background(Circle().fill(Color.tasukiBrandYellow))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: MessageListView(embedNavigationStack: false)) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color.tasukiPrimary)
                        if unreadProvider.unreadCount > 0 {
                            Text("\(min(unreadProvider.unreadCount, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                                .padding(4)
                                .background(Circle().fill(Color.tasukiBrandYellow))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: mainTabRouter.pendingMessageHubTab) { _, newValue in
            guard let tab = newValue else { return }
            messageHubSheetInitialTab = tab
            showMessageHubSheet = true
            mainTabRouter.pendingMessageHubTab = nil
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
        .onReceive(runBannerTimer) { date in
            if runTracker.isTracking {
                runBannerTick = date
            }
        }
        .onChange(of: runningDataSourceRaw) { _, _ in
            let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            if !usePreviewData, !isPreview {
                loadDistanceFromHealthKit()
            }
        }
        .onChange(of: activityStore.activities.count) { _ in
            // Home の進捗リングは Activity 記録に直接連動させる。
            if !activityStore.activities.isEmpty {
                isHealthKitLoading = false
            }
        }
    }

    private var activeRunHomeBanner: some View {
        Button {
            mainTabRouter.selectedTab = 1
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.run")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(runTracker.isPaused ? "走行記録 · 一時停止中" : "走行記録中")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Color.tasukiPrimary.opacity(0.75))
                    HStack(spacing: 16) {
                        Text(formatRunElapsed(runTracker.elapsedSeconds(now: runBannerTick)))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(String(format: "%.2f km", runTracker.distanceKm))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.tasukiBrandYellow)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Runタブで記録画面を開く")
    }

    private func formatRunElapsed(_ sec: TimeInterval) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func loadDistanceFromHealthKit() {
        if !selectedRunningDataSource.usesHealthKitForQueries {
            isHealthKitLoading = false
            let ds = selectedRunningDataSource
            let km = activityStore.monthlyDistanceKm(matching: ds)
            currentDistance = km
            if km == 0 {
                healthKitError = "\(ds.displayName) 由来の TASUKI 内記録が今月はまだありません"
            } else {
                healthKitError = nil
            }
            RankPromotionManager.shared.evaluateMonthlyDistancePromotion(monthlyKm: km)
            return
        }

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
                    RankPromotionManager.shared.evaluateMonthlyDistancePromotion(monthlyKm: km)
                case .failure(let err):
                    healthKitError = err.localizedDescription
                }
            }
        }
    }
}

#Preview("通常（読み込み中）") {
    NavigationStack {
        HomeView()
    }
    .environmentObject(MainTabRouter())
    .environmentObject(TabBarVisibility())
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
}

/// 円グラフ（黄→紫グラデ・進捗弧）の見え方確認用サンプル。実機では HealthKit の値を使用。
#Preview("円グラフサンプル・中くらい（63%）") {
    NavigationStack {
        HomeView(
            currentDistance: 63.0,
            goalDistance: 100.0,
            isHealthKitLoading: false,
            usePreviewData: true
        )
    }
    .environmentObject(MainTabRouter())
    .environmentObject(TabBarVisibility())
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
}

#Preview("円グラフサンプル・未達（22%）") {
    NavigationStack {
        HomeView(
            currentDistance: 21.8,
            goalDistance: 100.0,
            isHealthKitLoading: false,
            usePreviewData: true
        )
    }
    .environmentObject(MainTabRouter())
    .environmentObject(TabBarVisibility())
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
}

#Preview("円グラフサンプル・ほぼ達成（91%）") {
    NavigationStack {
        HomeView(
            currentDistance: 90.7,
            goalDistance: 100.0,
            isHealthKitLoading: false,
            usePreviewData: true
        )
    }
    .environmentObject(MainTabRouter())
    .environmentObject(TabBarVisibility())
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
}

#Preview("円グラフサンプル・目標超え（109%・弧は100%で頭打ち）") {
    NavigationStack {
        HomeView(
            currentDistance: 108.5,
            goalDistance: 100.0,
            isHealthKitLoading: false,
            usePreviewData: true
        )
    }
    .environmentObject(MainTabRouter())
    .environmentObject(TabBarVisibility())
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
}

#Preview("未読・参加予定バッジあり") {
    let store = JoinedPracticesStore()
    store.add(JoinedPracticeItem(id: "1", practiceId: "p1", title: "皇居ラン", location: "皇居", date: Date(), chatId: nil))
    return NavigationStack {
        HomeView(
            currentDistance: 63.0,
            goalDistance: 100.0,
            isHealthKitLoading: false,
            usePreviewData: true
        )
    }
    .environmentObject(MainTabRouter())
    .environmentObject(TabBarVisibility())
    .environmentObject(PreviewUnreadProvider(unreadCount: 3) as UnreadCountProviderBase)
    .environmentObject(store)
}
