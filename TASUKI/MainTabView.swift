import SwiftUI

struct MainTabView: View {
    @StateObject private var mainTabRouter = MainTabRouter()
    @State private var previousTabIndex: Int = 0
    @State private var tabEnterDate: Date = Date()
    @EnvironmentObject private var unreadProvider: UnreadCountProviderBase
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var coachCertification: CoachCertificationManager
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    @EnvironmentObject private var matchPromisesStore: MatchPromisesStore

    private let tabItems: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("figure.run", "Run"),
        ("person.3.fill", "EKIDEN"),
        ("magnifyingglass", "Find"),
        ("person.fill", "Me")
    ]

    /// Home 以外はモード画面として扱い、下部メニューを隠す。
    private var shouldShowMenuBar: Bool {
        mainTabRouter.selectedTab == 0 && !tabBarVisibility.isHidden
    }

    var body: some View {
        Group {
            switch mainTabRouter.selectedTab {
            case 0:
                NavigationStack {
                    HomeView()
                        .environmentObject(unreadProvider)
                }
            case 1:
                NavigationStack {
                    RunRecordingView()
                        .environmentObject(mainTabRouter)
                }
            case 2:
                TeamView()
            case 3:
                FindView()
            case 4:
                meTabContent()
            default:
                NavigationStack { HomeView().environmentObject(unreadProvider) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environmentObject(mainTabRouter)
        .overlay(alignment: .topLeading) {
            if mainTabRouter.selectedTab != 0, !mainTabRouter.suppressBackToHomeOverlay {
                backToHomeButton
            }
        }
        .simultaneousGesture(returnToHomeGesture)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowMenuBar {
                customTabBar
            }
        }
        .ignoresSafeArea(.keyboard)
        .onReceive(joinedPracticesStore.$items) { items in
            TasukiScheduleReminderScheduler.reschedule(joined: items, promises: matchPromisesStore.items)
        }
        .onReceive(matchPromisesStore.$items) { items in
            TasukiScheduleReminderScheduler.reschedule(joined: joinedPracticesStore.items, promises: items)
        }
        .onAppear {
            TasukiScheduleReminderScheduler.reschedule(joined: joinedPracticesStore.items, promises: matchPromisesStore.items)
            previousTabIndex = mainTabRouter.selectedTab
            tabEnterDate = Date()
            RealityMiningManager.shared.trackScreenView(name: tabItems[mainTabRouter.selectedTab].label)
        }
        .onChange(of: mainTabRouter.selectedTab) { newValue in
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

    /// 右フリック（強め）で Home に戻す。
    private var returnToHomeGesture: some Gesture {
        DragGesture(minimumDistance: 26, coordinateSpace: .local)
            .onEnded { value in
                guard mainTabRouter.selectedTab != 0 else { return }
                let movedRightFarEnough = value.translation.width >= 180
                let hasStrongRightVelocity = value.predictedEndTranslation.width >= 280
                if movedRightFarEnough || hasStrongRightVelocity {
                    returnToHome()
                }
            }
    }

    private func returnToHome() {
        withAnimation(.easeInOut(duration: 0.22)) {
            mainTabRouter.selectedTab = 0
        }
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
                Button(action: { mainTabRouter.selectedTab = index }) {
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
        .environmentObject(MatchPromisesStore())
        .environmentObject(PartnerMatchRequestsStore.shared)
        .environmentObject(PracticeRecruitmentsStore.shared)
        .environmentObject(CoachCertificationManager.shared)
        .environmentObject(TabBarVisibility())
}
