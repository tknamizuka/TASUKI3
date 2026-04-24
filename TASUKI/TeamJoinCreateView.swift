import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TeamJoinCreateView: View {
    private let maxTeamMembers = 10
    /// この画面で扱うチームはこのモードに一致するもののみ（検索・ランダム・参加）
    let ekidenJoinMode: EkidenJoinMode
    var onComplete: ((String?) -> Void)? = nil
    var useMockFlow: Bool = false
    
    @State private var showCreateForm: Bool = false
    @State private var showSearchForm: Bool = false
    @State private var teamNameInput: String = ""
    @State private var searchNameInput: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var requiresApproval: Bool = false
    @State private var createdInviteCode: String? = nil
    @State private var searchResults: [TeamCandidate] = []
    @State private var showResultsSheet: Bool = false
    
    struct TeamCandidate: Identifiable {
        let id: String
        let name: String
        let requiresApproval: Bool
        let inviteCode: String?
    }
    
    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                
                Text("チームに所属していません")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                
                Text("EKIDENに参加するにはチームに参加するか、新しくチームを作成してください。")
                    .font(.system(size: 14))
                    .foregroundColor(Color.tasukiMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("参加モード: \(ekidenJoinMode.displayTitle)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.85))
                
                VStack(spacing: 12) {
                    Button(action: { showSearchForm = true }) {
                        HStack {
                            Spacer()
                            Text("チームを探す")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                            Spacer()
                        }
                        .frame(minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    Button(action: { showCreateForm = true }) {
                        HStack {
                            Spacer()
                            Text("チームをつくる")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                            Spacer()
                        }
                        .frame(minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    Button(action: joinRandomAvailableTeam) {
                        HStack {
                            Spacer()
                            Text(isProcessing ? "検索中..." : "空きチームにランダム参加")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                            Spacer()
                        }
                        .frame(minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing)

                    Text("定員に空きがあり、再加入ブロックのないチームからランダムに選びます（承認不要を優先）。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.tasukiMutedText.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.horizontal, 40)
                
                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(Color.tasukiAccentOrange)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                
                Spacer()
            }
        }
        .sheet(isPresented: $showCreateForm) {
            NavigationStack {
                Form {
                    Section("チーム情報") {
                        TextField("チーム名", text: $teamNameInput)
                        Toggle("参加は承認制にする", isOn: $requiresApproval)
                    }
                    
                    Section {
                        Button(action: createTeam) {
                            HStack { Spacer(); Text(isProcessing ? "作成中..." : "チームを作成") ; Spacer() }
                        }
                        .disabled(teamNameInput.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
                    }
                    
                    if let code = createdInviteCode {
                        Section("招待コード") {
                            HStack { Text(code); Spacer(); Button("コピー") { UIPasteboard.general.string = code } }
                        }
                    }
                }
                .navigationTitle("チームをつくる")
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("閉じる") { showCreateForm = false } } }
            }
        }
        .sheet(isPresented: $showSearchForm) {
            NavigationStack {
                Form {
                    Section("検索") {
                        TextField("チーム名で検索（プレフィックス一致）", text: $searchNameInput)
                        TextField("または招待コードで参加（任意）", text: $teamNameInput)
                    }
                    Section {
                        Button(action: searchAndJoin) {
                            HStack { Spacer(); Text(isProcessing ? "検索中..." : "チームを探す") ; Spacer() }
                        }
                        .disabled((searchNameInput.trimmingCharacters(in: .whitespaces).isEmpty && teamNameInput.trimmingCharacters(in: .whitespaces).isEmpty) || isProcessing)
                    }
                }
                .navigationTitle("チームを探す")
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("閉じる") { showSearchForm = false } } }
            }
        }
        
        // 検索結果選択シート
        .sheet(isPresented: $showResultsSheet) {
            NavigationStack {
                List(searchResults) { candidate in
                    NavigationLink(destination: TeamDetailView(teamId: candidate.id, expectedEkidenJoinMode: ekidenJoinMode, onJoined: { resultId in
                        // 詳細画面から戻ったときの処理
                        showResultsSheet = false
                        self.onComplete?(resultId)
                    })) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(candidate.name).font(.system(size: 16, weight: .semibold))
                                Text(candidate.requiresApproval ? "承認制" : "自動参加可").font(.system(size: 12)).foregroundColor(.gray)
                            }
                            Spacer()
                            if let code = candidate.inviteCode {
                                Text(code).font(.system(size: 12)).foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .navigationTitle("検索結果")
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("閉じる") { showResultsSheet = false } } }
            }
        }
    }
    
    private func createTeam() {
        guard !isProcessing else { return }
        isProcessing = true
        errorMessage = nil
        
        // モックフロー（プレビュー/未ログイン時など）: サンプルチームをオーナーとして作成した状態を再現
        if useMockFlow {
            let inviteCode = randomInviteCode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.createdInviteCode = inviteCode
                self.isProcessing = false
                self.showCreateForm = false
                // サンプルチームIDとして「オーナー視点」の example_owner を返す
                self.onComplete?("example_owner")
            }
            return
        }

        let db = Firestore.firestore()
        
        // ログインユーザーを先に確保して ownerUid を含めて作成
        guard let firebaseUser = Auth.auth().currentUser else {
            self.errorMessage = "ログインユーザーが見つかりません。"
            self.isProcessing = false
            return
        }
        
        // 新しいチームドキュメントを作成（招待コード、承認設定、ownerUid を含む）
        let newTeamRef = db.collection("teams").document()
        let inviteCode = randomInviteCode()
        let teamData: [String: Any] = [
            "name": teamNameInput,
            "createdAt": Timestamp(date: Date()),
            "members": [],
            "inviteCode": inviteCode,
            "requiresApproval": requiresApproval,
            "maxMembers": maxTeamMembers,
            "ownerUid": firebaseUser.uid,
            "ekidenMode": ekidenJoinMode.firestoreValue
        ]
        
        newTeamRef.setData(teamData) { error in
            if let error = error {
                self.errorMessage = "チーム作成に失敗しました: \(error.localizedDescription)"
                self.isProcessing = false
                return
            }
            // 作成成功 -> users/<uid>.teamId を設定
            let teamId = newTeamRef.documentID
            let userRef = db.collection("users").document(firebaseUser.uid)
            userRef.setData(["teamId": teamId], merge: true) { err in
                if let err = err {
                    self.errorMessage = "ユーザー情報更新に失敗しました: \(err.localizedDescription)"
                    self.isProcessing = false
                    return
                }
                
                // 作成者は自動的にメンバーに追加
                newTeamRef.updateData(["members": FieldValue.arrayUnion([firebaseUser.uid])]) { mErr in
                    self.isProcessing = false
                    if let mErr = mErr {
                        self.errorMessage = "メンバー追加に失敗しました: \(mErr.localizedDescription)"
                        return
                    }
                    
                    // 完了
                    DispatchQueue.main.async {
                        self.createdInviteCode = inviteCode
                        showCreateForm = false
                        onComplete?(teamId)
                    }
                }
            }
        }
    }
    
    /// 取得したチーム一覧から、空き枠のあるチームへランダム参加（承認不要を優先）。
    private func joinRandomAvailableTeam() {
        guard !isProcessing else { return }
        isProcessing = true
        errorMessage = nil

        if useMockFlow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                let mockId = ekidenJoinMode == .realEkiden ? "example_ekiden_real" : "example_member"
                TeamLeavePolicy.clearLeaveBlock(teamId: mockId, isMock: true)
                self.isProcessing = false
                self.onComplete?(mockId)
            }
            return
        }

        guard Auth.auth().currentUser != nil else {
            errorMessage = "ログインユーザーが見つかりません。"
            isProcessing = false
            return
        }

        Task { @MainActor in
            let db = Firestore.firestore()
            do {
                let snap = try await db.collection("teams").limit(to: 50).getDocuments()
                guard let uid = Auth.auth().currentUser?.uid else {
                    self.errorMessage = "ログインユーザーが見つかりません。"
                    self.isProcessing = false
                    return
                }

                var openTeams: [TeamCandidate] = []
                var approvalTeams: [TeamCandidate] = []

                for doc in snap.documents.shuffled() {
                    let data = doc.data()
                    guard ekidenJoinMode.matchesTeamDocument(data) else { continue }
                    let members = data["members"] as? [String] ?? []
                    let maxM = data["maxMembers"] as? Int ?? maxTeamMembers
                    let requiresApproval = data["requiresApproval"] as? Bool ?? false
                    guard !members.contains(uid), members.count < maxM else { continue }
                    if await TeamLeavePolicy.isRejoinBlocked(teamId: doc.documentID, isMock: false) { continue }

                    let cand = TeamCandidate(
                        id: doc.documentID,
                        name: data["name"] as? String ?? "Unnamed",
                        requiresApproval: requiresApproval,
                        inviteCode: data["inviteCode"] as? String
                    )
                    if requiresApproval {
                        approvalTeams.append(cand)
                    } else {
                        openTeams.append(cand)
                    }
                }

                let pool = openTeams.isEmpty ? approvalTeams : openTeams
                guard let pick = pool.randomElement() else {
                    self.errorMessage = "参加可能な空きチームが見つかりませんでした。検索または新規作成をお試しください。"
                    self.isProcessing = false
                    return
                }

                joinTeam(teamId: pick.id, byInvite: false)
            } catch {
                self.errorMessage = "チーム一覧の取得に失敗しました: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }

    private func searchAndJoin() {
        guard !isProcessing else { return }
        isProcessing = true
        errorMessage = nil
        // immediately dismiss the search form so results (or join flows) aren't hidden behind it
        showSearchForm = false
        
        // モックフロー
        if useMockFlow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if !self.teamNameInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    let mockId = self.ekidenJoinMode == .realEkiden ? "example_ekiden_real" : "example_member"
                    self.isProcessing = false
                    self.onComplete?(mockId)
                    return
                }
                let prefix = self.searchNameInput.trimmingCharacters(in: .whitespaces)
                if prefix.isEmpty {
                    self.errorMessage = "検索キーワードを入力してください。"
                    self.isProcessing = false
                    return
                }
                let mockCandidate: TeamCandidate = self.ekidenJoinMode == .realEkiden
                    ? TeamCandidate(id: "example_ekiden_real", name: "リアルEKIDEN サンプルチーム", requiresApproval: true, inviteCode: "RL5678")
                    : TeamCandidate(id: "example_member", name: "Enjoy EKIDEN サンプルチーム", requiresApproval: true, inviteCode: "EX1234")
                self.searchResults = [mockCandidate]
                self.isProcessing = false
                self.showResultsSheet = true
            }
            return
        }

        let db = Firestore.firestore()
        
        // まず招待コードで検索（teamNameInput を招待コードとして使う）
        self.isProcessing = true
        self.errorMessage = nil
        
        if !teamNameInput.trimmingCharacters(in: .whitespaces).isEmpty {
            // 招待コードで参加
            db.collection("teams")
                .whereField("inviteCode", isEqualTo: teamNameInput.trimmingCharacters(in: .whitespaces))
                .limit(to: 1)
                .getDocuments { snapshot, error in
                    if let error = error {
                        self.errorMessage = "検索に失敗しました: \(error.localizedDescription)"
                        self.isProcessing = false
                        return
                    }
                    
                    if let doc = snapshot?.documents.first {
                        let teamId = doc.documentID
                        joinTeam(teamId: teamId, byInvite: true)
                        return
                    }
                    
                    // 招待コード一致なし -> 続けて名前検索にフォールバック
                    self.performNamePrefixSearch(db: db)
                }
        } else {
            // 名前検索
            performNamePrefixSearch(db: db)
        }
    }
    
    private func performNamePrefixSearch(db: Firestore) {
        // モックフロー: useMockFlow が有効ならモック結果を返す
        let prefix = searchNameInput.trimmingCharacters(in: .whitespaces)
        if useMockFlow {
            guard !prefix.isEmpty else {
                self.errorMessage = "検索キーワードを入力してください。"
                self.isProcessing = false
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let mockCandidate: TeamCandidate = self.ekidenJoinMode == .realEkiden
                    ? TeamCandidate(id: "example_ekiden_real", name: "リアルEKIDEN サンプルチーム", requiresApproval: true, inviteCode: "RL5678")
                    : TeamCandidate(id: "example_member", name: "Enjoy EKIDEN サンプルチーム", requiresApproval: true, inviteCode: "EX1234")
                self.searchResults = [mockCandidate]
                self.isProcessing = false
                self.showResultsSheet = true
            }
            return
        }

        let prefixNonEmpty = prefix
        guard !prefixNonEmpty.isEmpty else {
            self.errorMessage = "検索キーワードを入力してください。"
            self.isProcessing = false
            return
        }
        
        // Firestore のプレフィックス検索（range）
        let end = prefixNonEmpty + "\u{f8ff}"
        db.collection("teams")
            .whereField("name", isGreaterThanOrEqualTo: prefixNonEmpty)
            .whereField("name", isLessThanOrEqualTo: end)
            .limit(to: 10)
            .getDocuments { snapshot, error in
                self.isProcessing = false
                if let error = error {
                    self.errorMessage = "検索に失敗しました: \(error.localizedDescription)"
                    return
                }
                
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    self.errorMessage = "該当するチームが見つかりません。"
                    return
                }
                
                // 結果を候補リストとして表示
                let candidates: [TeamCandidate] = docs.compactMap { d -> TeamCandidate? in
                    let data = d.data()
                    guard self.ekidenJoinMode.matchesTeamDocument(data) else { return nil }
                    return TeamCandidate(
                        id: d.documentID,
                        name: data["name"] as? String ?? "Unnamed",
                        requiresApproval: data["requiresApproval"] as? Bool ?? false,
                        inviteCode: data["inviteCode"] as? String
                    )
                }
                guard !candidates.isEmpty else {
                    self.errorMessage = "このモードに該当するチームが見つかりません。"
                    return
                }
                self.searchResults = candidates
                self.showResultsSheet = true
            }
    }
    
    private func joinTeam(teamId: String, byInvite: Bool) {
        Task { @MainActor in
            if await TeamLeavePolicy.isRejoinBlocked(teamId: teamId, isMock: useMockFlow) {
                self.errorMessage = TeamLeavePolicy.rejoinBlockedMessage()
                self.isProcessing = false
                return
            }
            
            if useMockFlow {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let requiresApproval = (teamId == "example_member" || teamId == "example_ekiden_real")
                self.isProcessing = false
                if requiresApproval && !byInvite {
                    self.showSearchForm = false
                    self.onComplete?(nil)
                } else {
                    TeamLeavePolicy.clearLeaveBlock(teamId: teamId, isMock: true)
                    self.showSearchForm = false
                    self.onComplete?(teamId)
                }
                return
            }

            guard let firebaseUser = Auth.auth().currentUser else {
                self.errorMessage = "ログインユーザーが見つかりません。"
                self.isProcessing = false
                return
            }
            
            let db = Firestore.firestore()
            let teamRef = db.collection("teams").document(teamId)
            do {
                let snapshot = try await teamRef.getDocument()
                guard let data = snapshot.data() else {
                    self.errorMessage = "チームが見つかりません。"
                    self.isProcessing = false
                    return
                }

                guard self.ekidenJoinMode.matchesTeamDocument(data) else {
                    self.errorMessage = "このチームは、今選んでいるEKIDENモード（\(self.ekidenJoinMode.shortLabel)）のチームではありません。"
                    self.isProcessing = false
                    return
                }
                
                let requiresApproval = data["requiresApproval"] as? Bool ?? false
                let members = data["members"] as? [String] ?? []
                let maxMembers = data["maxMembers"] as? Int ?? maxTeamMembers

                if !members.contains(firebaseUser.uid), members.count >= maxMembers {
                    self.errorMessage = "このチームは定員\(maxMembers)名に達しています。"
                    self.isProcessing = false
                    return
                }
                
                if requiresApproval && !byInvite {
                    let reqRef = teamRef.collection("joinRequests").document(firebaseUser.uid)
                    try await reqRef.setData([
                        "uid": firebaseUser.uid,
                        "requestedAt": Timestamp(date: Date())
                    ])
                    self.isProcessing = false
                    self.showSearchForm = false
                    self.onComplete?(nil)
                } else {
                    let userRef = db.collection("users").document(firebaseUser.uid)
                    try await userRef.setData(["teamId": teamId], merge: true)
                    try await teamRef.updateData(["members": FieldValue.arrayUnion([firebaseUser.uid])])
                    TeamLeavePolicy.clearLeaveBlock(teamId: teamId, isMock: false)
                    self.isProcessing = false
                    self.showSearchForm = false
                    self.onComplete?(teamId)
                }
            } catch {
                self.errorMessage = "チーム参加に失敗しました: \(error.localizedDescription)"
                self.isProcessing = false
            }
        }
    }
    
    private func randomInviteCode(length: Int = 6) -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
}

