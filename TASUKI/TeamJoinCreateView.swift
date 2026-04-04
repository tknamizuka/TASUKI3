import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TeamJoinCreateView: View {
    private let maxTeamMembers = 10
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
                
                VStack(spacing: 12) {
                    Button(action: { showSearchForm = true }) {
                        HStack { Spacer(); Text("チームを探す").foregroundColor(Color.tasukiOnBrandYellow); Spacer() }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiPrimaryButtonFill))
                    }
                    
                    Button(action: { showCreateForm = true }) {
                        HStack { Spacer(); Text("チームをつくる").foregroundColor(Color.tasukiOnBrandYellow); Spacer() }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiPrimaryButtonFill))
                    }
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
                    NavigationLink(destination: TeamDetailView(teamId: candidate.id, onJoined: { resultId in
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
            "ownerUid": firebaseUser.uid
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
                    // 招待コードで直接参加（モック）: メンバー視点の example_member に参加したことにする
                    self.isProcessing = false
                    self.onComplete?("example_member")
                    return
                }
                let prefix = self.searchNameInput.trimmingCharacters(in: .whitespaces)
                if prefix.isEmpty {
                    self.errorMessage = "検索キーワードを入力してください。"
                    self.isProcessing = false
                    return
                }
                // モックの検索結果（メンバーとして参加する想定のチーム）
                self.searchResults = [
                    TeamCandidate(id: "example_member", name: "皇居ランナーズ", requiresApproval: true, inviteCode: "EX1234")
                ]
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
                self.searchResults = [
                    TeamCandidate(id: "example_member", name: "皇居ランナーズ", requiresApproval: true, inviteCode: "EX1234")
                ]
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
                let candidates: [TeamCandidate] = docs.map { d in
                    TeamCandidate(id: d.documentID,
                                  name: d.data()["name"] as? String ?? "Unnamed",
                                  requiresApproval: d.data()["requiresApproval"] as? Bool ?? false,
                                  inviteCode: d.data()["inviteCode"] as? String)
                }
                self.searchResults = candidates
                self.showResultsSheet = true
            }
    }
    
    private func joinTeam(teamId: String, byInvite: Bool) {
        // モックフロー対応
        if useMockFlow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // サンプルチーム example_member は承認制にしておく
                let requiresApproval = (teamId == "example_member")
                self.isProcessing = false
                if requiresApproval && !byInvite {
                    // 申請送信だけ行った状態（まだ参加していない）
                    self.showSearchForm = false
                    self.onComplete?(nil)
                } else {
                    // 直接参加（メンバーとして参加完了）
                    self.showSearchForm = false
                    self.onComplete?("example_member")
                }
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
        teamRef.getDocument { snapshot, error in
            if let error = error {
                self.errorMessage = "チーム情報の取得に失敗しました: \(error.localizedDescription)"
                self.isProcessing = false
                return
            }
            
            guard let data = snapshot?.data() else {
                self.errorMessage = "チームが見つかりません。"
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
                // 承認制かつ招待コードでない場合は申請を作成
                let reqRef = teamRef.collection("joinRequests").document(firebaseUser.uid)
                reqRef.setData([
                    "uid": firebaseUser.uid,
                    "requestedAt": Timestamp(date: Date())
                ]) { err in
                    self.isProcessing = false
                    if let err = err {
                        self.errorMessage = "申請の送信に失敗しました: \(err.localizedDescription)"
                        return
                    }
                    DispatchQueue.main.async {
                        self.showSearchForm = false
                        self.onComplete?(nil)
                    }
                }
            } else {
                // 直接参加
                let userRef = db.collection("users").document(firebaseUser.uid)
                userRef.setData(["teamId": teamId], merge: true) { err in
                    if let err = err {
                        self.errorMessage = "ユーザー情報更新に失敗しました: \(err.localizedDescription)"
                        self.isProcessing = false
                        return
                    }
                    
                    teamRef.updateData(["members": FieldValue.arrayUnion([firebaseUser.uid])]) { mErr in
                        self.isProcessing = false
                        if let mErr = mErr {
                            self.errorMessage = "チーム参加に失敗しました: \(mErr.localizedDescription)"
                            return
                        }
                        
                        DispatchQueue.main.async {
                            self.showSearchForm = false
                            self.onComplete?(teamId)
                        }
                    }
                }
            }
        }
    }
    
    private func randomInviteCode(length: Int = 6) -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
}

