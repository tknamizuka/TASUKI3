//
//  TeamView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Team Member Model
struct TeamMember: Identifiable {
    let id = UUID()
    let name: String
    let avatarImage: String?
    let currentDistance: Double  // km
    let targetDistance: Double  // km
    let condition: Condition
    let statusMessage: String
}

// MARK: - Team Chat Model
struct TeamChatMessage: Identifiable {
    let id = UUID()
    let memberName: String
    let message: String
    let timestamp: Date
}

/// 区間提出シート用。`sheet(isPresented:)` と optional の組み合わせでは中身が空になることがあるため `sheet(item:)` で渡す。
private struct EkidenSubmitSheetItem: Identifiable {
    let id: String
    let leg: EkidenLeg
    let state: EkidenViewState

    init(leg: EkidenLeg, state: EkidenViewState) {
        self.leg = leg
        self.state = state
        self.id = "\(state.event.id)-leg-\(leg.id)"
    }
}

// MARK: - Team View
struct TeamView: View {
    private let maxTeamMembers = 10
    var useMockTeamFlow: Bool = false
    @State private var userTeamId: String? = nil
    @State private var selectedTeamId: String = ""
    @State private var showTeamDetail: Bool = false
    @State private var showJoinCreate: Bool = false
    
    // 自分のデータ管理
    @AppStorage("myCondition") private var myConditionRaw: String = Condition.good.rawValue
    @AppStorage("myStatusMessage") private var myStatusMessage: String = "今月も頑張ります！"
    @AppStorage("myName") private var myName: String = "Hiro"
    
    // コンディション更新シート
    @State private var showConditionSheet = false
    @State private var selectedCondition: Condition = .good
    
    // チームチャットシート
    @State private var showTeamChatSheet = false
    
    // オーナーかどうか（メンバー管理の表示用）
    @State private var isTeamOwner: Bool = false
    
    // 駅伝イベント状態（MVP UI）
    @State private var ekidenViewState: EkidenViewState? = nil
    /// `.sheet(isPresented:)` + optional だと内容が空の白シートになることがあるため `item` で提示する
    @State private var ekidenSubmitSheetItem: EkidenSubmitSheetItem? = nil
    @State private var showEkidenResultView = false
    @State private var ekidenSubstituteSheetItem: EkidenSubmitSheetItem? = nil
    @State private var showPassTasukiConfirm = false
    @State private var passTasukiLegIndex: Int? = nil
    @State private var isPassingTasuki = false
    
    // チーム情報
    @State private var teamName: String = "皇居ランナーズ"
    @State private var league: String = "Gold League"
    @State private var rank: String = "3rd Place"
    
    // 目標と進捗
    @State private var targetDistance: Double = 500.0  // km
    @State private var currentDistance: Double = 325.0  // km
    
    // 自分のコンディションを取得
    private var myCondition: Condition {
        Condition(rawValue: myConditionRaw) ?? .good
    }
    
    // メンバー（自分を含む）
    private var members: [TeamMember] {
        var allMembers: [TeamMember] = [
            TeamMember(name: "Kenji_Run", avatarImage: "person.circle.fill", currentDistance: 85.0, targetDistance: 100.0, condition: .excellent, statusMessage: "調子が良い！今月は200km走る目標です🔥"),
            TeamMember(name: "さっちゃん", avatarImage: "person.circle.fill", currentDistance: 72.0, targetDistance: 100.0, condition: .good, statusMessage: "今月も頑張ります！週3回のペースで走ってます"),
            TeamMember(name: "Taka@Sub3", avatarImage: "person.circle.fill", currentDistance: 68.0, targetDistance: 100.0, condition: .good, statusMessage: "週末の朝ランが楽しみです！"),
            TeamMember(name: "Momo", avatarImage: "person.circle.fill", currentDistance: 65.0, targetDistance: 100.0, condition: .tired, statusMessage: "最近忙しくて疲れ気味...でも走りたい！"),
            TeamMember(name: "Runner123", avatarImage: "person.circle.fill", currentDistance: 35.0, targetDistance: 100.0, condition: .sos, statusMessage: "足を痛めてしまいました...しばらく休みます💦"),
            TeamMember(name: "Yuki", avatarImage: "person.circle.fill", currentDistance: 58.0, targetDistance: 100.0, condition: .good, statusMessage: "ペースはゆっくり、距離を積み上げていきます")
        ]
        
        // 自分を先頭に追加
        let myMember = TeamMember(
            name: myName,
            avatarImage: "person.circle.fill",
            currentDistance: 80.0,
            targetDistance: 100.0,
            condition: myCondition,
            statusMessage: myStatusMessage
        )
        allMembers.insert(myMember, at: 0)
        
        return Array(allMembers.prefix(maxTeamMembers))
    }
    
