import SwiftUI

struct ChallengeHubView: View {
    @ObservedObject private var activityStore = RunActivityStore.shared
    @State private var challenges: [MonthlyChallenge] = []
    @State private var leaderboard: [ChallengeLeaderboardEntry] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                challengeList
                leaderboardCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: activityStore.activities.count) { _, _ in
            refresh()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MONTHLY CHALLENGE")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.5)
                .foregroundColor(Color.tasukiMutedText)
            Text("記録した走行から自動で進捗を計算します")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tasukiCard()
    }

    private var challengeList: some View {
        VStack(spacing: 10) {
            ForEach(challenges) { challenge in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(challenge.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
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
                    if !challenge.isCompleted {
                        Text("未達の日があっても問題ありません。休む判断やペース調整も練習の一部です。")
                            .font(.caption2)
                            .foregroundColor(Color.tasukiMutedText.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tasukiCard()
            }
        }
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHALLENGE LEADERBOARD")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
            Text("順位は参考程度に。自分のペースを最優先にしてください。")
                .font(.caption2)
                .foregroundColor(Color.tasukiMutedText)
            ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, entry in
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
                .padding(.vertical, 3)
            }
        }
        .tasukiCard()
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
}
