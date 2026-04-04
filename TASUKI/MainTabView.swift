import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int = 0
    @State private var previousTabIndex: Int = 0
    @State private var tabEnterDate: Date = Date()
    @State private var showReengagementSheet = false
    @State private var reengagementGapDays = 0
    @EnvironmentObject private var unreadProvider: UnreadCountProviderBase
    
    private let tabItems: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("figure.run", "Run"),
        ("person.3.fill", "EKIDEN"),
        ("magnifyingglass", "Find"),
        ("person.fill", "Me")
    ]
    
    var body: some View {
        Group {
            switch selectedTab {
            case 0:
                NavigationStack {
                    HomeView()
                        .environmentObject(unreadProvider)
                }
            case 1:
                SoloRunHubView()
            case 2:
                TeamView()
            case 3:
                FindView()
            case 4:
                MyProfileView()
            default:
                NavigationStack { HomeView().environmentObject(unreadProvider) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            customTabBar
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            previousTabIndex = selectedTab
            tabEnterDate = Date()
            RealityMiningManager.shared.trackScreenView(name: tabItems[selectedTab].label)
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
        .onChange(of: selectedTab) { newValue in
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
    
    private func tabLabelColor(index: Int) -> Color {
        selectedTab == index ? Color.tasukiOnBrandYellow : .black
    }

    @ViewBuilder
    private func tabBarIcon(systemName: String, index: Int) -> some View {
        if selectedTab == index {
            TasukiBrandOutlinedSymbol(systemName: systemName, size: 18, weight: .semibold)
        } else {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black)
        }
    }

    private func tabSelectionBackground(for index: Int) -> Color {
        selectedTab == index ? Color.tasukiTabSelectionFill : .clear
    }
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabItems.count, id: \.self) { index in
                Button(action: { selectedTab = index }) {
                    VStack(spacing: 2) {
                        tabBarIcon(systemName: tabItems[index].icon, index: index)
                        Text(tabItems[index].label)
                            .font(.system(size: 9, weight: selectedTab == index ? .semibold : .regular))
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
}
