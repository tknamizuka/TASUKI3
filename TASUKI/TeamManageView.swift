import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct TeamManageView: View {
    private let maxTeamMembers = 10
    let teamId: String
    @State private var requests: [JoinRequest] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    struct JoinRequest: Identifiable {
        let id: String
        let uid: String
        let requestedAt: Date
    }

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            VStack {
                if isLoading {
                    ProgressView()
                }

                if let err = errorMessage {
                    Text(err).foregroundColor(Color.tasukiAccentOrange)
                }

                List {
                    ForEach(requests) { req in
                        HStack {
                            Text(req.uid).foregroundColor(Color.tasukiPrimary)
                            Spacer()
                            Text(req.requestedAt, style: .date).foregroundColor(Color.tasukiMutedText)
                            Button("承認") {
                                approveRequest(req)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("拒否") {
                                denyRequest(req)
                            }
                            .tint(.red)
                        }
                        .listRowBackground(Color.tasukiDarkCard)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.tasukiDarkBackground)
                .refreshable {
                    await loadRequests()
                }
            }
        }
        .task {
            await loadRequests()
        }
        .navigationTitle("参加申請")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: EkidenLegAssignmentView(teamId: teamId)) {
                    Text("区間割当").foregroundColor(Color.tasukiPrimary)
                }
            }
        }
    }

    private func loadRequests() async {
        isLoading = true
        errorMessage = nil
        requests = []
        // プレビューやサンプル表示用: example / example_owner のときはモックデータを返す
        if teamId == "example" || teamId == "example_owner" {
            await MainActor.run {
                self.requests = [
                    JoinRequest(id: "r1", uid: "Kenji_Run", requestedAt: Date().addingTimeInterval(-3600)),
                    JoinRequest(id: "r2", uid: "さっちゃん", requestedAt: Date().addingTimeInterval(-86400)),
                    JoinRequest(id: "r3", uid: "Runner123", requestedAt: Date().addingTimeInterval(-3600 * 24 * 3))
                ]
                self.isLoading = false
            }
            return
        }

        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("teams").document(teamId).collection("joinRequests").getDocuments()
            var items: [JoinRequest] = []
            for doc in snapshot.documents {
                let data = doc.data()
                if let uid = data["uid"] as? String, let ts = data["requestedAt"] as? Timestamp {
                    items.append(JoinRequest(id: doc.documentID, uid: uid, requestedAt: ts.dateValue()))
                }
            }
            await MainActor.run {
                self.requests = items
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "申請の取得に失敗しました: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func approveRequest(_ req: JoinRequest) {
        let db = Firestore.firestore()
        Task {
            do {
                // プレビュー用: モックデータの場合はローカルの配列を更新する
                if teamId == "example" || teamId == "example_owner" {
                    await MainActor.run {
                        if let idx = requests.firstIndex(where: { $0.id == req.id }) {
                            requests.remove(at: idx)
                        }
                    }
                    return
                }

                // users/<uid>.teamId を設定
                let teamDoc = try await db.collection("teams").document(teamId).getDocument()
                let teamData = teamDoc.data() ?? [:]
                let members = teamData["members"] as? [String] ?? []
                let allowedMax = teamData["maxMembers"] as? Int ?? maxTeamMembers
                if !members.contains(req.uid), members.count >= allowedMax {
                    await MainActor.run {
                        self.errorMessage = "定員\(allowedMax)名に達しているため承認できません。"
                    }
                    return
                }

                try await db.collection("users").document(req.uid).setData(["teamId": teamId], merge: true)
                // teams/<teamId>.members に追加
                try await db.collection("teams").document(teamId).updateData(["members": FieldValue.arrayUnion([req.uid])])
                TeamLeavePolicy.clearLeaveBlock(teamId: teamId, userId: req.uid)
                // joinRequests ドキュメントを削除
                try await db.collection("teams").document(teamId).collection("joinRequests").document(req.id).delete()
                await loadRequests()
            } catch {
                await MainActor.run {
                    self.errorMessage = "承認処理に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func denyRequest(_ req: JoinRequest) {
        let db = Firestore.firestore()
        Task {
            do {
                if teamId == "example" || teamId == "example_owner" {
                    await MainActor.run {
                        if let idx = requests.firstIndex(where: { $0.id == req.id }) {
                            requests.remove(at: idx)
                        }
                    }
                    return
                }

                try await db.collection("teams").document(teamId).collection("joinRequests").document(req.id).delete()
                await loadRequests()
            } catch {
                await MainActor.run {
                    self.errorMessage = "拒否処理に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TeamManageView(teamId: "example")
    }
}
