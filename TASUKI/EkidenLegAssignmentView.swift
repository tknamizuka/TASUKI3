//
//  EkidenLegAssignmentView.swift
//  TASUKI
//
//  オーナー向け区間メンバー割当・走順確定UI
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// 区間割当の1行（legIndex は 0=1区）
struct LegAssignmentRow: Identifiable {
    let id: Int
    var assignedUid: String?
    let displayName: String  // 表示用（例: "1区"）
}

struct EkidenLegAssignmentView: View {
    private let maxTeamMembers = 10
    let teamId: String

    @State private var memberUIDs: [String] = []
    @State private var memberNames: [String: String] = [:]  // uid -> name
    @State private var assignments: [LegAssignmentRow] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var ownerUid: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    headerSection

                    if memberUIDs.isEmpty {
                        emptyStateView
                    } else {
                        assignmentList
                        confirmButton
                    }
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(Color.tasukiAccentOrange)
                        .padding(.horizontal)
                }
                if let msg = successMessage {
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .navigationTitle("区間割当")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTeamAndAssignments()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("走順（1区〜\(assignments.count)区）を確定してください。")
                .font(.system(size: 14))
                .foregroundColor(Color.tasukiMutedText)
            Text("各区間に担当メンバーを割り当て、確定ボタンを押してください。")
                .font(.system(size: 13))
                .foregroundColor(Color.tasukiMutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundColor(Color.tasukiMutedText)
            Text("メンバーがいません")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
            Text("チームにメンバーを追加してから区間割当を行ってください。")
                .font(.system(size: 13))
                .foregroundColor(Color.tasukiMutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var assignmentList: some View {
        List {
            ForEach(Array(assignments.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text(row.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(width: 44, alignment: .leading)

                    Picker(row.displayName, selection: Binding(
                        get: { assignments[index].assignedUid ?? "" },
                        set: { newVal in
                            assignments[index].assignedUid = newVal.isEmpty ? nil : newVal
                        }
                    )) {
                        Text("未割当").tag("")
                        ForEach(memberUIDs, id: \.self) { uid in
                            Text(memberDisplayName(uid: uid))
                                .tag(uid)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.tasukiPrimary)
                }
                .listRowBackground(Color.tasukiDarkCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tasukiDarkBackground)
    }

    private var confirmButton: some View {
        Button(action: { Task { await saveAssignments() } }) {
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("確定")
                        .font(.system(size: 16, weight: .semibold))
                }
                Spacer()
            }
            .foregroundColor(isSaving ? Color.white : Color.tasukiOnBrandYellow)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSaving ? Color.gray : Color.tasukiPrimaryButtonFill)
            )
        }
        .disabled(isSaving || !isValid)
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    private var isValid: Bool {
        let assigned = assignments.compactMap { $0.assignedUid }
        let unique = Set(assigned)
        // 全区間に割当があり、重複がないこと
        return assigned.count == assignments.count && unique.count == assigned.count
    }

    private func memberDisplayName(uid: String) -> String {
        memberNames[uid] ?? uid
    }

    private func loadTeamAndAssignments() async {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        if teamId == "example" || teamId == "example_owner" {
            await MainActor.run {
                memberUIDs = ["sample_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                memberNames = [
                    "sample_owner": "あなた（オーナー）",
                    "u_kenji": "Kenji_Run",
                    "u_sacchan": "さっちゃん",
                    "u_taka": "Taka@Sub3",
                    "u_momo": "Momo",
                    "u_runner123": "Runner123",
                    "u_yuki": "Yuki"
                ]
                ownerUid = "sample_owner"
                assignments = (0..<memberUIDs.count).map { i in
                    LegAssignmentRow(
                        id: i,
                        assignedUid: memberUIDs.indices.contains(i) ? memberUIDs[i] : nil,
                        displayName: "\(i + 1)区"
                    )
                }
                isLoading = false
            }
            return
        }
        if teamId == "example_member" {
            await MainActor.run {
                memberUIDs = ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
                memberNames = [
                    "u_owner": "オーナー",
                    "u_kenji": "Kenji_Run",
                    "u_sacchan": "さっちゃん",
                    "u_taka": "Taka@Sub3",
                    "u_momo": "Momo",
                    "u_runner123": "Runner123",
                    "u_yuki": "Yuki"
                ]
                ownerUid = "u_owner"
                assignments = (0..<memberUIDs.count).map { i in
                    LegAssignmentRow(
                        id: i,
                        assignedUid: memberUIDs.indices.contains(i) ? memberUIDs[i] : nil,
                        displayName: "\(i + 1)区"
                    )
                }
                isLoading = false
            }
            return
        }

        let db = Firestore.firestore()
        do {
            let teamDoc = try await db.collection("teams").document(teamId).getDocument()
            guard let data = teamDoc.data() else {
                await MainActor.run {
                    errorMessage = "チームが見つかりません。"
                    isLoading = false
                }
                return
            }

            let members = data["members"] as? [String] ?? []
            let owner = data["ownerUid"] as? String

            var names: [String: String] = [:]
            for uid in members {
                if let userDoc = try? await db.collection("users").document(uid).getDocument(),
                   let udata = userDoc.data(),
                   let name = udata["name"] as? String {
                    names[uid] = name
                } else {
                    names[uid] = uid
                }
            }

            let legCount = min(members.count, maxTeamMembers)
            var rows: [LegAssignmentRow] = []

            let templateRef = db.collection("teams").document(teamId)
                .collection("ekidenLegTemplate").document("default")
            let templateDoc = try? await templateRef.getDocument()
            let savedAssignments = templateDoc?.data()?["assignments"] as? [[String: Any]]

            for i in 0..<legCount {
                var assignedUid: String?
                if let saved = savedAssignments, i < saved.count,
                   let uid = saved[i]["assignedUid"] as? String, members.contains(uid) {
                    assignedUid = uid
                }
                rows.append(LegAssignmentRow(
                    id: i,
                    assignedUid: assignedUid,
                    displayName: "\(i + 1)区"
                ))
            }

            await MainActor.run {
                self.memberUIDs = members
                self.memberNames = names
                self.ownerUid = owner
                self.assignments = rows
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "読み込みに失敗しました: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func saveAssignments() async {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil
        successMessage = nil

        if teamId == "example" || teamId == "example_owner" || teamId == "example_member" {
            await MainActor.run {
                successMessage = "区間割当を確定しました。（サンプル）"
                isSaving = false
            }
            return
        }

        guard let currentUid = Auth.auth().currentUser?.uid,
              currentUid == ownerUid else {
            await MainActor.run {
                errorMessage = "オーナーのみ区間割当を変更できます。"
                isSaving = false
            }
            return
        }

        let db = Firestore.firestore()
        let assignmentsData = assignments.map { row -> [String: Any] in
            var d: [String: Any] = ["legIndex": row.id]
            if let uid = row.assignedUid {
                d["assignedUid"] = uid
            }
            return d
        }

        do {
            try await db.collection("teams").document(teamId)
                .collection("ekidenLegTemplate").document("default")
                .setData([
                    "assignments": assignmentsData,
                    "legCount": assignments.count,
                    "updatedAt": Timestamp(date: Date()),
                    "updatedBy": currentUid
                ])

            await MainActor.run {
                successMessage = "区間割当を確定しました。"
                isSaving = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "保存に失敗しました: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        EkidenLegAssignmentView(teamId: "example_owner")
    }
}
