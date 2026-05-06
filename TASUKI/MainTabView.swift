import SwiftUI
import UIKit

struct MainTabView: View {
    @StateObject private var mainTabRouter = MainTabRouter()
    @State private var previousTabIndex: Int = 0
    @State private var tabEnterDate: Date = Date()
    @State private var showReengagementSheet = false
    @State private var reengagementGapDays = 0
    /// 非 Home タブのパネルを右へずらす量（Home を手前に見せる）
    @State private var panelSlideOffset: CGFloat = 0
    @State private var screenWidth: CGFloat = UIScreen.main.bounds.width
    @EnvironmentObject private var unreadProvider: UnreadCountProviderBase
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var coachCertification: CoachCertificationManager
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    
    private let tabItems: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("figure.run", "Run"),
        ("person.3.fill", "EKIDEN"),
        ("magnifyingglass", "Find"),
        ("person.fill", "Me")
    ]

    /// `TASUKI_demo` と同じ: Home タブ以外はモード画面として扱い、下部メニューを隠す。`TabBarVisibility` でネスト画面がさらに隠す。
    private var shouldShowMenuBar: Bool {
        mainTabRouter.selectedTab == 0 && !tabBarVisibility.isHidden
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                homeTabRoot
                    .frame(width: w, height: geo.size.height)
                    .allowsHitTesting(mainTabRouter.selectedTab == 0)

                if mainTabRouter.selectedTab != 0 {
                    nonHomeTabRoot(for: mainTabRouter.selectedTab)
                        .frame(width: w, height: geo.size.height)
                        .offset(x: panelSlideOffset)
                        .background(Color.tasukiDarkBackground)
                        .clipped()
                        .shadow(color: Color.black.opacity(panelSlideOffset > 2 ? 0.18 : 0), radius: 10, x: -6, y: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { screenWidth = w }
            .onChange(of: w) { _, newW in screenWidth = newW }
            .simultaneousGesture(interactiveSwipeToHomeGesture(screenWidth: w))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(mainTabRouter)
        .overlay(alignment: .topLeading) {
            if mainTabRouter.selectedTab != 0, !mainTabRouter.suppressBackToHomeOverlay {
                backToHomeButton
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowMenuBar {
                customTabBar
            }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            previousTabIndex = mainTabRouter.selectedTab
            tabEnterDate = Date()
            RealityMiningManager.shared.trackScreenView(name: tabItems[mainTabRouter.selectedTab].label)
            let gap = EngagementSignals.daysSinceSignificantInteraction()
            if gap >= 3 {
                reengagementGapDays = gap
                showReengagementSheet = true
                RealityMiningManager.shared.trackEvent(
                    name: "reengagement_shown",
                    properties: ["days_away": gap]
                )
            }
        }
        .fullScreenCover(isPresented: $showReengagementSheet) {
            ReengagementSheetView(daysAway: reengagementGapDays) {
                showReengagementSheet = false
            }
        }
        .onChange(of: mainTabRouter.selectedTab) { newValue in
            if newValue != 0 {
                panelSlideOffset = 0
            }
            if newValue == 2 {
                mainTabRouter.suppressBackToHomeOverlay = false
            }
            // #region agent log
            AgentDebugLog.log(
                location: "MainTabView.onChange(selectedTab)",
                message: "tab_changed",
                hypothesisId: "H5",
                data: [
                    "newValue": "\(newValue)",
                    "previousTabIndex": "\(previousTabIndex)"
                ]
            )
            // #endregion
            let previousTabName = tabItems.indices.contains(previousTabIndex) ? tabItems[previousTabIndex].label : "unknown"
            let duration = Date().timeIntervalSince(tabEnterDate)
            RealityMiningManager.shared.trackEvent(
                name: "screen_view_end",
                properties: [
                    "screen_name": previousTabName,
                    "duration_sec": duration
                ]
            )

            tabEnterDate = Date()
            let nextTabName = tabItems.indices.contains(newValue) ? tabItems[newValue].label : "unknown"
            RealityMiningManager.shared.trackScreenView(name: nextTabName)
            previousTabIndex = newValue
        }
    }

    private var backToHomeButton: some View {
        Button {
            returnToHome()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                Text("Home")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.95))
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .padding(.leading, 12)
    }

    private var homeTabRoot: some View {
        NavigationStack {
            HomeView()
                .environmentObject(unreadProvider)
                .environmentObject(mainTabRouter)
                .environmentObject(tabBarVisibility)
        }
    }

    @ViewBuilder
    private func nonHomeTabRoot(for tab: Int) -> some View {
        switch tab {
        case 1:
            NavigationStack {
                RunRecordingView()
                    .environmentObject(coachCertification)
                    .environmentObject(mainTabRouter)
            }
        case 2:
            TeamView()
        case 3:
            FindView()
        case 4:
            meTabContent()
        default:
            NavigationStack {
                HomeView()
                    .environmentObject(unreadProvider)
                    .environmentObject(mainTabRouter)
                    .environmentObject(tabBarVisibility)
            }
        }
    }

    /// 右にスワイプしてパネルを動かし、閾値で Home に戻る（縦スクロールとの兼ね合いで横方向を優先）。
    private func interactiveSwipeToHomeGesture(screenWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onChanged { value in
                guard mainTabRouter.selectedTab != 0 else { return }
                guard !mainTabRouter.suppressBackToHomeOverlay else { return }
                let dx = value.translation.width
                let dy = abs(value.translation.height)
                guard dx > 0, dx > dy * 0.65 else { return }
                panelSlideOffset = min(dx, screenWidth)
            }
            .onEnded { value in
                guard mainTabRouter.selectedTab != 0 else { return }
                guard !mainTabRouter.suppressBackToHomeOverlay else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        panelSlideOffset = 0
                    }
                    return
                }
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let shouldComplete = dx >= 240 || predicted >= 380
                if shouldComplete {
                    finishSwipeTransitionToHome(usingWidth: screenWidth)
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        panelSlideOffset = 0
                    }
                }
            }
    }

    private func finishSwipeTransitionToHome(usingWidth: CGFloat) {
        let w = usingWidth > 1 ? usingWidth : screenWidth
        withAnimation(.easeInOut(duration: 0.28)) {
            panelSlideOffset = w
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.29) {
            mainTabRouter.selectedTab = 0
            panelSlideOffset = 0
        }
    }

    private func returnToHome() {
        finishSwipeTransitionToHome(usingWidth: screenWidth)
    }
    
    private func meTabContent() -> some View {
        // #region agent log
        AgentDebugLog.log(
            location: "MainTabView.meTabContent",
            message: "before_MyProfileView_construct",
            hypothesisId: "H1",
            data: [
                "runId": "post-fix",
                "reinjectAuth": "true",
                "reinjectCoach": "true"
            ]
        )
        // #endregion
        return MyProfileView()
            .environmentObject(authManager)
            .environmentObject(coachCertification)
    }

    private func tabLabelColor(index: Int) -> Color {
        mainTabRouter.selectedTab == index ? Color.tasukiOnBrandYellow : .black
    }

    @ViewBuilder
    private func tabBarIcon(systemName: String, index: Int) -> some View {
        if mainTabRouter.selectedTab == index {
            TasukiBrandOutlinedSymbol(systemName: systemName, size: 18, weight: .semibold)
        } else {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
        }
    }

    private func tabSelectionBackground(for index: Int) -> Color {
        mainTabRouter.selectedTab == index ? Color.tasukiTabSelectionFill : .clear
    }
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabItems.count, id: \.self) { index in
                Button(action: {
                    if index == 0, mainTabRouter.selectedTab != 0 {
                        returnToHome()
                    } else {
                        mainTabRouter.selectedTab = index
                    }
                }) {
                    VStack(spacing: 2) {
                        tabBarIcon(systemName: tabItems[index].icon, index: index)
                        Text(tabItems[index].label)
                            .font(.system(size: 9, weight: mainTabRouter.selectedTab == index ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundColor(tabLabelColor(index: index))
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tabSelectionBackground(for: index))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthManager(forPreview: true))
        .environmentObject(UserManager())
        .environmentObject(PreviewUnreadProvider() as UnreadCountProviderBase)
        .environmentObject(JoinedPracticesStore())
        .environmentObject(CoachCertificationManager.shared)
        .environmentObject(TabBarVisibility())
}
