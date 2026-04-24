//
//  HomeView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

/// HealthKit 取得待ちの間に円グラフへ出すサンプル値（黄→紫の弧の見た目用。取得後は実距離に切り替わる）。
private enum MonthlyGoalRingSample {
    static let currentKm = 63.0
    static let goalKm = 100.0
}

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
    @ObservedObject private var activityStore = RunActivityStore.shared
    @EnvironmentObject private var unreadProvider: UnreadCountProviderBase
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    @EnvironmentObject private var matchPromisesStore: MatchPromisesStore
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
    
    /// 円グラフ表示用の距離（読み込み中はサンプル、それ以外は実データ）
    private var ringShowsSampleWhileLoading: Bool {
        isHealthKitLoading && !usePreviewData
    }

    private var ringCurrentKm: Double {
        ringShowsSampleWhileLoading ? MonthlyGoalRingSample.currentKm : currentDistance
    }

    private var ringGoalKm: Double {
        ringShowsSampleWhileLoading ? MonthlyGoalRingSample.goalKm : goalDistance
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

    /// カレンダーバッジ用（参加練習会 + マッチング約束の登録件数。サンプル表示は含めない）
    private var calendarScheduleBadgeCount: Int {
        joinedPracticesStore.scheduledCount + matchPromisesStore.scheduledCount
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
                    GeometryReader { geo in
                        HStack {
                            Spacer(minLength: 0)
                            Image("mainlogo")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: geo.size.width * 0.66, maxHeight: geo.size.height)
                            Spacer(minLength: 0)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(height: 100)
                    .padding(.horizontal, 12)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

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
                                        Text("\(ringProgressPercent)%")
                                            .font(.system(size: pctFont, weight: .bold))
                                            .foregroundColor(.black)
                                        Text(String(format: "%.1f / %.0f km", ringCurrentKm, ringGoalKm))
                                            .font(.system(size: subFont, weight: .medium))
                                            .foregroundColor(Color.tasukiMutedText)
                                        if ringShowsSampleWhileLoading {
                                            Text("HealthKit から取得中…")
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
                        NavigationLink(destination: RunRecordingView()) {
                            TasukiFlatHubRow(
                                title: "RUN",
                                subtitle: "記録を開始",
                                systemImage: "figure.run",
                                iconForegroundColor: Color(hex: "2E7D32")
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: ChallengeHubView()) {
                            TasukiFlatHubRow(
                                title: "CHALLENGE",
                                subtitle: "進捗は参考",
                                systemImage: "flag.checkered.2.crossed",
                                iconForegroundColor: Color.tasukiPrimary
                            )
                        }
                        .buttonStyle(.plain)
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
        }
        .sheet(isPresented: $showPracticeCalendar) {
            PracticeScheduleCalendarView(
                store: joinedPracticesStore,
                matchPromisesStore: matchPromisesStore
            )
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
                            .foregroundColor(.black)
                        if calendarScheduleBadgeCount > 0 {
                            Text("\(min(calendarScheduleBadgeCount, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                                .padding(4)
                                .background(Circle().fill(Color.tasukiBrandYellow))
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
                            .foregroundColor(.black)
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
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
    .environmentObject(MatchPromisesStore())
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
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
    .environmentObject(MatchPromisesStore())
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
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
    .environmentObject(MatchPromisesStore())
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
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
    .environmentObject(MatchPromisesStore())
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
    .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
    .environmentObject(JoinedPracticesStore())
    .environmentObject(MatchPromisesStore())
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
    .environmentObject(PreviewUnreadProvider(unreadCount: 3) as UnreadCountProviderBase)
    .environmentObject(store)
    .environmentObject(MatchPromisesStore())
}
