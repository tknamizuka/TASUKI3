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
    
    var progress: CGFloat {
        CGFloat(min(currentDistance / goalDistance, 1.0))
    }
    
    var progressPercent: Int {
        Int((currentDistance / goalDistance) * 100)
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
                    GeometryReader { geo in
                        ZStack {
                            Image("runner")
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width * 0.9)
                                .opacity(0.15)
                            Text("TASUKI")
                                .font(.system(size: 50, weight: .heavy))
                                .tracking(10)
                                .foregroundColor(Color(hex: "0F1A2E"))
                                .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 0)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(height: 100)
                    .padding(.top, 20)

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

                                    VStack(spacing: 8) {
                                        if isHealthKitLoading {
                                            ProgressView()
                                            Text("—")
                                                .font(.system(size: subFont, weight: .medium))
                                                .foregroundColor(Color.tasukiMutedText)
                                        } else {
                                            Text("\(progressPercent)%")
                                                .font(.system(size: pctFont, weight: .bold))
                                                .foregroundColor(.black)
                                            Text(String(format: "%.1f / %.0f km", currentDistance, goalDistance))
                                                .font(.system(size: subFont, weight: .medium))
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
                        NavigationLink(destination: CoachView()) {
                            TasukiFlatHubRow(
                                title: "COACH",
                                subtitle: "パーソナルコーチ",
                                systemImage: "graduationcap.fill",
                                iconForegroundColor: Color.tasukiAccent
                            )
                        }
                        .buttonStyle(.plain)

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
            PracticeScheduleCalendarView(store: joinedPracticesStore)
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
