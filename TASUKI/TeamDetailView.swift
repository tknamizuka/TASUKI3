import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct TeamDetailView: View {
    private let maxTeamMembers = 10
    let teamId: String
    /// チーム参加ハブで選んだモードと一致しないチームは参加できない
    var expectedEkidenJoinMode: EkidenJoinMode? = nil
    var onJoined: ((String?) -> Void)? = nil   // 呼び出し元へ参加結果を返す

    @State private var teamData: [String: Any]? = nil
    @State private var memberUIDs: [String] = []
    @State private var membersInfo: [String] = []
    @State private var ownerUid: String? = nil
    @State private var showingShare: Bool = false
    @State private var shareText: String = ""
    @State private var showManage: Bool = false
    @State private var alertMessage: String? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let data = teamData {
                HStack(alignment: .center, spacing: 12) {
                    Text(data["name"] as? String ?? "Team")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                    let total = (data["teamTotalPoints"] as? Int) ?? PointService.shared.teamTotalPoints(teamId: teamId)
                    let tier = TeamRankTier.tier(forTeamPoints: total)
                    Text(tier.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(tier.color.opacity(0.2)))
                        .foregroundColor(tier.color)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(total)pt")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                        Text("累計")
                            .font(.system(size: 10))
                            .foregroundColor(Color.tasukiMutedText)
                    }
                }
                .padding(.horizontal, 20)

                HStack {
                    Text("招待コード: ")
                    Text(data["inviteCode"] as? String ?? "—")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button(action: {
                        let code = data["inviteCode"] as? String ?? ""
                        shareText = "チームに参加する招待コード: \(code)"
                        showingShare = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(Color.tasukiPrimary)
                    }
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 20)

                HStack {
                    Text("承認制: ")
                    Text((data["requiresApproval"] as? Bool ?? false) ? "あり" : "なし")
                    Spacer()
                }
                .padding(.horizontal, 20)

                Divider()

                Text("メンバー")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                Text("\(memberUIDs.count)/\(resolvedMaxMembers)名")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)

                if let expected = expectedEkidenJoinMode, !expected.matchesTeamDocument(data) {
                    Text("このチームは、駅伝の参加画面で選んだモード（\(expected.shortLabel)）のチームではありません。「モード」から切り替えるか、別のチームを探してください。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.tasukiAccentOrange)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 20)
                }

                if membersInfo.isEmpty {
                    Text("メンバー情報を取得中…")
                        .foregroundColor(Color.tasukiMutedText)
                } else {
                    List(membersInfo, id: \.self) { info in
                        Text(info).foregroundColor(Color.tasukiPrimary)
                            .listRowBackground(Color.tasukiDarkCard)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.tasukiDarkBackground)
                }

                // 参加ボタン（自分がメンバーでもオーナーでもない場合のみ）
                let modeBlocksJoin = expectedEkidenJoinMode.map { !$0.matchesTeamDocument(data) } ?? false
                if let currentUid = effectiveCurrentUid,
                   !memberUIDs.contains(currentUid),
                   ownerUid != currentUid,
                   memberUIDs.count < resolvedMaxMembers,
                   !modeBlocksJoin {
                    Button(action: { Task { await joinCurrentTeam() } }) {
                        HStack {
                            Spacer()
                            Text("このチームに参加する")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                if memberUIDs.count >= resolvedMaxMembers {
                    Text("このチームは定員\(resolvedMaxMembers)名に達しています。")
                        .font(.system(size: 13))
                        .foregroundColor(Color.tasukiMutedText)
                        .padding(.top, 8)
                }
            } else {
                Text("チーム情報を読み込み中…")
                    .foregroundColor(Color.tasukiMutedText)
            }
            }
        }
        .navigationTitle("チーム詳細")
        .toolbar {
            if let currentUid = effectiveCurrentUid, ownerUid == currentUid {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink(destination: EkidenLegAssignmentView(teamId: teamId)) {
                            Text("区間割当").foregroundColor(Color.tasukiPrimary)
                        }
                        NavigationLink(destination: TeamManageView(teamId: teamId)) {
                            Text("参加申請").foregroundColor(Color.tasukiPrimary)
                        }
                    }
                }
            }
        }
        .alert(alertMessage ?? "", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task {
            await loadTeam()
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(activityItems: [shareText])
        }
    }

    private var resolvedMaxMembers: Int {
        (teamData?["maxMembers"] as? Int) ?? maxTeamMembers
    }
    
    /// サンプル用: 未ログインでも teamId に応じて「自分のUID相当」を決める
    private var effectiveCurrentUid: String? {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        switch teamId {
        case "example_owner":
            return "sample_owner"
        case "example_member", "example_ekiden_real":
            return "sample_member"
        default:
            return nil
        }
    }

    // MARK: - チーム参加処理
    private func joinCurrentTeam() async {
        let teamName = teamData?["name"] as? String
        if await TeamLeavePolicy.isRejoinBlocked(teamId: teamId, isMock: teamId == "example_member" || teamId == "example_ekiden_real") {
            await MainActor.run {
                alertMessage = TeamLeavePolicy.rejoinBlockedMessage(teamName: teamName)
            }
            return
        }
        
        // サンプルチーム（example_member / example_ekiden_real）の場合はローカルで擬似参加処理のみ行う
        if teamId == "example_member" || teamId == "example_ekiden_real", let currentUid = effectiveCurrentUid {
            await MainActor.run {
                if let expected = expectedEkidenJoinMode, let data = teamData, !expected.matchesTeamDocument(data) {
                    alertMessage = "このチームは選択中のEKIDENモードのチームではありません。"
                    return
                }
                if memberUIDs.count >= resolvedMaxMembers {
                    alertMessage = "このチームは定員\(resolvedMaxMembers)名に達しています。"
                    return
                }
                if !memberUIDs.contains(currentUid) {
                    memberUIDs.append(currentUid)
                    membersInfo.append("あなた")
                }
                TeamLeavePolicy.clearLeaveBlock(teamId: teamId, isMock: true)
                alertMessage = "チームに参加しました。（サンプル）"
                onJoined?(teamId)
            }
            return
        }
        
        guard let currentUid = Auth.auth().currentUser?.uid else {
            alertMessage = "ログインユーザーが見つかりません。"
            return
        }
        let db = Firestore.firestore()
        let teamRef = db.collection("teams").document(teamId)
        do {
            let snap = try await teamRef.getDocument()
            guard let data = snap.data() else {
                alertMessage = "チームが見つかりません。"
                return
            }
            if let expected = expectedEkidenJoinMode, !expected.matchesTeamDocument(data) {
                alertMessage = "このチームは選択中のEKIDENモードのチームではありません。"
                return
            }
            let requiresApproval = data["requiresApproval"] as? Bool ?? false
            let members = data["members"] as? [String] ?? []
            let maxMembers = data["maxMembers"] as? Int ?? maxTeamMembers
            if !members.contains(currentUid), members.count >= maxMembers {
                alertMessage = "このチームは定員\(maxMembers)名に達しています。"
                return
            }
            if requiresApproval {
                // 申請を送る
                let reqRef = teamRef.collection("joinRequests").document(currentUid)
                try await reqRef.setData([
                    "uid": currentUid,
                    "requestedAt": Timestamp(date: Date())
                ])
                alertMessage = "参加申請を送信しました。"
                onJoined?(nil)
            } else {
                // 直接参加
                let userRef = db.collection("users").document(currentUid)
                try await userRef.setData(["teamId": teamId], merge: true)
                try await teamRef.updateData(["members": FieldValue.arrayUnion([currentUid])])
                TeamLeavePolicy.clearLeaveBlock(teamId: teamId, isMock: false)
                alertMessage = "チームに参加しました。"
                onJoined?(teamId)
            }
        } catch {
            alertMessage = "参加に失敗しました: \(error.localizedDescription)"
        }
    }

    private func loadTeam() async {
        // プレビュー/サンプル用（オーナー視点）
        if teamId == "example_owner" {
            await MainActor.run {
                self.teamData = [
                    "name": "皇居ランナーズ",
                    "inviteCode": "EX1234",
                    "requiresApproval": true,
                    "ekidenMode": EkidenJoinMode.realEkiden.rawValue,
                    "members": ["sample_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                ]
                self.memberUIDs = ["sample_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                self.ownerUid = "sample_owner"
                self.membersInfo = ["あなた（オーナー）", "Kenji_Run", "さっちゃん", "Taka@Sub3", "Momo", "Runner123", "Yuki"]
            }
            return
        }
        // プレビュー/サンプル用（メンバー視点）
        if teamId == "example_member" {
            await MainActor.run {
                self.teamData = [
                    "name": "Enjoy EKIDEN サンプルチーム",
                    "inviteCode": "EX1234",
                    "requiresApproval": true,
                    "ekidenMode": EkidenJoinMode.enjoyEkiden.rawValue,
                    "members": ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                ]
                self.memberUIDs = ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                self.ownerUid = "u_owner"
                self.membersInfo = ["Kenji_Run", "さっちゃん", "Taka@Sub3", "Momo", "Runner123", "Yuki"]
            }
            return
        }
        if teamId == "example_ekiden_real" {
            await MainActor.run {
                self.teamData = [
                    "name": "リアルEKIDEN サンプルチーム",
                    "inviteCode": "RL5678",
                    "requiresApproval": true,
                    "ekidenMode": EkidenJoinMode.realEkiden.rawValue,
                    "members": ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                ]
                self.memberUIDs = ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                self.ownerUid = "u_owner"
                self.membersInfo = ["Kenji_Run", "さっちゃん", "Taka@Sub3", "Momo", "Runner123", "Yuki"]
            }
            return
        }

        let db = Firestore.firestore()
        let doc = try? await db.collection("teams").document(teamId).getDocument()
        if let data = doc?.data() {
            await MainActor.run {
                self.teamData = data
                self.memberUIDs = data["members"] as? [String] ?? []
                self.ownerUid = data["ownerUid"] as? String
            }

            // 簡易的に各UIDからユーザー名を読み取る
            var infos: [String] = []
            for uid in memberUIDs {
                if let userDoc = try? await db.collection("users").document(uid).getDocument(), let udata = userDoc.data() {
                    let name = udata["name"] as? String ?? uid
                    infos.append(name)
                } else {
                    infos.append(uid)
                }
            }
            await MainActor.run {
                self.membersInfo = infos
            }
        }
    }

    struct ShareSheet: UIViewControllerRepresentable {
        let activityItems: [Any]
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
}

#Preview {
    NavigationStack {
        TeamDetailView(teamId: "example")
            .onAppear {
                // プレビュー時は未ログインのため UID が nil。
                // Anonymous login でダミーUIDを作成するとボタンが見える。
                if Auth.auth().currentUser == nil {
                    Auth.auth().signInAnonymously { _, _ in }
                }
            }
    }
}
