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

/// `teams/{teamId}/spectator_cheers` の表示用
struct SpectatorCheerDisplay: Identifiable {
    let id: String
    let nickname: String
    let message: String
    let timestamp: Date
}

/// オーナー脱退時に譲渡できるメンバー候補
private struct OwnerSuccessorCandidate: Identifiable {
    let uid: String
    let displayName: String
    var id: String { uid }
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
    /// プレビュー用: `true` で脱退可UI、`false` で期間中（グレー）を強制。`nil` で実データの駅伝期間を使用
    var debugLeaveAllowedOverride: Bool? = nil
    /// プレビュー用: 所属済みチーム画面を開く（`userTeamId` が未設定のときの表示用）
    var debugPreviewTeamId: String? = nil
    
    @State private var userTeamId: String? = nil
    @State private var selectedTeamId: String = ""
    @State private var showTeamDetail: Bool = false
    @State private var showJoinCreate: Bool = false
    /// EKIDENタブ表示直後、所属チーム判定が返るまでのちらつき抑止
    @State private var isResolvingEntryState: Bool = true
    
    // 自分のデータ管理
    @AppStorage("myCondition") private var myConditionRaw: String = Condition.good.rawValue
    @AppStorage("myStatusMessage") private var myStatusMessage: String = "今月も頑張ります！"
    @AppStorage("myName") private var myName: String = "Hiro"
    /// 未所属時に `TeamJoinCreateView` を出すか。脱退直後は `false` で「脱退完了」画面のみ
    @AppStorage("ekidenShowTeamJoinHub") private var showTeamJoinHub: Bool = true
    /// チーム参加ハブで選んだ EKIDEN モード（脱退後の再参加フローでは毎回選び直し）
    @State private var hubEkidenJoinMode: EkidenJoinMode? = nil
    /// チーム未所属かつ開催中に表示する観戦ビュー
    @State private var showGuestSpectatorView: Bool = false
    @State private var spectatorStatusesForGuest: [EkidenSpectatorTeamStatus] = []
    @State private var isLoadingGuestSpectator = false
    @State private var guestSpectatorError: String?
    @State private var guestSpectatorDayKey: String = ""
    @State private var guestSpectatorFocusedMarkerId: String?
    
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
    @State private var showPassTasukiConfirm = false
    @State private var passTasukiLegIndex: Int? = nil
    @State private var isPassingTasuki = false
    @State private var showDisqualifyConfirm = false
    @State private var isDisqualifying = false
    @State private var disqualifyErrorMessage: String?
    @State private var showLeaveTeamConfirm = false
    /// オーナー脱退: 後任のオーナーを選ぶシート
    @State private var showOwnerLeaveSheet = false
    @State private var ownerSuccessorCandidates: [OwnerSuccessorCandidate] = []
    @State private var selectedSuccessorUid: String = ""
    @State private var isLoadingOwnerSuccessors = false
    @State private var ownerLeaveError: String?
    @State private var isPerformingOwnerLeave = false

