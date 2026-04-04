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

    /// MainTabView の safeAreaInset 内でレイアウトされる高さの約半分をパネルに割り当てる
    private static let monthlyGoalHeightRatio: CGFloat = 0.5

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            GeometryReader { geometry in
                let panelHeight = max(300, geometry.size.height * Self.monthlyGoalHeightRatio)
                let ringSize = min(max(panelHeight * 0.4, 148), 228)
                let ringLine = max(12, min(18, ringSize * 0.105))
                let pctSize = max(26, ringSize * 0.21)
                let goalSubSize = max(12, ringSize * 0.096)
                let kmSize = max(30, panelHeight * 0.14)
                let headerSize: CGFloat = 16
                let bottomBreathing: CGFloat = 12

                VStack(spacing: 10) {
                    Button {
                        if !isHealthKitLoading { showRunHistory = true }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("MONTHLY GOAL")
                                    .font(.system(size: headerSize, weight: .bold))
                                    .tracking(1.8)
                                    .foregroundColor(Color.tasukiMutedText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: headerSize, weight: .semibold))
                                    .foregroundColor(Color.tasukiMutedText)
                            }
                            .padding(.bottom, 16)

                            Spacer(minLength: 8)

                            HStack(alignment: .center, spacing: 16) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.2), lineWidth: ringLine)
                                        .frame(width: ringSize, height: ringSize)
                                    Circle()
                                        .trim(from: 0, to: isHealthKitLoading ? 0 : progress)
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
                                    VStack(spacing: 6) {
                                        Text(isHealthKitLoading ? "—" : "\(progressPercent)%")
                                            .font(.system(size: pctSize, weight: .bold))
                                            .foregroundColor(.black)
                                        Text("目標 \(Int(goalDistance)) km")
                                            .font(.system(size: goalSubSize, weight: .semibold))
                                            .foregroundColor(Color.tasukiMutedText)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: ringSize * 0.74)
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    if isHealthKitLoading {
                                        ProgressView()
                                        Text("同期中...")
                                            .font(.subheadline)
                                            .foregroundColor(Color.tasukiMutedText)
                                    } else {
                                        Text(String(format: "%.1fkm", currentDistance))
                                            .font(.system(size: kmSize, weight: .bold))
                                            .foregroundColor(.black)
                                            .minimumScaleFactor(0.7)
                                            .lineLimit(1)
                                        Text("ソース: \(selectedRunningDataSource.displayName)")
                                            .font(.system(size: max(11, goalSubSize - 1)))
                                            .foregroundColor(Color.tasukiMutedText)
                                        HStack(spacing: 6) {
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: max(15, kmSize * 0.42)))
                                                .foregroundColor(Color.tasukiBrandYellow)
                                            Text("\(PointService.shared.currentTotalPoints()) pt")
                                                .font(.system(size: max(15, kmSize * 0.48), weight: .semibold))
                                                .foregroundColor(.black)
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }

                            Spacer(minLength: 8)

                            if let error = healthKitError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(Color.tasukiAccentOrange)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(22)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color.tasukiSurface)
                                .shadow(color: Color.tasukiMutedText.opacity(0.12), radius: 8, x: 0, y: 3)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isHealthKitLoading)
                    .frame(height: panelHeight)
                    .frame(maxWidth: .infinity)

                    HStack(alignment: .top, spacing: 8) {
                        NavigationLink(destination: CoachView()) {
                            quickActionCard(
                                title: "COACH",
                                subtitle: "パーソナルコーチ",
                                icon: "graduationcap.fill"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        NavigationLink(destination: RunRecordingView()) {
                            quickActionCard(
                                title: "RUN",
                                subtitle: "記録を開始",
                                icon: "figure.run"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)

                        NavigationLink(destination: ChallengeHubView()) {
                            quickActionCard(
                                title: "CHALLENGE",
                                subtitle: "進捗は参考",
                                icon: "flag.checkered.2.crossed"
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }

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
                .padding(.bottom, bottomBreathing)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .sheet(isPresented: $showRunHistory) {
            RunHistoryListView()
        }
        .sheet(isPresented: $showPracticeCalendar) {
            PracticeScheduleCalendarView(store: joinedPracticesStore)
        }
        .navigationTitle("ホーム")
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

    private func quickActionCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color.tasukiMutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tasukiSurface)
                .shadow(color: Color.tasukiMutedText.opacity(0.12), radius: 8, x: 0, y: 3)
        )
    }

    private var rankingShortcutCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("RANKING")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
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
                .fill(Color.tasukiSurface)
                .shadow(color: Color.tasukiMutedText.opacity(0.12), radius: 8, x: 0, y: 3)
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
