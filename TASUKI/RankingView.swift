import SwiftUI
import FirebaseFirestore
import FirebaseAuth

private enum RankingMode {
    case personal
    case team
}

private enum RankingPeriod {
    case total
    case monthly
}

private enum RankingFilter {
    case overall
    case sameRank
    case samePrefecture
}

/// ランキング画面（サンプルデータベース）
struct RankingView: View {
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @State private var didPushTabBarHide = false
    @State private var mode: RankingMode = .personal
    @State private var period: RankingPeriod = .total
    @State private var filter: RankingFilter = .overall
    @State private var remoteUsers: [User] = []
    @State private var remoteTeams: [SampleTeam] = []
    
    @AppStorage("myRank") private var myRank: String = "Rank B"
    @AppStorage("myName") private var myName: String = "Hiro"
    @AppStorage("myTeamId") private var myTeamId: String = ""
    
    // 地域フィルタ用（現状は東京都で固定に近い扱い）
    private var myPrefecture: String { "東京都" }
    
    private var personalSource: [User] {
        if !remoteUsers.isEmpty {
            return remoteUsers
        }
        var users = [mockUser] + mockUsers
        let myPoints = PointService.shared.currentTotalPoints()
        if myPoints > 0 {
            var me = mockUser
            me.totalPoints = myPoints
            me.monthlyPoints = PointService.shared.currentMonthlyPoints()
            users[0] = me
        }
        return users
    }
    