    /// 区間賞
    @State private var showLegRankingSheet = false
    /// 総合順位タップ → 全チームランキング（プログレスバー）
    @State private var showOverallStandingsMap = false
    /// 総合シートの「区間賞」から閉じた直後に区間賞シートを開く
    @State private var openLegRankingAfterStandingsDismiss = false
    @State private var legRankingSnapshot: EkidenLegRankingSnapshot?
    @State private var legRankingSelectedLegIndex: Int = 0
    /// 沿道応援（観客投稿・チーム内フィード）
    @State private var showSpectatorCheerSheet = false
    @State private var spectatorCheers: [SpectatorCheerDisplay] = []
    @State private var spectatorCheerListener: ListenerRegistration?
    @State private var spectatorCheersExpanded = false
    
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
                    .foregroundColor(Color.tasukiOnBrandYellow)
                Spacer()
            }
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.tasukiPrimaryButtonFill)
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
        useMockTeamFlow || TasukiDevelopmentFlags.skipFirestoreEkidenTabReads || Auth.auth().currentUser == nil
    }
    
    /// 参加チームID（本番の `userTeamId` またはプレビュー用）
    private var resolvedTeamId: String? {
        if let u = userTeamId, !u.isEmpty { return u }
        if let d = debugPreviewTeamId, !d.isEmpty { return d }
        return nil
    }

    /// 初期表示時のみ、所属状態が未確定なら中間ローディングを出す
    private var shouldShowEntryLoading: Bool {
        isResolvingEntryState && !isSampleTeamFlow && debugPreviewTeamId == nil && userTeamId == nil
    }
    
    /// 駅伝レース期間外のみ脱退可能（期間中はグレーアウト）
    private var canLeaveTeam: Bool {
        if let override = debugLeaveAllowedOverride {
            return override
        }
        // EKIDEN 状態の読み込み前は一時的に脱退ボタンを出さない（文言ちらつき防止）
        guard let state = ekidenViewState else { return false }
        return !state.isWithinEventWindow
    }
    
    var body: some View {
        NavigationStack {
            if shouldShowEntryLoading {
                ekidenEntryLoadingView
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Ekiden")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(Color.tasukiPrimary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
            } else if resolvedTeamId == nil {
                if showTeamJoinHub {
                    Group {
                        if showGuestSpectatorView, !spectatorStatusesForGuest.isEmpty {
                            ekidenGuestSpectatorView
                        } else if let mode = hubEkidenJoinMode {
                            TeamJoinCreateView(
                                ekidenJoinMode: mode,
                                onComplete: { teamId in
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
                                    } else {
                                        // 参加確定していない戻り（承認待ち・キャンセル）では参加済みUIにしない
                                        self.selectedTeamId = ""
                                        self.showTeamDetail = false
                                    }
                                    self.showTeamJoinHub = true
                                },
                                useMockFlow: isSampleTeamFlow
                            )
                        } else {
                            EkidenJoinModeSelectionView { selected in
                                hubEkidenJoinMode = selected
                            }
                        }
                    }
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Ekiden")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(Color.tasukiPrimary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        // leading は空けておく（MainTabView の「Home」オーバーレイと横並びで“戻る系が二重”に見えないようにする）
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            if hubEkidenJoinMode != nil {
                                Button("モード") {
                                    hubEkidenJoinMode = nil
                                }
                                .foregroundColor(Color.tasukiPrimary)
                            }
                            if !spectatorStatusesForGuest.isEmpty {
                                Button(showGuestSpectatorView ? "参加へ" : "観戦") {
                                    showGuestSpectatorView.toggle()
                                }
                                .foregroundColor(Color.tasukiPrimary)
                            }
                        }
                    }
                    .task {
                        await refreshGuestSpectatorIfNeeded()
                    }
                } else {
                    teamPostLeaveView
                }
            } else {
                ZStack {
                    Color.tasukiDarkBackground
                        .ignoresSafeArea()
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            Group {
                                if let ekiden = ekidenViewState {
                                    ekidenProgressCard(ekiden, isReadOnly: !ekiden.isWithinEventWindow)
                                } else {
                                    ekidenLoadingCard
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                            if let ekiden = ekidenViewState {
                                EmptyView()
                            }

                            if let ekiden = ekidenViewState {
                                ekidenSubmitRecordButton(ekiden)
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
                                            .foregroundColor(Color.tasukiOnBrandYellow)
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color.tasukiOnBrandYellow)
                                        Spacer()
                                    }
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.tasukiPrimaryButtonFill)
                                    )
                                }
                                .padding(.horizontal, 20)
                            }

                            if let ekiden = ekidenViewState {
                                ownerDisqualifySection(ekiden)
                                    .padding(.horizontal, 20)
                            }
                            
                            leaveTeamSection
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }
                        .padding(.bottom, scrollContentBottomPadding)
                    }
                    
                    NavigationLink(destination: TeamDetailView(teamId: selectedTeamId), isActive: $showTeamDetail) {
                        EmptyView()
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // principal を広げない（中央タイトルが trailing を圧縮してアイコンが小さく見えるのを防ぐ）
                    ToolbarItem(placement: .principal) {
                        Text("Ekiden")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showTeamChatSheet = true
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.system(size: 20))
                                .foregroundColor(Color.tasukiPrimary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
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
                .sheet(isPresented: $showLegRankingSheet) {
                    if let ekiden = ekidenViewState {
                        EkidenLegRankingSheetView(
                            state: ekiden,
                            selectedLegIndex: $legRankingSelectedLegIndex,
                            snapshot: $legRankingSnapshot,
                            isSampleTeam: isSampleTeamFlow || selectedTeamId.hasPrefix("example"),
                            myEntryId: ekiden.entry.id,
                            currentUid: Auth.auth().currentUser?.uid,
                            reload: { legIdx in
                                await reloadLegRanking(legIndex: legIdx, state: ekiden)
                            }
                        )
                    }
                }
                .sheet(isPresented: $showOverallStandingsMap) {
                    if let ekiden = ekidenViewState {
                        EkidenOverallStandingsMapView(
                            eventId: ekiden.event.id,
                            isSampleTeam: isSampleTeamFlow || selectedTeamId.hasPrefix("example"),
                            usesHakoneCourse: ekiden.usesOfficialHakoneRelayRules,
                            highlightTeamId: selectedTeamId,
                            myOutboundRank: ekiden.outboundRank,
                            referenceTotalKm: ekiden.rankingProgressReferenceKm,
                            onOpenLegRanking: {
                                openLegRankingAfterStandingsDismiss = true
                                showOverallStandingsMap = false
                            }
                        )
                    }
                }
                .onChange(of: showOverallStandingsMap) { _, presented in
                    guard !presented, openLegRankingAfterStandingsDismiss else { return }
                    openLegRankingAfterStandingsDismiss = false
                    showLegRankingSheet = true
                }
                .onAppear {
                    selectedCondition = myCondition
                    if !isSampleTeamFlow {
                        loadUserTeamId()
                    }
                    if let tid = resolvedTeamId, !tid.isEmpty {
                        if selectedTeamId.isEmpty { selectedTeamId = tid }
                        if userTeamId == nil, let d = debugPreviewTeamId, !d.isEmpty {
                            userTeamId = d
                        }
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
                        loadTeamOwner(teamId: newId)
                        Task { await loadEkidenState(teamId: newId) }
                    } else {
                        isTeamOwner = false
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
                .alert("チームから脱退しますか？", isPresented: $showLeaveTeamConfirm) {
                    Button("キャンセル", role: .cancel) {}
                    Button("脱退する", role: .destructive) {
                        performLeaveTeam()
                    }
                } message: {
                    Text("脱退後は駅伝のチーム機能を利用できなくなります。駅伝開催期間外のみ脱退できます。")
                }
                .alert("公式記録を棄権扱いにしますか？", isPresented: $showDisqualifyConfirm) {
                    Button("キャンセル", role: .cancel) {}
                    Button("棄権する", role: .destructive) {
                        performTeamDisqualify()
                    }
                } message: {
                    Text("この操作はオーナーのみ実行できます。チームの公式順位は失格（参考記録）として扱われます。")
                }
                .sheet(isPresented: $showOwnerLeaveSheet) {
                    ownerLeaveTransferSheet
                }
            }
        }
        .task(id: debugPreviewTeamId) {
            if let d = debugPreviewTeamId, !d.isEmpty {
                if userTeamId == nil { userTeamId = d }
                if selectedTeamId.isEmpty { selectedTeamId = d }
            }
        }
        .task {
            await EkidenDeviceSampleDataSeeder.seedIfNeeded()
        }
        .onAppear {
            if isSampleTeamFlow || debugPreviewTeamId != nil {
                isResolvingEntryState = false
            } else {
                isResolvingEntryState = true
                loadUserTeamId()
            }
            if userTeamId == nil, isSampleTeamFlow, let savedId = UserDefaults.standard.string(forKey: "myTeamId"), !savedId.isEmpty {
                userTeamId = savedId
                selectedTeamId = savedId
            }
        }
    } // body の閉じ (修正箇所)

    private func loadUserTeamId() {
        guard let firebaseUser = Auth.auth().currentUser else {
            isResolvingEntryState = false
            return
        }
        if TasukiDevelopmentFlags.skipFirestoreEkidenTabReads {
            DispatchQueue.main.async {
                self.userTeamId = nil
                self.isResolvingEntryState = false
            }
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(firebaseUser.uid).getDocument { snapshot, error in
            if let data = snapshot?.data(), let teamId = data["teamId"] as? String {
                DispatchQueue.main.async {
                    self.userTeamId = teamId
                    self.isResolvingEntryState = false
                }
            } else {
                DispatchQueue.main.async {
                    self.userTeamId = nil
                    self.isResolvingEntryState = false
                }
            }
        }
    }

    private var ekidenEntryLoadingView: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.tasukiAccentOrange)
                Text("チーム情報を確認中...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
            }
        }
    }

    private var ekidenGuestSpectatorView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if isLoadingGuestSpectator {
                    ProgressView("観戦データを読み込み中...")
                        .padding(.top, 24)
                }

                if let guestSpectatorError, !guestSpectatorError.isEmpty {
                    Text(guestSpectatorError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                }

                if !spectatorStatusesForGuest.isEmpty {
                    let guestMarkers = spectatorStatusesForGuest.map {
                        EkidenTeamsCourseProgressBar.Marker(
                            id: $0.teamId,
                            title: $0.teamName,
                            cumulativeKm: $0.cumulativeDistanceKm
                        )
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("横軸は全区間を 100% とした累計の進捗（箱根 \(String(format: "%.1f", HakoneEkidenCourse.totalKm)) km）")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.tasukiMutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        EkidenTeamsCourseProgressBar(
                            markers: guestMarkers,
                            referenceTotalKm: HakoneEkidenCourse.totalKm,
                            emphasizedMarkerIds: [],
                            ownTeamMarkerIds: [],
                            focusedMarkerId: $guestSpectatorFocusedMarkerId
                        )
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.tasukiDarkCardSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.tasukiMutedText.opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    Text("観戦データは1日1回更新されます（\(guestSpectatorDayKey)時点）")
                        .font(.system(size: 11))
                        .foregroundColor(Color.tasukiMutedText)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 10) {
                    ForEach(spectatorStatusesForGuest) { status in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(status.teamName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                Text(status.currentRunnerName.map { "現在走者: \($0)" } ?? "現在走者: 集計中")
                                    .font(.system(size: 12))
                                    .foregroundColor(.black.opacity(0.78))
                                Text(String(format: "累計 %.1f km", status.cumulativeDistanceKm))
                                    .font(.system(size: 11))
                                    .foregroundColor(.black.opacity(0.66))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guestSpectatorFocusedMarkerId = status.teamId
                            }
                            Spacer()
                            Button {
                                Task { await sendGuestCheer(to: status) }
                            } label: {
                                Text(canSendGuestCheerToday(teamId: status.teamId) ? "応援する" : "本日送信済み")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(canSendGuestCheerToday(teamId: status.teamId) ? Color.tasukiOnBrandYellow : .gray)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(canSendGuestCheerToday(teamId: status.teamId) ? Color.tasukiPrimaryButtonFill : Color.gray.opacity(0.22))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSendGuestCheerToday(teamId: status.teamId))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiDarkCard))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .padding(.top, 16)
        }
    }
    
    @ViewBuilder
    private var leaveTeamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ekidenViewState == nil && debugLeaveAllowedOverride == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("読み込み中…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.tasukiMutedText)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.12))
                )
            } else {
                Button {
                    if isTeamOwner {
                        ownerLeaveError = nil
                        selectedSuccessorUid = ""
                        showOwnerLeaveSheet = true
                    } else {
                        showLeaveTeamConfirm = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("チームから脱退")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canLeaveTeam ? Color.white : Color.gray.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(canLeaveTeam ? 0.4 : 0.2), lineWidth: 1)
                    )
                }
                .foregroundColor(canLeaveTeam ? Color.tasukiPrimary : Color.gray)
                .disabled(!canLeaveTeam)
            }
            
            if ekidenViewState != nil && !canLeaveTeam {
                Text("駅伝レースの開催期間中は脱退できません（期間終了後に再度お試しください）")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isTeamOwner, canLeaveTeam {
                Text("オーナーの場合は、脱退前に他のメンバーへオーナー権を譲る必要があります。")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func ownerDisqualifySection(_ state: EkidenViewState) -> some View {
        if isTeamOwner {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if !state.entry.officialResultDisqualified && !isDisqualifying {
                        disqualifyErrorMessage = nil
                        showDisqualifyConfirm = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(state.entry.officialResultDisqualified ? "棄権済み（参考記録）" : "棄権する")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(state.entry.officialResultDisqualified ? Color.gray.opacity(0.22) : Color.red.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(state.entry.officialResultDisqualified ? Color.gray.opacity(0.2) : Color.red.opacity(0.45), lineWidth: 1)
                    )
                }
                .foregroundColor(state.entry.officialResultDisqualified ? Color.gray : Color.red)
                .disabled(state.entry.officialResultDisqualified || isDisqualifying)

                if let disqualifyErrorMessage {
                    Text(disqualifyErrorMessage)
                        .font(.caption)
                        .foregroundColor(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    /// オーナー脱退: 後任指定＋Firestore 更新シート
    private var ownerLeaveTransferSheet: some View {
        NavigationStack {
            Group {
                if isLoadingOwnerSuccessors {
                    ProgressView("読み込み中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if ownerSuccessorCandidates.isEmpty {
                    VStack(spacing: 16) {
                        Text("他にメンバーがいません")
                            .font(.headline)
                        Text("オーナーを譲るには、チームに自分以外のメンバーが必要です。先にメンバーを追加してから脱退してください。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        Section {
                            Picker("新しいオーナー", selection: $selectedSuccessorUid) {
                                ForEach(ownerSuccessorCandidates) { c in
                                    Text(c.displayName).tag(c.uid)
                                }
                            }
                        } footer: {
                            Text("選んだメンバーにオーナー権を移し、あなたはチームから外れます。駅伝エントリがある場合も新オーナーに紐づけます。")
                        }
                        if let err = ownerLeaveError {
                            Section {
                                Text(err)
                                    .foregroundColor(.red)
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
            .navigationTitle("オーナーを譲る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showOwnerLeaveSheet = false
                    }
                    .disabled(isPerformingOwnerLeave)
                }
                if !ownerSuccessorCandidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("譲って脱退") {
                            Task { await performOwnerTransferAndLeave() }
                        }
                        .disabled(selectedSuccessorUid.isEmpty || isPerformingOwnerLeave)
                    }
                }
            }
            .task {
                await loadOwnerSuccessorCandidates()
            }
        }
    }
    
    private func effectiveTeamIdForLeave() -> String {
        let tid = selectedTeamId.isEmpty ? (userTeamId ?? "") : selectedTeamId
        return tid
    }
    
    private func mockOwnerSuccessorCandidates(teamId: String) -> [OwnerSuccessorCandidate] {
        if teamId == "example_owner" {
            return [
                OwnerSuccessorCandidate(uid: "u_kenji", displayName: "Kenji_Run"),
                OwnerSuccessorCandidate(uid: "u_sacchan", displayName: "さっちゃん")
            ]
        }
        return []
    }
    
    private func loadOwnerSuccessorCandidates() async {
        await MainActor.run {
            isLoadingOwnerSuccessors = true
            ownerLeaveError = nil
        }
        defer {
            Task { @MainActor in
                isLoadingOwnerSuccessors = false
            }
        }
        let tid = effectiveTeamIdForLeave()
        guard !tid.isEmpty else {
            await MainActor.run { ownerSuccessorCandidates = [] }
            return
        }
        if isSampleTeamFlow {
            let mock = mockOwnerSuccessorCandidates(teamId: tid)
            await MainActor.run {
                ownerSuccessorCandidates = mock
                selectedSuccessorUid = mock.first?.uid ?? ""
            }
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            await MainActor.run { ownerSuccessorCandidates = [] }
            return
        }
        let db = Firestore.firestore()
        do {
            let teamSnap = try await db.collection("teams").document(tid).getDocument()
            guard let data = teamSnap.data() else {
                await MainActor.run { ownerSuccessorCandidates = [] }
                return
            }
            let members = data["members"] as? [String] ?? []
            let others = members.filter { $0 != uid }
            var rows: [OwnerSuccessorCandidate] = []
            for m in others {
                let displayName: String
                if let ud = try? await db.collection("users").document(m).getDocument(),
                   let d = ud.data(),
                   let n = d["name"] as? String,
                   !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    displayName = n
                } else {
                    displayName = "ユーザー (\(String(m.prefix(6)))…)"
                }
                rows.append(OwnerSuccessorCandidate(uid: m, displayName: displayName))
            }
            await MainActor.run {
                ownerSuccessorCandidates = rows
                if selectedSuccessorUid.isEmpty, let first = rows.first {
                    selectedSuccessorUid = first.uid
                }
            }
        } catch {
            await MainActor.run {
                ownerSuccessorCandidates = []
                ownerLeaveError = "メンバー情報の取得に失敗しました: \(error.localizedDescription)"
            }
        }
    }
    
    private func commitFirestoreBatch(_ batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }
    
    private func performOwnerTransferAndLeave() async {
        let tid = effectiveTeamIdForLeave()
        guard !tid.isEmpty, !selectedSuccessorUid.isEmpty else { return }
        await MainActor.run {
            isPerformingOwnerLeave = true
            ownerLeaveError = nil
        }
        defer {
            Task { @MainActor in
                isPerformingOwnerLeave = false
            }
        }
        if isSampleTeamFlow {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                TeamLeavePolicy.recordLeave(teamId: tid, isMock: true)
                UserDefaults.standard.removeObject(forKey: "myTeamId")
                userTeamId = nil
                selectedTeamId = ""
                ekidenViewState = nil
                isTeamOwner = false
                showTeamJoinHub = false
                showOwnerLeaveSheet = false
                ownerSuccessorCandidates = []
            }
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            await MainActor.run { ownerLeaveError = "ログイン情報がありません。" }
            return
        }
        let newOwner = selectedSuccessorUid
        guard newOwner != uid else {
            await MainActor.run { ownerLeaveError = "自分以外のメンバーを選んでください。" }
            return
        }
        let db = Firestore.firestore()
        let teamRef = db.collection("teams").document(tid)
        let userRef = db.collection("users").document(uid)
        do {
            let teamSnap = try await teamRef.getDocument()
            guard let data = teamSnap.data(),
                  let docOwner = data["ownerUid"] as? String,
                  docOwner == uid else {
                await MainActor.run { ownerLeaveError = "チームのオーナーではないか、情報が古いです。画面を開き直してください。" }
                return
            }
            let memberIds = data["members"] as? [String] ?? []
            guard memberIds.contains(newOwner) else {
                await MainActor.run { ownerLeaveError = "選んだユーザーは現在のメンバーに含まれていません。" }
                return
            }
            let batch = db.batch()
            batch.updateData([
                "ownerUid": newOwner,
                "members": FieldValue.arrayRemove([uid])
            ], forDocument: teamRef)
            let entriesSnap = try await db.collection("ekiden_entries")
                .whereField("teamId", isEqualTo: tid)
                .getDocuments()
            for doc in entriesSnap.documents {
                batch.updateData(["ownerUid": newOwner], forDocument: doc.reference)
            }
            batch.updateData(["teamId": FieldValue.delete()], forDocument: userRef)
            try await commitFirestoreBatch(batch)
            await MainActor.run {
                TeamLeavePolicy.recordLeave(teamId: tid, isMock: false)
                userTeamId = nil
                selectedTeamId = ""
                ekidenViewState = nil
                isTeamOwner = false
                showTeamJoinHub = false
                showOwnerLeaveSheet = false
                ownerSuccessorCandidates = []
                ownerLeaveError = nil
            }
        } catch {
            await MainActor.run {
                ownerLeaveError = "処理に失敗しました: \(error.localizedDescription)"
            }
        }
    }
    
    private func performLeaveTeam() {
        let tid = selectedTeamId.isEmpty ? (userTeamId ?? "") : selectedTeamId
        guard !tid.isEmpty else { return }
        // オーナーは通常フローではシート側で処理（二重実行防止）
        if isTeamOwner {
            return
        }
        if isSampleTeamFlow {
            TeamLeavePolicy.recordLeave(teamId: tid, isMock: true)
            UserDefaults.standard.removeObject(forKey: "myTeamId")
            userTeamId = nil
            selectedTeamId = ""
            ekidenViewState = nil
            isTeamOwner = false
            showLeaveTeamConfirm = false
            showTeamJoinHub = false
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData(["teamId": FieldValue.delete()]) { err in
            DispatchQueue.main.async {
                self.showLeaveTeamConfirm = false
                if err == nil {
                    TeamLeavePolicy.recordLeave(teamId: tid, isMock: false)
                    self.userTeamId = nil
                    self.selectedTeamId = ""
                    self.ekidenViewState = nil
                    self.isTeamOwner = false
                    self.showTeamJoinHub = false
                }
            }
        }
    }
    
    /// 脱退直後: 検索ハブではなくメッセージ画面を出す
    private var teamPostLeaveView: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 48))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.65))
                Text("チームから脱退しました")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("再度チームに参加するときは下のボタンから「チームを探す・作る」に進めます。\nこのシーズン（4月〜翌3月）に脱退した同じチームへは、次のシーズンまで再加入できません。")
                    .font(.system(size: 14))
                    .foregroundColor(Color.tasukiMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button {
                    hubEkidenJoinMode = nil
                    showTeamJoinHub = true
                } label: {
                    HStack {
                        Spacer()
                        Text("チームを探す・作る")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                        Spacer()
                    }
                    .frame(minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                Spacer()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Ekiden")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
    
    /// 駅伝イベント状態を取得
    private func loadEkidenState(teamId: String) async {
        let isSample = isSampleTeamFlow || teamId.hasPrefix("example")
        let state = await EkidenDataService.shared.loadEkidenState(teamId: teamId, isSampleTeam: isSample)
        let defaultLegIdx: Int
        if let s = state {
            let maxIdx = max(0, s.event.legCount - 1)
            var idx = min(max(0, s.entry.currentLegIndex), maxIdx)
            // 区間賞のモックは「提出済み区間」だけ生成するため、未提出の現在区間だと一覧が空になる
            if isSample, !s.legs.indices.contains(idx) || s.legs[idx].status != .submitted || s.legs[idx].isPass {
                idx = s.legs.firstIndex(where: { $0.status == .submitted && !$0.isPass }) ?? 0
            }
            defaultLegIdx = min(max(0, idx), maxIdx)
        } else {
            defaultLegIdx = 0
        }
        await MainActor.run {
            ekidenViewState = state
            legRankingSelectedLegIndex = defaultLegIdx
        }
        guard let s = state else {
            await MainActor.run { legRankingSnapshot = nil }
            return
        }
        let snap: EkidenLegRankingSnapshot?
        if isSample {
            snap = EkidenLegRankingSnapshot.buildMock(from: s, legIndex: defaultLegIdx)
        } else {
            snap = await EkidenDataService.shared.loadLegRankingSnapshot(eventId: s.event.id, legIndex: defaultLegIdx)
        }
        await MainActor.run { legRankingSnapshot = snap }
    }

    private func reloadLegRanking(legIndex: Int, state: EkidenViewState) async {
        let isSample = isSampleTeamFlow || selectedTeamId.hasPrefix("example")
        let snap: EkidenLegRankingSnapshot?
        if isSample {
            snap = EkidenLegRankingSnapshot.buildMock(from: state, legIndex: legIndex)
        } else {
            snap = await EkidenDataService.shared.loadLegRankingSnapshot(eventId: state.event.id, legIndex: legIndex)
        }
        await MainActor.run { legRankingSnapshot = snap }
    }

    private func startSpectatorCheerListener(teamId: String) {
        spectatorCheerListener?.remove()
        spectatorCheerListener = nil
        guard !teamId.isEmpty else {
            spectatorCheers = []
            return
        }
        if isSampleTeamFlow || teamId.hasPrefix("example") {
            spectatorCheers = []
            return
        }
        let db = Firestore.firestore()
        spectatorCheerListener = db.collection("teams").document(teamId).collection("spectator_cheers")
            .order(by: "timestamp", descending: true)
            .limit(to: 30)
            .addSnapshotListener { snapshot, _ in
                guard let docs = snapshot?.documents else { return }
                let list: [SpectatorCheerDisplay] = docs.compactMap { doc in
                    let d = doc.data()
                    let nick = d["nickname"] as? String ?? "沿道"
                    let msg = d["message"] as? String ?? ""
                    let ts = (d["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    return SpectatorCheerDisplay(id: doc.documentID, nickname: nick, message: msg, timestamp: ts)
                }
                DispatchQueue.main.async {
                    self.spectatorCheers = list
                }
            }
    }

    private func stopSpectatorCheerListener() {
        spectatorCheerListener?.remove()
        spectatorCheerListener = nil
        spectatorCheers = []
    }

    private func ekidenEngagementRow(_ state: EkidenViewState) -> some View {
        HStack(spacing: 0) {
            Button {
                showLegRankingSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32)
                    Text("区間賞")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.tasukiMutedText.opacity(0.25))
                .frame(width: 1, height: 28)

            Button {
                showSpectatorCheerSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hands.clap.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 32)
                    Text("応援を送る")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var spectatorCheerFeedSection: some View {
        if spectatorCheers.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        spectatorCheersExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundColor(.black)
                        Text("沿道からの応援")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                        Spacer()
                        Text("\(spectatorCheers.count)件")
                            .font(.caption)
                            .foregroundColor(.black)
                        Image(systemName: spectatorCheersExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)

                let visible = spectatorCheersExpanded ? spectatorCheers : Array(spectatorCheers.prefix(3))
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, cheer in
                    VStack(alignment: .leading, spacing: 4) {
                        if index > 0 {
                            Divider()
                                .background(Color.tasukiMutedText.opacity(0.2))
                        }
                        HStack {
                            Text(cheer.nickname)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black)
                            Spacer()
                            Text(shortRelativeTime(cheer.timestamp))
                                .font(.system(size: 10))
                                .foregroundColor(.black)
                        }
                        Text(cheer.message)
                            .font(.system(size: 13))
                            .foregroundColor(.black)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func shortRelativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func dayKeyString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func guestCheerStorageKey(teamId: String, dayKey: String) -> String {
        "guest_spectator_cheer_\(teamId)_\(dayKey)"
    }

    private func canSendGuestCheerToday(teamId: String) -> Bool {
        let key = guestCheerStorageKey(teamId: teamId, dayKey: dayKeyString(Date()))
        return !UserDefaults.standard.bool(forKey: key)
    }

    private func markGuestCheerSentToday(teamId: String) {
        let key = guestCheerStorageKey(teamId: teamId, dayKey: dayKeyString(Date()))
        UserDefaults.standard.set(true, forKey: key)
    }

    private func refreshGuestSpectatorIfNeeded() async {
        guard resolvedTeamId == nil else { return }
        let todayKey = dayKeyString(Date())
        if guestSpectatorDayKey == todayKey, !spectatorStatusesForGuest.isEmpty {
            return
        }
        if TasukiDevelopmentFlags.skipFirestoreEkidenTabReads {
            await MainActor.run {
                spectatorStatusesForGuest = []
                guestSpectatorDayKey = todayKey
                isLoadingGuestSpectator = false
                guestSpectatorError = nil
            }
            return
        }
        await MainActor.run {
            isLoadingGuestSpectator = true
            guestSpectatorError = nil
        }
        let statuses = await EkidenDataService.shared.loadActiveEkidenSpectatorStatuses(isSampleTeam: isSampleTeamFlow)
        await MainActor.run {
            spectatorStatusesForGuest = statuses
            guestSpectatorDayKey = todayKey
            isLoadingGuestSpectator = false
        }
    }

    private func sendGuestCheer(to status: EkidenSpectatorTeamStatus) async {
        guard canSendGuestCheerToday(teamId: status.teamId) else { return }
        if isSampleTeamFlow || status.teamId.hasPrefix("example") {
            await MainActor.run {
                markGuestCheerSentToday(teamId: status.teamId)
            }
            return
        }
        let spectatorUid = Auth.auth().currentUser?.uid ?? SpectatorCheerClientInstance.value
        let result = await EkidenDataService.shared.sendSpectatorCheerOncePerDay(
            teamId: status.teamId,
            eventId: status.eventId,
            spectatorUid: spectatorUid,
            cheerDateKey: dayKeyString(Date())
        )
        await MainActor.run {
            switch result {
            case .success:
                markGuestCheerSentToday(teamId: status.teamId)
            case .failure(let error):
                guestSpectatorError = "応援の送信に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    /// 当該区間の担当走者がログイン中の自分か。サンプルかつ未ログインのときはモック UID で判定。
    private func isCurrentUserAssignedRunner(leg: EkidenLeg, teamId: String, isSampleTeam: Bool) -> Bool {
        guard let assigned = leg.assignedUid else { return false }
        if let uid = Auth.auth().currentUser?.uid {
            return assigned == uid
        }
        guard isSampleTeam else { return false }
        switch teamId {
        case "example_owner":
            return assigned == "sample_owner"
        case "example_member", "example_ekiden_real":
            return assigned == "u_kenji"
        default:
            return assigned == "sample_owner"
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
        let teamId = selectedTeamId
        let isSample = isSampleTeamFlow || teamId.hasPrefix("example")
        guard let leg = state.legs.first(where: { $0.id == legIndex }),
              isCurrentUserAssignedRunner(leg: leg, teamId: teamId, isSampleTeam: isSample) else {
            showPassTasukiConfirm = false
            passTasukiLegIndex = nil
            return
        }
        let submittedByUid: String? = isSampleTeamFlow
            ? leg.assignedUid
            : Auth.auth().currentUser?.uid
        guard let uid = submittedByUid else {
            showPassTasukiConfirm = false
            passTasukiLegIndex = nil
            return
        }
        let entryId = state.entry.id
        let passedLegIndex = legIndex
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
            }
            guard case .success = result else { return }
            await loadEkidenState(teamId: teamId)
            await MainActor.run {
                if let st = ekidenViewState {
                    TasukiHandoffNotifier.notifyAfterPassTasuki(state: st, passedLegIndex: passedLegIndex)
                }
            }
        }
    }

    private func performTeamDisqualify() {
        guard isTeamOwner, let state = ekidenViewState else {
            showDisqualifyConfirm = false
            return
        }
        if state.entry.officialResultDisqualified {
            showDisqualifyConfirm = false
            return
        }
        let teamId = selectedTeamId
        let isSample = isSampleTeamFlow || teamId.hasPrefix("example")
        isDisqualifying = true
        disqualifyErrorMessage = nil
        showDisqualifyConfirm = false
        Task {
            let result = await EkidenDataService.shared.setOfficialResultDisqualified(
                teamId: teamId,
                entryId: state.entry.id,
                isSampleTeam: isSample,
                isDisqualified: true
            )
            await MainActor.run {
                isDisqualifying = false
                switch result {
                case .success:
                    Task { await loadEkidenState(teamId: teamId) }
                case .failure(let error):
                    disqualifyErrorMessage = "棄権処理に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }
    
    /// チームのオーナー（管理者）かどうかを取得。「メンバー管理」ボタン表示用
    private func loadTeamOwner(teamId: String) {
        isTeamOwner = false
        // サンプルチーム: example_owner のときだけオーナー視点
        if teamId == "example_owner" || teamId == "example_member" || teamId == "example_ekiden_real" {
            isTeamOwner = (teamId == "example_owner")
            return
        }
        guard let currentUid = Auth.auth().currentUser?.uid else {
            return
        }
        let db = Firestore.firestore()
        db.collection("teams").document(teamId).getDocument { snapshot, error in
            if error != nil {
                DispatchQueue.main.async { self.isTeamOwner = false }
                return
            }
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
    private func ekidenSubmitRecordButton(_ state: EkidenViewState) -> some View {
        let readyLeg = state.legs.first {
            $0.status == .ready && isCurrentUserAssignedRunner(
                leg: $0,
                teamId: selectedTeamId,
                isSampleTeam: isSampleTeamFlow || selectedTeamId.hasPrefix("example")
            )
        }
        return Button {
            guard let leg = readyLeg else { return }
            ekidenSubmitSheetItem = EkidenSubmitSheetItem(leg: leg, state: state)
        } label: {
            HStack {
                Spacer()
                Image(systemName: "link.badge.plus")
                Text(readyLeg == nil ? "提出可能な記録はありません" : "記録を提出する")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.tasukiPrimaryButtonFill)
            )
            .foregroundColor(Color.tasukiOnBrandYellow)
            .opacity(readyLeg == nil ? 0.65 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(readyLeg == nil)
    }

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
        } else if state.usesOfficialHakoneRelayRules {
            legProgress = state.hakoneCourseProgressFraction * 100
            progressCaption = String(
                format: "コース進捗 %.1f / %.1f km（%d区まで） · %@",
                state.cumulativeDistanceKm,
                HakoneEkidenCourse.totalKm,
                state.submittedLegCount,
                HakoneEkidenCourse.mapProgressLabel(cumulativeRunKm: state.cumulativeDistanceKm)
            )
        } else {
            legProgress = state.event.legCount > 0 ? Double(state.submittedLegCount) / Double(state.event.legCount) * 100 : 0
            progressCaption = "\(state.submittedLegCount)/\(state.event.legCount) 区間"
        }
        
        return VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(teamName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
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
                        .foregroundColor(.black)
                }
                Spacer()
                if state.provisionalRank != nil || state.outboundRank != nil || state.totalTeams > 0 {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button {
                            showOverallStandingsMap = true
                        } label: {
                            VStack(alignment: .trailing, spacing: 2) {
                                if let outbound = state.outboundRank {
                                    Text("往路 \(outbound)位")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.8))
                                }
                                if let rank = state.provisionalRank {
                                    Text("総合 \(rank)位")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.black)
                                } else if state.totalTeams > 0 {
                                    Text("総合ランキング")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.black.opacity(0.85))
                                }
                                Text(state.totalTeams > 0 ? "/\(state.totalTeams)チーム" : "")
                                    .font(.system(size: 10))
                                    .foregroundColor(.black)
                                Text("タップで一覧・区間賞へ")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color.tasukiMutedText)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("総合ランキングを開く")

                        Button {
                            showLegRankingSheet = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "trophy.fill")
                                Text("区間賞")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.tasukiDarkCardSecondary))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 4)
            
            // イベント期間（1行）
            HStack(spacing: 8) {
                Text(isReadOnly
                     ? "期間 \(startStr) 〜 \(endStr)（閲覧のみ）"
                     : "期間 \(startStr) 〜 \(endStr)（あと\(remainingDays)日）")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isReadOnly {
                    Text("期間外")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.tasukiMutedText.opacity(0.3)))
                        .foregroundColor(.black)
                }
                Spacer(minLength: 0)
            }
            
            // 区間進行
            HStack(spacing: 4) {
                Text("現在")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                Text("\(min(currentLegIndex + 1, state.event.legCount))区")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                        .frame(height: 20)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "C5DB00"),
                                    Color.tasukiBrandYellow,
                                    Color(hex: "FFF59E")
                                ],
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
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)

            if state.usesOfficialHakoneRelayRules {
                VStack(alignment: .leading, spacing: 8) {
                    Text("コース上の進捗（累計距離）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                    EkidenTeamsCourseProgressBar(
                        markers: [
                            EkidenTeamsCourseProgressBar.Marker(
                                id: state.entry.teamId,
                                title: "あなたのチーム",
                                cumulativeKm: state.cumulativeDistanceKm
                            )
                        ],
                        referenceTotalKm: HakoneEkidenCourse.totalKm,
                        emphasizedMarkerIds: Set([state.entry.teamId]),
                        ownTeamMarkerIds: Set([state.entry.teamId]),
                        focusedMarkerId: .constant(nil)
                    )
                    Text(HakoneEkidenCourse.mapProgressLabel(cumulativeRunKm: state.cumulativeDistanceKm))
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.tasukiMutedText.opacity(0.25), lineWidth: 1)
                )
            }

            if state.entry.officialResultDisqualified {
                Text("公式記録は失格（参考記録・繰り上げ完走の扱い）です。")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if state.usesOfficialHakoneRelayRules {
                Text(HakoneEkidenCourse.officialRulesFootnote)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44, maximum: 72), spacing: 4)],
                spacing: 4
            ) {
                ForEach(0..<state.event.legCount, id: \.self) { i in
                    let leg = state.legs.first { $0.id == i }
                    let isDone = leg?.status == .submitted
                    let isCurrent = leg?.status == .ready
                    HStack(spacing: 2) {
                        Image(systemName: isDone ? "checkmark.circle.fill" : (isCurrent ? "figure.run" : "circle"))
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                        Text("\(i + 1)区")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            
            // TASUKI受け渡し
            if let name = state.nextRunnerName(), state.legs.contains(where: { $0.status == .ready }) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                    Text("TASUKI:\(name)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    Text("（提出可能）")
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                }
                .padding(.vertical, 8)
            } else {
                let lastSubmitted = state.legs.last { $0.status == .submitted }
                let nextLeg = state.legs.first { $0.status == .awaitingTasuki }
                if let next = nextLeg, let uid = next.assignedUid, let name = state.memberNames[uid] {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                        Text("次走者: \(name)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                    }
                } else if lastSubmitted != nil && state.submittedLegCount >= state.event.legCount {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.black)
                        Text("全区間完了")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
            }
            
            // 累積タイム＆リザルト
            HStack {
                if state.totalElapsedSeconds > 0 {
                    HStack(spacing: 8) {
                        Text("累計タイム")
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                        Text(EkidenViewState.formatElapsed(state.totalElapsedSeconds))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                Spacer()
                Button(action: { showEkidenResultView = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.doc.horizontal")
                        Text("リザルト")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 0)
    }
    
    // MARK: - Ekiden Leg List View（区間担当行）
    private func ekidenLegListView(_ state: EkidenViewState, allowSubmit: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("区間担当")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.black)
                Spacer()
                Text("\(state.legs.count)区間")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(state.legs.enumerated()), id: \.element.id) { index, leg in
                    if index > 0 {
                        Divider()
                            .background(Color.tasukiMutedText.opacity(0.2))
                    }
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
                        onTapPassTasuki: {
                            passTasukiLegIndex = leg.id
                            showPassTasukiConfirm = true
                        }
                    )
                }
            }
        }
    }
    
    private func ekidenLegRowView(leg: EkidenLeg, state: EkidenViewState, teamId: String, isSampleTeam: Bool, allowSubmit: Bool = true, isTeamOwner: Bool = false, onTapSubmit: @escaping () -> Void, onTapPassTasuki: (() -> Void)? = nil) -> some View {
        let name = leg.assignedUid.flatMap { state.memberNames[$0] } ?? "未割当"
        let statusText: String
        let icon: String
        switch leg.status {
        case .submitted:
            let timeStr = leg.elapsedSeconds.map { EkidenViewState.formatElapsed($0) } ?? "—"
            if let km = leg.actualDistanceKm {
                statusText = String(format: "%.1fkm · %@", km, timeStr)
            } else {
                statusText = timeStr
            }
            icon = "checkmark.circle.fill"
        case .ready:
            statusText = "提出可能"
            icon = "figure.run"
        case .awaitingTasuki:
            statusText = "TASUKI待ち"
            icon = "clock"
        }
        let canSubmit = allowSubmit
            && leg.status == .ready
            && isCurrentUserAssignedRunner(leg: leg, teamId: teamId, isSampleTeam: isSampleTeam)
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(leg.id + 1)区")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 32, alignment: .leading)
                
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.black)
                    .saturation(0)
                
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 0)

            if state.usesOfficialHakoneRelayRules, let route = HakoneEkidenCourse.legRouteCaption(legIndex: leg.id) {
                Text(route)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black.opacity(0.58))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 44)
                    .padding(.bottom, 2)
            }
            
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ekidenLegActionButtons(
                        leg: leg,
                        canSubmit: canSubmit,
                        allowSubmit: allowSubmit,
                        isTeamOwner: isTeamOwner,
                        onTapSubmit: onTapSubmit,
                        onTapPassTasuki: onTapPassTasuki
                    )
                }
                VStack(spacing: 8) {
                    ekidenLegActionButtons(
                        leg: leg,
                        canSubmit: canSubmit,
                        allowSubmit: allowSubmit,
                        isTeamOwner: isTeamOwner,
                        onTapSubmit: onTapSubmit,
                        onTapPassTasuki: onTapPassTasuki
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func ekidenLegActionButtons(
        leg: EkidenLeg,
        canSubmit: Bool,
        allowSubmit: Bool,
        isTeamOwner: Bool,
        onTapSubmit: @escaping () -> Void,
        onTapPassTasuki: (() -> Void)?
    ) -> some View {
        // 区間行からの操作ボタン（区間提出/襷つなぎ/代走）は表示しない。
        EmptyView()
    }
    
    // MARK: - Slim Member List View
    private var slimMemberListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("メンバー")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.black)
                Spacer()
                Text("\(members.count)/\(maxTeamMembers)名")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
            }
            .padding(.bottom, 10)
            
            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 {
                        Divider()
                            .background(Color.tasukiMutedText.opacity(0.2))
                    }
                    slimMemberRowView(member: member)
                }
            }
        }
    }
    
    // MARK: - Slim Member Row View
    private func slimMemberRowView(member: TeamMember) -> some View {
        HStack(spacing: 12) {
            if let avatarImage = member.avatarImage {
                Image(systemName: avatarImage)
                    .font(.system(size: 20))
                    .foregroundColor(.black)
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
                    .fill(Color.tasukiDarkCardSecondary)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(Color(hex: member.condition.colorHex), lineWidth: member.condition == .sos ? 3 : 2)
                    )
            }
            
            Text(member.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 70, alignment: .leading)
            
            HStack(spacing: 4) {
                Text("\(Int(member.currentDistance))km")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                
                Text("/")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black)
                
                Text("\(Int(member.targetDistance))km")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            Image(systemName: member.condition.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: member.condition.colorHex))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 0)
    }
    
    // MARK: - Progress View (The Tasuki Bar)
    private var ekidenLoadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.tasukiAccentOrange)
            Text("EKIDENデータを読み込み中...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    // MARK: - Progress View (The Tasuki Bar)
    private var progressView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Text(teamName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
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
                        .foregroundColor(.black)
                }
                Spacer()
                if !selectedTeamId.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(PointService.shared.teamTotalPoints(teamId: selectedTeamId))pt")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                        Text("累計")
                            .font(.system(size: 10))
                            .foregroundColor(.black)
                    }
                }
            }
            .padding(.bottom, 4)
            
            Text("\(Int(progressPercentage))%")
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(.black)
            
            Text("\(monthEndDateString)まで（あと\(remainingDays)日）")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.black)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                        .frame(height: 24)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "C5DB00"),
                                    Color.tasukiBrandYellow,
                                    Color(hex: "FFF59E")
                                ],
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
                    .foregroundColor(.black)
                
                Text("/")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.black)
                
                Text("\(Int(targetDistance))km")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.black)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 0)
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

