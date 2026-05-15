import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MyProfileView: View {
    @AppStorage("myName") private var name: String = "Hiro"
    @AppStorage("myArea") private var area: String = "Tokyo, Setagaya"
    @AppStorage("myRank") private var rank: String = "Rank A"
    @AppStorage("myPurpose") private var purpose: String = "サブ3, 健康維持"
    @AppStorage("myRunningSpots") private var runningSpots: String = "皇居, 代々木公園"
    @AppStorage("mySchedule") private var schedule: String = "平日夜, 土日午前"
    @AppStorage("myPersonalBest") private var personalBest: String = "Full 3:10:00"
    @AppStorage("myTargetTime") private var targetTime: String = "Full 2:59:00"
    @AppStorage("myNextRace") private var nextRace: String = "東京マラソン2026"
    @AppStorage("myMonthlyDist") private var monthlyDist: String = "150km"
    @AppStorage("myTotalPoints") private var myTotalPoints: Int = 0
    @AppStorage("myBio") private var bio: String = "平日は仕事終わりに5-10km走ってます！週末は距離走やりたいです。"
    @AppStorage("reduceRankingPressure") private var reduceRankingPressure: Bool = false

    @State private var userUUID: String = ""
    @State private var showCopiedToast: Bool = false
    @ObservedObject private var activityStore = RunActivityStore.shared
    @EnvironmentObject private var coachCertification: CoachCertificationManager

    private var myBadgeTier: PointBadgeTier? {
        PointBadgeHelper.tier(forTotalPoints: myTotalPoints)
    }

    /// 今月の Run 記録から算出（暦月でリセット）。
    private var monthlyAveragePaceDisplay: String {
        activityStore.monthlyAveragePaceDisplayLabel()
    }

    private var runningSpotTags: [String] {
        runningSpots.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var sameRankUsers: [User] {
        var users = [mockUser] + mockUsers
        var me = users[0]
        me.rank = rank
        me.totalPoints = PointService.shared.currentTotalPoints()
        users[0] = me
        return users
            .filter { $0.rank == rank }
            .sorted { $0.totalPoints > $1.totalPoints }
    }

    private var sameRankPosition: Int {
        guard let idx = sameRankUsers.firstIndex(where: { $0.id == mockUser.id }) else { return 1 }
        return idx + 1
    }

    private var sameRankTotal: Int {
        max(sameRankUsers.count, 1)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        TasukiBrandedHeroHeader(title: "My Profile", compactToolbarStyle: true, compactTitleTracking: 3)
                        VStack(spacing: 0) {
                            heroSection
                                .padding(.bottom, 28)
                            if coachCertification.isCertifiedCoach {
                                certifiedCoachSection
                                    .padding(.bottom, 28)
                            }
                            activitySection
                                .padding(.bottom, 28)
                            statsSection
                                .padding(.bottom, 28)
                            profileSection
                                .padding(.bottom, 28)
                            aboutSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ProfileEditView()) {
                        Image(systemName: "pencil")
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
            }
            .task {
                // #region agent log
                AgentDebugLog.log(
                    location: "MyProfileView.task",
                    message: "task_start_before_loadUserUUID",
                    hypothesisId: "H2",
                    data: [:]
                )
                // #endregion
                loadUserUUID()
            }
            .onAppear {
                activityStore.refreshFromRemote()
                // #region agent log
                AgentDebugLog.log(
                    location: "MyProfileView.onAppear",
                    message: "navigationStack_onAppear",
                    hypothesisId: "H1",
                    data: [
                        "isCertifiedCoach": "\(coachCertification.isCertifiedCoach)"
                    ]
                )
                // #endregion
            }
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Text("UUIDをコピーしました")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.8)))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                        .transition(.opacity)
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 96))
                .foregroundColor(.black)
                .frame(width: 140, height: 140)

            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
                if let tier = myBadgeTier {
                    HStack(spacing: 4) {
                        Image(systemName: tier.iconName)
                        Text(tier.displayName)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                }
            }

            Text(rank)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)

            HStack(spacing: 5) {
                Text("保有ポイント")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                Text("\(PointService.shared.currentTotalPoints())pt")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
            }

            HStack(spacing: 8) {
                Text(userUUID.isEmpty ? "—" : userUUID)
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    guard !userUUID.isEmpty else { return }
                    UIPasteboard.general.string = userUUID
                    withAnimation(.easeInOut(duration: 0.2)) { showCopiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) { showCopiedToast = false }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.black)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("RUNNING STATS")
            
            HStack(spacing: 12) {
                statItem(title: "Avg Pace (月)", value: monthlyAveragePaceDisplay)
                statItem(title: "Monthly Dist", value: monthlyDist)
            }

            sectionEyebrow("RUN RECORDER")

            HStack(spacing: 12) {
                statItem(title: "記録 今月回数", value: "\(activityStore.tasukiRecorderMonthlyRunCount()) 回")
                statItem(title: "記録 今月 km", value: String(format: "%.1f km", activityStore.tasukiRecorderMonthlyDistanceKm()))
            }
            HStack(spacing: 12) {
                statItem(title: "平均ペース（記録・月）", value: activityStore.tasukiRecorderMonthlyAveragePaceDisplayLabel())
                statItem(title: "移動ペース（記録・月）", value: activityStore.tasukiRecorderMonthlyAverageMovingPaceDisplayLabel())
            }
            HStack(spacing: 12) {
                statItem(title: "GAP（記録・月）", value: activityStore.tasukiRecorderMonthlyGapPaceDisplayLabel())
                statItem(title: "平均速度（記録・月）", value: activityStore.tasukiRecorderMonthlyAverageSpeedDisplayLabel())
            }
            HStack(spacing: 12) {
                statItem(title: "平均ケイデンス", value: activityStore.tasukiRecorderMonthlyAverageCadenceDisplayLabel())
                statItem(title: "最高ケイデンス（月）", value: activityStore.tasukiRecorderMonthlyMaxCadenceDisplayLabel())
            }
            HStack(spacing: 12) {
                statItem(title: "推定ストライド", value: activityStore.tasukiRecorderMonthlyAverageStrideDisplayLabel())
                statItem(title: "累積上昇（記録・月）", value: activityStore.tasukiRecorderMonthlyTotalAscentDisplayLabel())
            }
            HStack(spacing: 12) {
                statItem(title: "消費 kcal（記録・月）", value: activityStore.tasukiRecorderMonthlyTotalCaloriesDisplayLabel())
                statItem(
                    title: "累計（記録）",
                    value: "\(activityStore.tasukiRecorderAllTimeRunCount()) 回 · \(String(format: "%.1f km", activityStore.tasukiRecorderAllTimeDistanceKm()))"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var certifiedCoachPublicName: String {
        let n = coachCertification.coachProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? CoachProfileCatalog.profile(for: "廣 佳樹").name : n
    }

    private var certifiedCoachSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("認定コーチ")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.black)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                NavigationLink(destination: CoachProfileView(coachName: certifiedCoachPublicName)) {
                    TasukiFlatHubRow(
                        title: "公開コーチプロフィール",
                        subtitle: "ランナーに表示される画面を確認",
                        systemImage: "person.crop.circle.badge.checkmark",
                        iconForegroundColor: Color.tasukiAccent
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(destination: CoachPendingQuestionsView()) {
                    TasukiFlatHubRow(
                        title: "Q&A に回答",
                        subtitle: "ユーザーからの質問へ返信",
                        systemImage: "text.bubble.fill",
                        iconForegroundColor: Color(hex: "2E7D32")
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity")
                .font(.system(size: 14, weight: .bold))
                .tracking(1.1)
                .foregroundColor(.black)

            HStack(spacing: 14) {
                graphStatActivity(title: "今週距離", value: String(format: "%.1f km", activityStore.weeklyDistanceKm()))
                graphStatActivity(title: "今週回数", value: "\(activityStore.weeklyRunCount()) 回")
                graphStatActivity(title: "今月距離", value: String(format: "%.1f km", activityStore.monthlyDistanceKm()))
            }

            TasukiWeeklyActivityLineChart(points: activityStore.weeklyActivityChartPoints())
                .frame(height: 190)
                .padding(.horizontal, 4)
                .onAppear {
                    // #region agent log
                    let pts = activityStore.weeklyActivityChartPoints()
                    AgentDebugLog.log(
                        location: "MyProfileView.activitySection.chart",
                        message: "chart_onAppear",
                        hypothesisId: "H4",
                        data: [
                            "pointCount": "\(pts.count)"
                        ]
                    )
                    // #endregion
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("PROFILE")

            if !reduceRankingPressure {
                NavigationLink(destination: RankingView()) {
                    TasukiFlatHubRow(
                        title: "RANKING",
                        subtitle: "総合ランキング · 現在 \(rank) · 同ランク内 \(sameRankPosition)/\(sameRankTotal)（参考）",
                        systemImage: "crown.fill",
                        iconFontSize: 20,
                        hStackSpacing: 12,
                        titleSubtitleSpacing: 4
                    )
                }
                .buttonStyle(.plain)
            }

            HStack {
                Image(systemName: "mappin.and.ellipse")
                Text(area)
            }
            .font(.subheadline)
            .foregroundColor(.black)

            if !purpose.isEmpty {
                tagView(text: purpose, isPrimary: true)
            }

            if !runningSpotTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(runningSpotTags, id: \.self) { spot in
                        tagView(text: spot, isPrimary: false)
                    }
                }
            }

            VStack(spacing: 0) {
                infoRow(icon: "trophy.fill", title: "Personal Best", value: personalBest)
                infoRow(icon: "calendar", title: "Schedule", value: schedule)
                if !nextRace.isEmpty {
                    infoRow(icon: "flag.fill", title: "Next Race", value: nextRace)
                }
                if !targetTime.isEmpty {
                    infoRow(icon: "scope", title: "Target", value: targetTime)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionEyebrow("ABOUT ME")
            Text(bio)
                .font(.system(size: 15))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.black)
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func graphStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func graphStatActivity(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagView(text: String, isPrimary: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
            .foregroundColor(.black)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func loadUserUUID() {
        // #region agent log
        AgentDebugLog.log(
            location: "MyProfileView.loadUserUUID",
            message: "entry",
            hypothesisId: "H2",
            data: ["hasAuthUser": "\(Auth.auth().currentUser != nil)"]
        )
        // #endregion
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        db.collection("users").document(firebaseUser.uid).getDocument { snapshot, _ in
            // #region agent log
            let hasId = snapshot?.data()?["id"] as? String != nil
            AgentDebugLog.log(
                location: "MyProfileView.loadUserUUID",
                message: "firestore_callback",
                hypothesisId: "H2",
                data: [
                    "hasSnapshot": "\(snapshot != nil)",
                    "hasIdField": "\(hasId)"
                ]
            )
            // #endregion
            if let data = snapshot?.data(), let idString = data["id"] as? String {
                DispatchQueue.main.async {
                    self.userUUID = idString
                }
            }
        }
    }

}

#Preview {
    MyProfileView()
        .environmentObject(AuthManager())
        .environmentObject(CoachCertificationManager.shared)
}