    // チームチャット
    // 注: TeamMessageモデルが別ファイルで定義されている前提です。mockTeamMessagesがない場合は空配列で初期化します。
    @State private var teamMessages: [TeamMessage] = []
    
    var progressPercentage: Double {
        guard targetDistance > 0 else { return 0 }
        return min(currentDistance / targetDistance, 1.0) * 100
    }
    
    /// メインタブバーとの干渉を緩和する ScrollView 下端の余白
    private let scrollContentBottomPadding: CGFloat = 80
    /// 右上チャット FAB とカード内の順位・pt 表示が重ならないように確保する幅
    private let teamViewChatFABReserveWidth: CGFloat = 64
    
    @ViewBuilder
    private var conditionRecordButton: some View {
        Button(action: {
            selectedCondition = myCondition
            showConditionSheet = true
        }) {
            HStack {
                Spacer()
                Text("調子を記録する")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.tasukiAccentOrange)
            )
        }
    }
    
    // 今月の月末日を取得
    var monthEndDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        var dateComponents = DateComponents()
        dateComponents.year = components.year
        dateComponents.month = components.month
        dateComponents.day = calendar.range(of: .day, in: .month, for: now)?.count
        return calendar.date(from: dateComponents) ?? now
    }
    
    // 残り日数を計算
    var remainingDays: Int {
        let calendar = Calendar.current
        let now = Date()
        let days = calendar.dateComponents([.day], from: now, to: monthEndDate).day ?? 0
        return max(0, days)
    }
    
    // 日付フォーマット
    var monthEndDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: monthEndDate)
    }
    
    /// 本番かつ未ログインでは EKIDEN チームフローをサンプル（モック）で動かす
    private var isSampleTeamFlow: Bool {
        useMockTeamFlow || Auth.auth().currentUser == nil
    }
    
    var body: some View {
        NavigationStack {
            if userTeamId == nil {
                // 未所属の場合、チーム参加/作成画面を表示
                TeamJoinCreateView(onComplete: { teamId in
                    if isSampleTeamFlow {
                        self.userTeamId = teamId
                        if let id = teamId {
                            UserDefaults.standard.set(id, forKey: "myTeamId")
                        }
                    } else {
                        loadUserTeamId()
                    }
                    if let id = teamId {
                        self.selectedTeamId = id
                        self.showTeamDetail = true
                    }
                }, useMockFlow: isSampleTeamFlow)
                .navigationTitle("EKIDEN MODE")
                .navigationBarTitleDisplayMode(.large)
            } else {
                ZStack {
                    Color.tasukiDarkBackground
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            Group {
                                if let ekiden = ekidenViewState {
                                    ekidenProgressCard(ekiden, isReadOnly: !ekiden.isWithinEventWindow)
                                } else {
                                    progressView
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            
                            if let ekiden = ekidenViewState {
                                conditionRecordButton
                                    .padding(.horizontal, 20)
                                ekidenLegListView(ekiden, allowSubmit: ekiden.isWithinEventWindow)
                                    .padding(.horizontal, 20)
                            } else {
                                slimMemberListView
                                    .padding(.horizontal, 20)
                            }
                            
                            // オーナーのみ: メンバー管理（参加申請・チーム詳細）へ
                            if isTeamOwner {
                                Button(action: { showTeamDetail = true }) {
                                    HStack {
                                        Spacer()
                                        Text("メンバー管理")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.tasukiAccentOrange)
                                    )
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                        }
                        .padding(.bottom, scrollContentBottomPadding)
                    }
                    
                    NavigationLink(destination: TeamDetailView(teamId: selectedTeamId), isActive: $showTeamDetail) {
                        EmptyView()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button(action: { showTeamChatSheet = true }) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.tasukiAccentOrange))
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 20)
                }
                .navigationTitle("EKIDEN MODE")
                .navigationBarTitleDisplayMode(.large)
                .sheet(isPresented: $showConditionSheet) {
                    ConditionUpdateSheet(
                        selectedCondition: $selectedCondition,
                        onSave: {
                            let oldCondition = myCondition
                            myConditionRaw = selectedCondition.rawValue
                            
                            if oldCondition != selectedCondition {
                                addSystemMessage(condition: selectedCondition)
                            }
                            
                            showConditionSheet = false
                        },
                        onCancel: {
                            showConditionSheet = false
                        }
                    )
                }
                .sheet(isPresented: $showTeamChatSheet) {
                    TeamChatSheetView(
                        teamId: selectedTeamId,
                        isSampleTeam: isSampleTeamFlow || selectedTeamId.hasPrefix("example_"),
                        teamMessages: $teamMessages,
                        myName: myName,
                        myCondition: myCondition,
                        myStatusMessage: myStatusMessage
                    )
                }
                .sheet(item: $ekidenSubstituteSheetItem) { item in
                    EkidenSubstituteSheet(
                        leg: item.leg,
                        state: item.state,
                        teamId: selectedTeamId,
                        entryId: item.state.entry.id,
                        isSampleTeam: isSampleTeamFlow || selectedTeamId.hasPrefix("example"),
                        onDismiss: {
                            ekidenSubstituteSheetItem = nil
                        },
                        onSuccess: {
                            Task { await loadEkidenState(teamId: selectedTeamId) }
                        }
                    )
                }
                .sheet(isPresented: $showEkidenResultView) {
                    if let state = ekidenViewState {
                        EkidenResultView(state: state, teamId: selectedTeamId, onDismiss: {
                            showEkidenResultView = false
                        })
                    }
                }
                .sheet(item: $ekidenSubmitSheetItem) { item in
                    EkidenLegSubmitSheet(
                        leg: item.leg,
                        state: item.state,
                        teamId: selectedTeamId,
                        isSampleTeam: isSampleTeamFlow || selectedTeamId.hasPrefix("example"),
                        onDismiss: {
                            ekidenSubmitSheetItem = nil
                        },
                        onSuccess: {
                            Task { await loadEkidenState(teamId: selectedTeamId) }
                        }
                    )
                }
                .onAppear {
                    selectedCondition = myCondition
                    if !isSampleTeamFlow {
                        loadUserTeamId()
                    }
                    if let tid = userTeamId, !tid.isEmpty {
                        loadTeamOwner(teamId: tid)
                        Task { await loadEkidenState(teamId: tid) }
                    }
                }
                .onChange(of: userTeamId) { _, newId in
                    if let tid = newId, !tid.isEmpty {
                        loadTeamOwner(teamId: tid)
                        Task { await loadEkidenState(teamId: tid) }
                    } else {
                        isTeamOwner = false
                        ekidenViewState = nil
                    }
                }
                .onChange(of: selectedTeamId) { _, newId in
                    if !newId.isEmpty {
                        Task { await loadEkidenState(teamId: newId) }
                    } else {
                        ekidenViewState = nil
                    }
                }
                .alert("TASUKIをつなぐ", isPresented: $showPassTasukiConfirm) {
                    Button("キャンセル", role: .cancel) {
                        passTasukiLegIndex = nil
                    }
                    Button("つなぐ", role: .none) {
                        performPassTasuki()
                    }
                } message: {
                    Text("走らずにTASUKIだけ次の担当へ渡します。距離は加算されません。")
                }
            }
        }
        .onAppear {
            if userTeamId == nil, isSampleTeamFlow, let savedId = UserDefaults.standard.string(forKey: "myTeamId"), !savedId.isEmpty {
                userTeamId = savedId
                selectedTeamId = savedId
            }
        }
    } // body の閉じ (修正箇所)

    private func loadUserTeamId() {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        db.collection("users").document(firebaseUser.uid).getDocument { snapshot, error in
            if let data = snapshot?.data(), let teamId = data["teamId"] as? String {
                DispatchQueue.main.async {
                    self.userTeamId = teamId
                }
            } else {
                DispatchQueue.main.async {
                    self.userTeamId = nil
                }
            }
        }
    }
    
    /// 駅伝イベント状態を取得
    private func loadEkidenState(teamId: String) async {
        let isSample = isSampleTeamFlow || teamId.hasPrefix("example")
        let state = await EkidenDataService.shared.loadEkidenState(teamId: teamId, isSampleTeam: isSample)
        await MainActor.run {
            ekidenViewState = state
        }
    }
    
    /// TASUKIをつなぐ（TASUKIだけ次へ、距離加算なし）
    private func performPassTasuki() {
        guard let legIndex = passTasukiLegIndex,
              let state = ekidenViewState else {
            showPassTasukiConfirm = false
            passTasukiLegIndex = nil
            return
        }
        let leg = state.legs.first { $0.id == legIndex }
        let submittedByUid: String? = isSampleTeamFlow
            ? leg?.assignedUid
            : Auth.auth().currentUser?.uid
        guard let uid = submittedByUid else {
            showPassTasukiConfirm = false
            passTasukiLegIndex = nil
            return
        }
        let teamId = selectedTeamId
        let entryId = state.entry.id
        let isSample = isSampleTeamFlow || teamId.hasPrefix("example")
        showPassTasukiConfirm = false
        passTasukiLegIndex = nil
        isPassingTasuki = true
        Task {
            let result = await EkidenDataService.shared.passTasuki(
                teamId: teamId,
                entryId: entryId,
                legIndex: legIndex,
                totalLegCount: state.event.legCount,
                submittedByUid: uid,
                isSampleTeam: isSample
            )
            await MainActor.run {
                isPassingTasuki = false
                if case .success = result {
                    Task { await loadEkidenState(teamId: teamId) }
                }
            }
        }
    }
    
    /// チームのオーナーかどうかを取得（メンバー管理ボタン表示用）
    private func loadTeamOwner(teamId: String) {
        // サンプルチーム: example_owner のときだけオーナー
        if teamId == "example_owner" || teamId == "example_member" {
            isTeamOwner = (teamId == "example_owner")
            return
        }
        guard let currentUid = Auth.auth().currentUser?.uid else {
            isTeamOwner = false
            return
        }
        let db = Firestore.firestore()
        db.collection("teams").document(teamId).getDocument { snapshot, _ in
            guard let data = snapshot?.data(), let ownerUid = data["ownerUid"] as? String else {
                DispatchQueue.main.async { self.isTeamOwner = false }
                return
            }
            DispatchQueue.main.async {
                self.isTeamOwner = (ownerUid == currentUid)
            }
        }
    }
    
    // MARK: - Ekiden Progress Card（駅伝進行カード）
    private func ekidenProgressCard(_ state: EkidenViewState, isReadOnly: Bool = false) -> some View {
        let calendar = Calendar.current
        let now = Date()
        let remainingDays = max(0, calendar.dateComponents([.day], from: now, to: state.event.endAt).day ?? 0)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "M/d"
        let startStr = dateFormatter.string(from: state.event.startAt)
        let endStr = dateFormatter.string(from: state.event.endAt)
        
        let currentLegIndex = state.entry.currentLegIndex
        let legProgress: Double
        let progressCaption: String
        if state.isCumulativeMode {
            legProgress = state.teamGoalKm > 0 ? min(1.0, state.cumulativeDistanceKm / state.teamGoalKm) * 100 : 0
            progressCaption = String(format: "チーム累計 %.1f / %.0f km", state.cumulativeDistanceKm, state.teamGoalKm)
        } else {
            legProgress = state.event.legCount > 0 ? Double(state.submittedLegCount) / Double(state.event.legCount) * 100 : 0
            progressCaption = "\(state.submittedLegCount)/\(state.event.legCount) 区間"
        }
        
        return VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(teamName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !selectedTeamId.isEmpty {
                    let total = PointService.shared.teamTotalPoints(teamId: selectedTeamId)
                    let tier = TeamRankTier.tier(forTeamPoints: total)
                    Text(tier.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(tier.color.opacity(0.2)))
                        .foregroundColor(tier.color)
                }
                Spacer()
                if let rank = state.provisionalRank {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("暫定 \(rank)位")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.tasukiAccentOrange)
                        Text(state.totalTeams > 0 ? "/\(state.totalTeams)チーム" : "")
                            .font(.system(size: 10))
                            .foregroundColor(Color.tasukiMutedText)
                    }
                    .padding(.trailing, teamViewChatFABReserveWidth)
                }
            }
            .padding(.bottom, 4)
            
            // イベント期間（1行）
            HStack(spacing: 8) {
                Text(isReadOnly
                     ? "期間 \(startStr) 〜 \(endStr)（閲覧のみ）"
                     : "期間 \(startStr) 〜 \(endStr)（あと\(remainingDays)日）")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.tasukiPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isReadOnly {
                    Text("期間外")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.tasukiMutedText.opacity(0.3)))
                        .foregroundColor(Color.tasukiMutedText)
                }
                Spacer(minLength: 0)
            }
            
            // 区間進行
            HStack(spacing: 4) {
                Text("現在")
                    .font(.system(size: 12))
                    .foregroundColor(Color.tasukiMutedText)
                Text("\(min(currentLegIndex + 1, state.event.legCount))区")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.tasukiAccentOrange)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                        .frame(height: 20)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "2E5CFF"),
                                    Color.tasukiAccentOrange
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(min(legProgress / 100, 1.0)), height: 20)
                }
            }
            .frame(height: 20)
            
            Text(progressCaption)
                .font(.system(size: 12))
                .foregroundColor(Color.tasukiMutedText)
            
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 4),
                    count: max(1, state.event.legCount)
                ),
                spacing: 4
            ) {
                ForEach(0..<state.event.legCount, id: \.self) { i in
                    let leg = state.legs.first { $0.id == i }
                    let isDone = leg?.status == .submitted
                    let isCurrent = leg?.status == .ready
                    HStack(spacing: 2) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : (isCurrent ? "figure.run" : "circle"))
                            .font(.system(size: 12))
                            .foregroundColor(isDone ? Color(hex: "34C759") : (isCurrent ? Color.tasukiAccentOrange : Color.tasukiMutedText))
                        Text("\(i + 1)区")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundColor(isDone || isCurrent ? Color.tasukiPrimary : Color.tasukiMutedText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            
            // TASUKI受け渡し
            if let name = state.nextRunnerName(), state.legs.contains(where: { $0.status == .ready }) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14))
                        .foregroundColor(Color.tasukiAccentOrange)
                    Text("TASUKI:\(name)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text("（提出可能）")
                        .font(.system(size: 12))
                        .foregroundColor(Color.tasukiMutedText)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.tasukiAccentOrange.opacity(0.15))
                )
            } else {
                let lastSubmitted = state.legs.last { $0.status == .submitted }
                let nextLeg = state.legs.first { $0.status == .awaitingTasuki }
                if let next = nextLeg, let uid = next.assignedUid, let name = state.memberNames[uid] {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundColor(Color.tasukiMutedText)
                        Text("次走者: \(name)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.tasukiMutedText)
                    }
                } else if lastSubmitted != nil && state.submittedLegCount >= state.event.legCount {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "34C759"))
                        Text("全区間完了")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
            }
            
            // 累積タイム＆リザルト
            HStack {
                if state.totalElapsedSeconds > 0 {
                    HStack(spacing: 8) {
                        Text("累計タイム")
                            .font(.system(size: 12))
                            .foregroundColor(Color.tasukiMutedText)
                        Text(EkidenViewState.formatElapsed(state.totalElapsedSeconds))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
                Spacer()
                Button(action: { showEkidenResultView = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.doc.horizontal")
                        Text("リザルト")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiAccentOrange)
                }
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tasukiDarkCard)
        )
    }
    
    // MARK: - Ekiden Leg List View（区間担当行）
    private func ekidenLegListView(_ state: EkidenViewState, allowSubmit: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("区間担当")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Spacer()
                Text("\(state.legs.count)区間")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText)
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(state.legs, id: \.id) { leg in
                    ekidenLegRowView(
                        leg: leg,
                        state: state,
                        teamId: selectedTeamId,
                        isSampleTeam: isSampleTeamFlow || selectedTeamId.hasPrefix("example"),
                        allowSubmit: allowSubmit,
                        isTeamOwner: isTeamOwner,
                        onTapSubmit: {
                            ekidenSubmitSheetItem = EkidenSubmitSheetItem(leg: leg, state: state)
                        },
                        onTapSubstitute: {
                            ekidenSubstituteSheetItem = EkidenSubmitSheetItem(leg: leg, state: state)
                        },
                        onTapPassTasuki: {
                            passTasukiLegIndex = leg.id
                            showPassTasukiConfirm = true
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiDarkCard)
        )
    }
    
    private func ekidenLegRowView(leg: EkidenLeg, state: EkidenViewState, teamId: String, isSampleTeam: Bool, allowSubmit: Bool = true, isTeamOwner: Bool = false, onTapSubmit: @escaping () -> Void, onTapSubstitute: @escaping () -> Void = {}, onTapPassTasuki: (() -> Void)? = nil) -> some View {
        let name = leg.assignedUid.flatMap { state.memberNames[$0] } ?? "未割当"
        let statusText: String
        let statusColor: Color
        let icon: String
        switch leg.status {
        case .submitted:
            let timeStr = leg.elapsedSeconds.map { EkidenViewState.formatElapsed($0) } ?? "—"
            if let km = leg.actualDistanceKm {
                statusText = String(format: "%.1fkm · %@", km, timeStr)
            } else {
                statusText = timeStr
            }
            statusColor = Color(hex: "34C759")
            icon = "checkmark.circle.fill"
        case .ready:
            statusText = "提出可能"
            statusColor = Color.tasukiAccentOrange
            icon = "figure.run"
        case .awaitingTasuki:
            statusText = "TASUKI待ち"
            statusColor = Color.tasukiMutedText
            icon = "clock"
        }
        let canSubmit = allowSubmit && leg.status == .ready && (isSampleTeam || (leg.assignedUid != nil && leg.assignedUid == Auth.auth().currentUser?.uid))
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(leg.id + 1)区")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .frame(width: 32, alignment: .leading)
                
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.tasukiPrimary)
                    .saturation(0)
                
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(statusColor)
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ekidenLegActionButtons(
                        leg: leg,
                        canSubmit: canSubmit,
                        allowSubmit: allowSubmit,
                        isTeamOwner: isTeamOwner,
                        substituteButtonFullWidth: false,
                        onTapSubmit: onTapSubmit,
                        onTapSubstitute: onTapSubstitute,
                        onTapPassTasuki: onTapPassTasuki
                    )
                }
                VStack(spacing: 8) {
                    ekidenLegActionButtons(
                        leg: leg,
                        canSubmit: canSubmit,
                        allowSubmit: allowSubmit,
                        isTeamOwner: isTeamOwner,
                        substituteButtonFullWidth: true,
                        onTapSubmit: onTapSubmit,
                        onTapSubstitute: onTapSubstitute,
                        onTapPassTasuki: onTapPassTasuki
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(leg.status == .ready ? Color.tasukiAccentOrange.opacity(0.12) : Color.tasukiDarkCardSecondary)
        )
    }
    
    @ViewBuilder
    private func ekidenLegActionButtons(
        leg: EkidenLeg,
        canSubmit: Bool,
        allowSubmit: Bool,
        isTeamOwner: Bool,
        substituteButtonFullWidth: Bool,
        onTapSubmit: @escaping () -> Void,
        onTapSubstitute: @escaping () -> Void,
        onTapPassTasuki: (() -> Void)?
    ) -> some View {
        if canSubmit {
            Button(action: onTapSubmit) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                    Text("区間を走って提出")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Color.tasukiAccentOrange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            if let onPass = onTapPassTasuki {
                Button(action: onPass) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                        Text("TASUKIをつなぐ")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color.tasukiMutedText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.tasukiDarkCardSecondary))
                }
                .buttonStyle(.plain)
            }
        }
        if isTeamOwner && allowSubmit && (leg.status == .ready || leg.status == .awaitingTasuki) {
            Button(action: onTapSubstitute) {
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                    Text("代走")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color.tasukiMutedText)
                .frame(maxWidth: substituteButtonFullWidth ? .infinity : nil)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.tasukiDarkCardSecondary))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Slim Member List View
    private var slimMemberListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("メンバー")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Spacer()
                Text("\(members.count)/\(maxTeamMembers)名")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText)
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(members) { member in
                    slimMemberRowView(member: member)
                }
            }
            
            conditionRecordButton
                .padding(.top, 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiDarkCard)
        )
    }
    
    // MARK: - Slim Member Row View
    private func slimMemberRowView(member: TeamMember) -> some View {
        HStack(spacing: 12) {
            if let avatarImage = member.avatarImage {
                Image(systemName: avatarImage)
                    .font(.system(size: 20))
                    .foregroundColor(Color.tasukiPrimary)
                    .saturation(0)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.tasukiDarkCardSecondary)
                            .overlay(
                                Circle()
                                    .stroke(Color(hex: member.condition.colorHex), lineWidth: member.condition == .sos ? 3 : 2)
                            )
                    )
            } else {
                Circle()
                    .fill(Color(hex: "F5F7FA"))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: member.condition.colorHex), lineWidth: member.condition == .sos ? 3 : 2)
                    )
            }
            
            Text(member.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
                .frame(width: 70, alignment: .leading)
            
            HStack(spacing: 4) {
                Text("\(Int(member.currentDistance))km")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                
                Text("/")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
                
                Text("\(Int(member.targetDistance))km")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
            }
            
            Spacer()
            
            Image(systemName: member.condition.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: member.condition.colorHex))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(member.condition == .sos ? Color(hex: member.condition.colorHex).opacity(0.15) : Color.tasukiDarkCardSecondary)
        )
    }
    
    // MARK: - Progress View (The Tasuki Bar)
    private var progressView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(teamName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !selectedTeamId.isEmpty {
                    let total = PointService.shared.teamTotalPoints(teamId: selectedTeamId)
                    let tier = TeamRankTier.tier(forTeamPoints: total)
                    Text(tier.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(tier.color.opacity(0.2)))
                        .foregroundColor(tier.color)
                }
                Spacer()
                if !selectedTeamId.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(PointService.shared.teamTotalPoints(teamId: selectedTeamId))pt")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                        Text("累計")
                            .font(.system(size: 10))
                            .foregroundColor(Color.tasukiMutedText)
                    }
                    .padding(.trailing, teamViewChatFABReserveWidth)
                }
            }
            .padding(.bottom, 4)
            
            Text("\(Int(progressPercentage))%")
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(Color.tasukiAccentOrange)
            
            Text("\(monthEndDateString)まで（あと\(remainingDays)日）")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.tasukiMutedText)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                        .frame(height: 24)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: "2E5CFF"),
                                    Color.tasukiAccentOrange
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(progressPercentage / 100), height: 24)
                }
            }
            .frame(height: 24)
            
            HStack {
                Text("\(Int(currentDistance))km")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                
                Text("/")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
                
                Text("\(Int(targetDistance))km")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tasukiDarkCard)
        )
    }
    
    private func addSystemMessage(condition: Condition) {
        // 注: PartnerUserモデルが定義されている必要があります。
        // ここでは便宜上、最小限の初期化を想定しています。
        let systemUser = PartnerUser(
            name: "System",
            rank: "S",
            avatarImage: nil,
            isOnline: false,
            bestCategory: .full,
            bestTime: "0:00:00",
            age: 0,
            runningSchedule: .flexible,
            purpose: "",
            nextRace: nil,
            targetTime: nil,
            runningSpots: [],
            prefecture: "Tokyo",
            gender: .male,
            condition: .good,
            statusMessage: "",
            ageGroup: "",
            runningGoal: "",
            personalBest: nil,
            activeTime: "",
            easyPace: "0:00/km",
            connectionStyle: .both
        )
        
        let systemMessage = TeamMessage(
            user: systemUser,
            content: "\(myName)さんが「\(condition.rawValue)」に変更しました。",
            timestamp: Date(),
            isSystem: true
        )
        
        teamMessages.append(systemMessage)
    }
}