// MARK: - 区間賞シート（ランキング行タップ → コースマップ）
private struct LegRankingMapTapPayload: Identifiable {
    let id: String
    let row: EkidenLegRankingRow
}

private struct EkidenLegRankingSheetView: View {
    let state: EkidenViewState
    @Binding var selectedLegIndex: Int
    @Binding var snapshot: EkidenLegRankingSnapshot?
    let isSampleTeam: Bool
    let myEntryId: String
    let currentUid: String?
    let reload: (Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mapTapPayload: LegRankingMapTapPayload?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    if state.event.legCount > 1 {
                        Picker("区間", selection: $selectedLegIndex) {
                            ForEach(0..<state.event.legCount, id: \.self) { i in
                                Text("\(i + 1)区").tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(.black)
                        .onChange(of: selectedLegIndex) { _, new in
                            Task { await reload(new) }
                        }
                    }

                    if let snap = snapshot {
                        if let myRank = snap.rank(forEntryId: myEntryId), snap.totalFinishers > 0 {
                            Text("あなたのチームの順位: \(myRank)位（完走 \(snap.totalFinishers)）")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                        }

                        if snap.top.isEmpty {
                            Text(isSampleTeam ? "この区間はまだ記録がないか、デモでは完了済み区間のみ表示します。" : "この区間のランキングはまだありません。")
                                .font(.footnote)
                                .foregroundColor(.black)
                                .padding(.vertical, 8)
                        }

                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(snap.top.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 {
                                        Divider()
                                            .background(Color.tasukiMutedText.opacity(0.2))
                                    }
                                    Button {
                                        mapTapPayload = LegRankingMapTapPayload(id: row.entryId, row: row)
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(row.rank > 0 ? "\(row.rank)位" : "—")
                                                .font(.system(size: 14, weight: .bold))
                                                .frame(minWidth: 40, alignment: .leading)
                                                .foregroundColor(.black)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(row.displayName)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(.black)
                                                Text(EkidenViewState.formatElapsed(row.elapsedSeconds))
                                                    .font(.caption)
                                                    .foregroundColor(.black)
                                            }
                                            Spacer(minLength: 0)
                                            Image(systemName: "chart.line.uptrend.xyaxis")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(Color.tasukiAccent.opacity(0.85))
                                        }
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 16)
                        }
                    } else {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                .padding(16)
            }
            .navigationTitle("区間賞")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.black)
                }
            }
            .task {
                await reload(selectedLegIndex)
            }
            .sheet(item: $mapTapPayload) { payload in
                EkidenRankingCourseMapView(
                    eventId: state.event.id,
                    isSampleTeam: isSampleTeam,
                    usesHakoneCourse: state.usesOfficialHakoneRelayRules,
                    referenceTotalKm: state.rankingProgressReferenceKm,
                    ownEntryId: myEntryId,
                    selectedLegIndex: selectedLegIndex,
                    legRankForHighlight: snapshot?.rank(forEntryId: payload.row.entryId),
                    legTotalFinishers: snapshot?.totalFinishers ?? 0,
                    highlightEntryId: payload.row.entryId,
                    tappedRowDisplayName: payload.row.displayName
                )
            }
        }
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
                Color.white
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
                        HStack(spacing: 12) {
                            ForEach(CompanionChatQuickPhrases.all, id: \.self) { phrase in
                                Button {
                                    sendQuickPhrase(phrase)
                                } label: {
                                    Text(phrase)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(Color(.systemGray6))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .background(Color.white)
                    
                    HStack(spacing: 12) {
                        TextField("メッセージを入力", text: $messageText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(.systemGray6))
                            )
                            .focused($isTextFieldFocused)
                            .lineLimit(1...4)
                        
                        Button(action: {
                            sendMessage()
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(messageText.isEmpty ? Color.white : Color.tasukiOnBrandYellow)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(messageText.isEmpty ? Color.gray : Color.tasukiPrimaryButtonFill)
                                )
                        }
                        .disabled(messageText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiAccent)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("チームチャット")
                        .font(.system(size: 19, weight: .bold))
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
                            .foregroundColor(.black)
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                    }
                    
                    Text(message.content)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(isFromMe ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isFromMe ? Color.royalBlue : Color.gray.opacity(0.2))
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
                                .foregroundColor(.black)
                            
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
                            .tint(.black)
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
                    .foregroundColor(.black)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        onSave()
                    }
                    .foregroundColor(.black)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview("デフォルト（モック）") {
    TeamView(useMockTeamFlow: true)
}

#if DEBUG
/// 駅伝**期間外**として脱退ボタンが有効になる見た目を確認する
struct TeamViewOutsideEkidenPeriodPreview: View {
    var body: some View {
        NavigationStack {
            TeamView(
                useMockTeamFlow: true,
                debugLeaveAllowedOverride: true,
                debugPreviewTeamId: "example_owner"
            )
        }
    }
}

/// 駅伝**期間中**として脱退ボタンがグレーになる見た目を確認する
struct TeamViewInsideEkidenPeriodPreview: View {
    var body: some View {
        NavigationStack {
            TeamView(
                useMockTeamFlow: true,
                debugLeaveAllowedOverride: false,
                debugPreviewTeamId: "example_owner"
            )
        }
    }
}

#Preview("脱退・期間外UI") {
    TeamViewOutsideEkidenPeriodPreview()
}

#Preview("脱退・期間中（不可）") {
    TeamViewInsideEkidenPeriodPreview()
}
#endif
