import SwiftUI

struct ChallengeHubView: View {
    @ObservedObject private var activityStore = RunActivityStore.shared
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @State private var didPushTabBarHide = false
    @State private var challenges: [MonthlyChallenge] = []
    @State private var leaderboard: [ChallengeLeaderboardEntry] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                challengeList
                    .padding(.horizontal, 20)

                leaderboardSection
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
            }
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Challenges")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
        }
        .onAppear {
            if !didPushTabBarHide {
                didPushTabBarHide = true
                tabBarVisibility.pushHiddenContext()
            }
            refresh()
        }
        .onDisappear {
            if didPushTabBarHide {
                didPushTabBarHide = false
                tabBarVisibility.popHiddenContext()
            }
        }
        .onChange(of: activityStore.activities.count) { _, _ in
            refresh()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MONTHLY CHALLENGE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            Text("記録した走行から自動で進捗を計算します")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var challengeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(challenges.enumerated()), id: \.element.id) { index, challenge in
                if index > 0 {
                    Divider()
                        .background(Color.tasukiDarkCardSecondary)
                        .padding(.vertical, 12)
                }
                challengeBlock(challenge)
            }
        }
    }

    private func challengeBlock(_ challenge: MonthlyChallenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(challenge.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.black)
                Spacer()
                Text("+\(challenge.rewardPoints)pt")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(challenge.isCompleted ? Color.tasukiOnBrandYellow : Color.tasukiAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(challenge.isCompleted ? Color.tasukiPrimaryButtonFill : Color.tasukiAccent.opacity(0.12))
                    )
            }
            Text(challenge.description)
                .font(.footnote)
                .foregroundColor(Color.tasukiMutedText)
            ProgressView(value: challenge.progress)
                .tint(challenge.isCompleted ? Color.green : Color.tasukiAccent)
            HStack {
                Text("\(formatted(challenge.current)) / \(formatted(challenge.target)) \(challenge.unit)")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
                Spacer()
                if challenge.isCompleted {
                    Text("達成済み")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHALLENGE LEADERBOARD")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            Text("順位は参考程度に。自分のペースを最優先にしてください。")
                .font(.caption2)
                .foregroundColor(Color.tasukiMutedText)
            VStack(spacing: 0) {
                ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                            .background(Color.tasukiDarkCardSecondary.opacity(0.8))
                    }
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .frame(width: 22, alignment: .trailing)
                        Text(entry.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        Spacer()
                        Text("\(entry.score) pt")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.tasukiAccent)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tasukiDarkCardSecondary)
            )
        }
    }

    private func refresh() {
        let monthActivities = activityStore.activitiesInCurrentMonth()
        let newChallenges = ChallengeService.shared.currentMonthChallenges(from: monthActivities)
        ChallengeService.shared.awardPointsIfNeeded(challenges: newChallenges)
        challenges = newChallenges
        ChallengeService.shared.fetchLeaderboard(monthlyDistanceKm: activityStore.monthlyDistanceKm()) { fetched in
            DispatchQueue.main.async {
                leaderboard = fetched
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded(.down) == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

#Preview {
    NavigationStack {
        ChallengeHubView()
    }
    .environmentObject(TabBarVisibility())
}
