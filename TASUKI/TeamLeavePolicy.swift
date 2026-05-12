import Foundation
import FirebaseAuth
import FirebaseFirestore

/// チーム脱退・再加入（同一シーズン不可）のルール
enum TeamLeavePolicy {
    private static let mockStorageKey = "teamLeaveFiscalYearByTeamId"
    private static let teamLeaveHistoryField = "teamLeaveHistory"
    
    /// 4月始まりの「駅伝シーズン」に相当する年度キー（4月〜翌3月が同じ年度）
    static func fiscalYear(containing date: Date = Date()) -> Int {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return m >= 4 ? y : y - 1
    }
    
    // MARK: - Mock (UserDefaults)
    
    private static func loadMockMap() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: mockStorageKey),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return map
    }
    
    private static func saveMockMap(_ map: [String: Int]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: mockStorageKey)
        }
    }
    
    /// 脱退を記録（その年度内は同チームへ再加入不可）
    static func recordLeave(teamId: String, isMock: Bool) {
        guard !teamId.isEmpty else { return }
        let fy = fiscalYear()
        if isMock {
            var m = loadMockMap()
            m[teamId] = fy
            saveMockMap(m)
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).setData([
            "\(teamLeaveHistoryField).\(teamId)": fy
        ], merge: true)
    }
    
    /// 再加入時にブロック記録を消す（参加が完了したとき・ログイン中ユーザー）
    static func clearLeaveBlock(teamId: String, isMock: Bool) {
        guard !teamId.isEmpty else { return }
        if isMock {
            var m = loadMockMap()
            m.removeValue(forKey: teamId)
            saveMockMap(m)
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        clearLeaveBlock(teamId: teamId, userId: uid)
    }
    
    /// 承認などで別ユーザーの再加入ブロックを消す
    static func clearLeaveBlock(teamId: String, userId: String) {
        guard !teamId.isEmpty, !userId.isEmpty else { return }
        Firestore.firestore().collection("users").document(userId).updateData([
            "\(teamLeaveHistoryField).\(teamId)": FieldValue.delete()
        ])
    }
    
    /// 同じ年度内に脱退したチームへは再加入できない
    static func isRejoinBlocked(teamId: String, isMock: Bool) async -> Bool {
        guard !teamId.isEmpty else { return false }
        let nowFY = fiscalYear()
        if isMock {
            guard let leftFY = loadMockMap()[teamId] else { return false }
            return leftFY == nowFY
        }
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let map = snap.data()?[teamLeaveHistoryField] as? [String: Int]
            guard let leftFY = map?[teamId] else { return false }
            return leftFY == nowFY
        } catch {
            return false
        }
    }
    
    static func rejoinBlockedMessage(teamName: String? = nil) -> String {
        let suffix = teamName.map { "（\($0)）" } ?? ""
        return "このシーズン（4月〜翌3月）に脱退したチーム\(suffix)へは、次のシーズンまで再加入できません。"
    }
}