    private var teamSource: [SampleTeam] {
        if !remoteTeams.isEmpty {
            return remoteTeams
        }
        var teams = SampleTeam.samples
        if !myTeamId.isEmpty {
            let total = PointService.shared.teamTotalPoints(teamId: myTeamId)
            let monthly = PointService.shared.teamMonthlyPoints(teamId: myTeamId)
            let myTeam = SampleTeam(
                id: myTeamId,
                name: myTeamId == "example_owner" ? "皇居ランナーズ" : "皇居ランナーズ",
                prefecture: "東京都",
                memberCount: 5,
                totalPoints: total,
                monthlyPoints: monthly
            )
            if !teams.contains(where: { $0.id == myTeamId }) {
                teams.append(myTeam)
            }
        }
        return teams
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // モード切替（個人 / チーム）
            Picker("", selection: $mode) {
                Text("個人").tag(RankingMode.personal)
                Text("チーム").tag(RankingMode.team)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // 期間切替（累計 / 月間）
            Picker("", selection: $period) {
                Text("累計").tag(RankingPeriod.total)
                Text("月間").tag(RankingPeriod.monthly)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            
            // フィルター（全体 / ランク別 / 地域別）
            Picker("", selection: $filter) {
                Text("全体").tag(RankingFilter.overall)
                Text("ランク別").tag(RankingFilter.sameRank)
                Text("地域別").tag(RankingFilter.samePrefecture)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            
            Divider()
            
            if mode == .personal {
                personalRankingList
            } else {
                teamRankingList
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ランキング")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
        }
        .background(Color.tasukiDarkBackground)
        .onAppear {
            if !didPushTabBarHide {
                didPushTabBarHide = true
                tabBarVisibility.pushHiddenContext()
            }
            fetchRemoteRankingIfPossible()
        }
        .onDisappear {
            if didPushTabBarHide {
                didPushTabBarHide = false
                tabBarVisibility.popHiddenContext()
            }
        }
    }
    
    // MARK: - 個人ランキング
    
    private var filteredPersonalUsers: [User] {
        var users = personalSource
        
        // フィルタ適用
        switch filter {
        case .overall:
            break
        case .sameRank:
            users = users.filter { $0.rank == myRank }
        case .samePrefecture:
            users = users.filter { $0.prefecture == myPrefecture }
        }
        
        // 期間ごとに並び替え
        switch period {
        case .total:
            return users.sorted { $0.totalPoints > $1.totalPoints }
        case .monthly:
            return users.sorted { $0.monthlyPoints > $1.monthlyPoints }
        }
    }
    
    private var personalRankingList: some View {
        List(Array(filteredPersonalUsers.enumerated()), id: \.element.id) { index, user in
            let isMe = user.name == myName || (index == 0 && PointService.shared.currentTotalPoints() > 0)
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 32, alignment: .trailing)
                    .foregroundColor(Color.tasukiPrimary)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        if let tier = PointBadgeHelper.tier(forTotalPoints: user.totalPoints) {
                            HStack(spacing: 3) {
                                Image(systemName: tier.iconName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(tier.color)
                                Text(tier.displayName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(tier.color.opacity(0.12))
                            )
                        }
                        Text(user.rank)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.tasukiPrimary.opacity(0.06))
                            )
                    }
                    Text(user.prefecture)
                        .font(.system(size: 12))
                        .foregroundColor(Color.tasukiMutedText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    let points = (period == .total) ? user.totalPoints : user.monthlyPoints
                    Text("\(points)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text(period == .total ? "累計pt" : "月間pt")
                        .font(.system(size: 10))
                        .foregroundColor(Color.tasukiMutedText)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(isMe ? Color.tasukiAccent.opacity(0.12) : Color.clear)
        }
        .listStyle(.plain)
    }
    
    // MARK: - チームランキング（サンプル）
    
    private var filteredTeams: [SampleTeam] {
        var teams = teamSource
        
        switch filter {
        case .overall:
            break
        case .sameRank:
            // チームランク別（自チームがあればそのランクと同じもの）
            if let myTeamTier = teams.first?.tier {
                teams = teams.filter { $0.tier == myTeamTier }
            }
        case .samePrefecture:
            teams = teams.filter { $0.prefecture == myPrefecture }
        }
        
        switch period {
        case .total:
            return teams.sorted { $0.totalPoints > $1.totalPoints }
        case .monthly:
            return teams.sorted { $0.monthlyPoints > $1.monthlyPoints }
        }
    }
    
    private var teamRankingList: some View {
        List(Array(filteredTeams.enumerated()), id: \.element.id) { index, team in
            let isMyTeam = team.id == myTeamId
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 32, alignment: .trailing)
                    .foregroundColor(Color.tasukiPrimary)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(team.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        Text(team.tier.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(team.tier.color.opacity(0.12))
                            )
                    }
                    Text("\(team.prefecture) / \(team.memberCount)名")
                        .font(.system(size: 12))
                        .foregroundColor(Color.tasukiMutedText)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    let points = (period == .total) ? team.totalPoints : team.monthlyPoints
                    Text("\(points)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text(period == .total ? "累計pt" : "月間pt")
                        .font(.system(size: 10))
                        .foregroundColor(Color.tasukiMutedText)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(isMyTeam ? Color.tasukiAccent.opacity(0.12) : Color.clear)
        }
        .listStyle(.plain)
    }

    private func fetchRemoteRankingIfPossible() {
        guard Auth.auth().currentUser != nil else { return }
        let db = Firestore.firestore()

        db.collection("users")
            .order(by: "totalPoints", descending: true)
            .limit(to: 100)
            .getDocuments { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let mapped: [User] = docs.map { doc in
                    let data = doc.data()
                    let name = data["name"] as? String ?? "Runner"
                    let rank = data["rank"] as? String ?? "Rank B"
                    let prefecture = data["prefecture"] as? String ?? "東京都"
                    let total = data["totalPoints"] as? Int ?? 0
                    let monthly = data["monthlyPoints"] as? Int ?? 0
                    return User(
                        id: UUID(),
                        name: name,
                        profileImage: "runner",
                        profileImageUrl: nil,
                        bio: "",
                        rank: rank,
                        age: 20,
                        gender: "other",
                        purpose: "",
                        prefecture: prefecture,
                        area: prefecture,
                        pace: "5:30 /km",
                        runningFrequency: "",
                        personalBest: "",
                        schedule: "",
                        nextRace: "",
                        targetTime: "",
                        monthlyDistance: 0,
                        monthlyTarget: 0,
                        avgPace: "5:30 /km",
                        totalPoints: total,
                        monthlyPoints: monthly,
                        matchRate: 0,
                        lastLogin: Date(),
                        spotName: prefecture,
                        latitude: 0,
                        longitude: 0,
                        distanceFromUserMock: 0,
                        monthlyGpsActivityCount: nil
                    )
                }
                DispatchQueue.main.async {
                    remoteUsers = mapped
                }
            }

        db.collection("teams")
            .order(by: "teamTotalPoints", descending: true)
            .limit(to: 50)
            .getDocuments { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let mapped: [SampleTeam] = docs.map { doc in
                    let data = doc.data()
                    return SampleTeam(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "Team",
                        prefecture: data["prefecture"] as? String ?? "東京都",
                        memberCount: (data["members"] as? [String])?.count ?? 0,
                        totalPoints: data["teamTotalPoints"] as? Int ?? 0,
                        monthlyPoints: data["teamMonthlyPoints"] as? Int ?? 0
                    )
                }
                DispatchQueue.main.async {
                    remoteTeams = mapped
                }
            }
    }
}

// MARK: - サンプルチームモデル

private struct SampleTeam: Identifiable {
    let id: String
    let name: String
    let prefecture: String
    let memberCount: Int
    let totalPoints: Int
    let monthlyPoints: Int
    
    var tier: TeamRankTier {
        TeamRankTier.tier(forTeamPoints: totalPoints)
    }
    
    static let samples: [SampleTeam] = [
        SampleTeam(
            id: "team-1",
            name: "皇居ランナーズ",
            prefecture: "東京都",
            memberCount: 8,
            totalPoints: 5200,
            monthlyPoints: 800
        ),
        SampleTeam(
            id: "team-2",
            name: "代々木モーニングクラブ",
            prefecture: "東京都",
            memberCount: 5,
            totalPoints: 3100,
            monthlyPoints: 600
        ),
        SampleTeam(
            id: "team-3",
            name: "大阪城ナイトラン",
            prefecture: "大阪府",
            memberCount: 10,
            totalPoints: 7800,
            monthlyPoints: 1200
        )
    ]
}