// MARK: - Team Chat Sheet View（TeamView 内専用。HomeView のメッセージとは連携しない）
struct TeamChatSheetView: View {
    let teamId: String
    /// サンプルチームのときはローカルの Binding のみ使用。本番チームでは Firestore teams/{teamId}/teamChat を使用
    var isSampleTeam: Bool = false
    @Binding var teamMessages: [TeamMessage]
    let myName: String
    let myCondition: Condition
    let myStatusMessage: String
    
    @State private var messageText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) var dismiss
    
    /// 本番チーム用: Firestore から取得したメッセージ（HomeView の会話とは別コレクション）
    @State private var firestoreMessages: [TeamMessage] = []
    @State private var chatListener: ListenerRegistration?
    
    private var displayedMessages: [TeamMessage] {
        isSampleTeam ? teamMessages : firestoreMessages
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(displayedMessages) { message in
                                    messageBubbleView(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        }
                        .onChange(of: displayedMessages.count) { _ in
                            if let lastMessage = displayedMessages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CompanionChatQuickPhrases.all, id: \.self) { phrase in
                                Button {
                                    sendQuickPhrase(phrase)
                                } label: {
                                    Text(phrase)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Color.tasukiPrimary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(Color.tasukiAccentOrange.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                    
                    HStack(spacing: 12) {
                        TextField("メッセージを入力...", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundColor(Color.tasukiPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.tasukiDarkCardSecondary)
                            )
                            .focused($isTextFieldFocused)
                            .lineLimit(1...4)
                        
                        Button(action: {
                            sendMessage()
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(messageText.isEmpty ? Color.gray : Color.tasukiAccentOrange)
                                )
                        }
                        .disabled(messageText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.tasukiDarkBackground)
                }
            }
            .navigationTitle("チームチャット")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(Color.tasukiPrimary)
                }
            }
        }
        .onAppear {
            if !isSampleTeam && !teamId.isEmpty {
                startTeamChatListener()
            }
        }
        .onDisappear {
            chatListener?.remove()
            chatListener = nil
        }
    }
    
    /// 本番チーム用: teams/{teamId}/teamChat を監視（HomeView メッセージとは別）
    private func startTeamChatListener() {
        chatListener?.remove()
        let db = Firestore.firestore()
        chatListener = db.collection("teams").document(teamId).collection("teamChat")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                guard let docs = snapshot?.documents, error == nil else { return }
                let list = docs.compactMap { doc -> TeamMessage? in
                    let data = doc.data()
                    let senderName = data["senderName"] as? String ?? ""
                    let content = data["content"] as? String ?? ""
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    let isSystem = data["isSystem"] as? Bool ?? false
                    let id = UUID(uuidString: doc.documentID) ?? UUID()
                    let user = minimalPartnerUser(name: senderName)
                    return TeamMessage(id: id, user: user, content: content, timestamp: timestamp, isSystem: isSystem)
                }
                DispatchQueue.main.async {
                    firestoreMessages = list
                }
            }
    }
    
    private func minimalPartnerUser(name: String) -> PartnerUser {
        PartnerUser(
            name: name,
            rank: "—",
            avatarImage: "person.circle.fill",
            isOnline: false,
            bestCategory: .fiveKm,
            bestTime: "—",
            age: 0,
            runningSchedule: .flexible,
            purpose: "",
            nextRace: nil,
            targetTime: nil,
            runningSpots: [],
            prefecture: "",
            gender: .other,
            condition: .good,
            statusMessage: "",
            ageGroup: "",
            runningGoal: "",
            personalBest: nil,
            activeTime: "",
            easyPace: "—",
            connectionStyle: .both
        )
    }
    
    @ViewBuilder
    private func messageBubbleView(message: TeamMessage) -> some View {
        if message.isSystem {
            HStack {
                Spacer()
                Text("--- \(message.content) ---")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
                Spacer()
            }
            .padding(.vertical, 8)
        } else {
            let isFromMe = message.user.name == myName
            
            HStack(alignment: .top, spacing: 8) {
                if !isFromMe {
                    if let avatarImage = message.user.avatarImage {
                        Image(systemName: avatarImage)
                            .font(.system(size: 18))
                            .foregroundColor(Color.tasukiPrimary)
                            .saturation(0)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.tasukiDarkCardSecondary)
                            )
                    }
                }
                
                VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                    if !isFromMe {
                        Text(message.user.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.tasukiMutedText)
                    }
                    
                    Text(message.content)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(isFromMe ? .white : Color.tasukiPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isFromMe ? Color.tasukiAccentOrange : Color.tasukiDarkCard)
                        )
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7, alignment: isFromMe ? .trailing : .leading)
                
                if isFromMe {
                    Spacer()
                }
            }
        }
    }
    
    private func sendQuickPhrase(_ phrase: String) {
        messageText = phrase
        sendMessage()
    }
    
    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        if isSampleTeam {
            let myUser = PartnerUser(
                name: myName,
                rank: "A",
                avatarImage: "person.circle.fill",
                isOnline: true,
                bestCategory: .full,
                bestTime: "3:10:00",
                age: 29,
                runningSchedule: .weekdayEvening,
                purpose: "サブ3目標",
                nextRace: nil,
                targetTime: nil,
                runningSpots: [],
                prefecture: "Tokyo",
                gender: .male,
                condition: myCondition,
                statusMessage: myStatusMessage,
                ageGroup: "20s",
                runningGoal: "Sub3",
                personalBest: "3:10:00",
                activeTime: "Night",
                easyPace: "5:00/km",
                connectionStyle: .both
            )
            let newMessage = TeamMessage(user: myUser, content: content, timestamp: Date(), isSystem: false)
            teamMessages.append(newMessage)
        } else {
            // 本番チーム: Firestore に保存（HomeView のメッセージとは連携しない）
            let senderId = Auth.auth().currentUser?.uid ?? "anonymous"
            let db = Firestore.firestore()
            db.collection("teams").document(teamId).collection("teamChat").addDocument(data: [
                "senderId": senderId,
                "senderName": myName,
                "content": content,
                "timestamp": Timestamp(date: Date()),
                "isSystem": false
            ]) { _ in }
        }
        messageText = ""
        isTextFieldFocused = false
    }
}

// MARK: - Condition Update Sheet
struct ConditionUpdateSheet: View {
    @Binding var selectedCondition: Condition
    let onSave: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("調子")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color.tasukiPrimary)
                            
                            Picker("調子", selection: $selectedCondition) {
                                ForEach(Condition.allCases, id: \.self) { condition in
                                    HStack {
                                        Image(systemName: condition.icon)
                                            .foregroundColor(Color(hex: condition.colorHex))
                                        Text(condition.rawValue)
                                    }
                                    .tag(condition)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.tasukiPrimary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("調子を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                    }
                    .foregroundColor(Color.tasukiPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave()
                    }
                    .foregroundColor(Color.tasukiAccentOrange)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    TeamView(useMockTeamFlow: true)
}
