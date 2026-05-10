import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

/// TASUKI 内の「ポイント」を管理する。
/// ローカル（UserDefaults）で UI を即時反映し、Firestore への反映は Cloud Functions（grantActivityPoints / grantTeamActivityPoints）経由。
final class PointService {
    static let shared = PointService()
    
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "asia-northeast1")

    private init() {}
    
    // MARK: - Public API
    
    /// タイムトライアルなどで獲得したポイントを現在ユーザーに付与する。
    /// - Parameter amount: 付与するポイント（0 以下なら何もしない）
    func addPointsToCurrentUser(amount: Int, actionId: String? = nil) {
        guard amount > 0 else { return }
        
        let defaults = UserDefaults.standard
        let monthKey = currentMonthKey()
        
        // 累計ポイント
        var total = defaults.integer(forKey: "myTotalPoints")
        // 月間ポイント
        var monthly = defaults.integer(forKey: "myMonthlyPoints")
        let storedMonth = defaults.string(forKey: "myPointsMonth")
        
        // 月が変わっていたら月間ポイントをリセット
        if storedMonth != monthKey {
            monthly = 0
        }
        
        total += amount
        monthly += amount
        
        defaults.set(monthKey, forKey: "myPointsMonth")
        defaults.set(total, forKey: "myTotalPoints")
        defaults.set(monthly, forKey: "myMonthlyPoints")

        syncCurrentUserPointsToFirestore(
            totalIncrement: amount,
            monthlyIncrement: amount,
            actionId: actionId ?? makeActionId(prefix: "activity")
        )
    }
    
    /// 現在の累計ポイントを取得するヘルパー（UI 用）
    func currentTotalPoints() -> Int {
        UserDefaults.standard.integer(forKey: "myTotalPoints")
    }
    
    /// アプリ起動時に月が変わっていたら月間ポイントをリセットする
    func resetMonthlyIfNeeded() {
        let defaults = UserDefaults.standard
        let monthKey = currentMonthKey()
        
        if defaults.string(forKey: "myPointsMonth") != monthKey {
            defaults.set(monthKey, forKey: "myPointsMonth")
            defaults.set(0, forKey: "myMonthlyPoints")
        }
        
        if let teamId = defaults.string(forKey: "myTeamId"), teamId.hasPrefix("example_") {
            let prefix = "team_\(teamId)_"
            if defaults.string(forKey: prefix + "pointsMonth") != monthKey {
                defaults.set(monthKey, forKey: prefix + "pointsMonth")
                defaults.set(0, forKey: prefix + "monthlyPoints")
            }
        }
    }
    
    /// 現在の月間ポイントを取得するヘルパー（UI 用）
    func currentMonthlyPoints() -> Int {
        let defaults = UserDefaults.standard
        let monthKey = currentMonthKey()
        let storedMonth = defaults.string(forKey: "myPointsMonth")
        if storedMonth != monthKey {
            // 月が変わっている場合は 0 とみなす
            return 0
        }
        return defaults.integer(forKey: "myMonthlyPoints")
    }

    /// Firestore のポイントをローカル（UserDefaults）へ同期する
    func syncFromRemoteIfNeeded(completion: (() -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }
        db.collection("users").document(uid).getDocument { snapshot, _ in
            defer { completion?() }
            guard let data = snapshot?.data() else { return }
            let defaults = UserDefaults.standard
            let monthKey = self.currentMonthKey()
            let total = data["totalPoints"] as? Int ?? defaults.integer(forKey: "myTotalPoints")
            let monthly = data["monthlyPoints"] as? Int ?? defaults.integer(forKey: "myMonthlyPoints")
            defaults.set(monthKey, forKey: "myPointsMonth")
            defaults.set(total, forKey: "myTotalPoints")
            defaults.set(monthly, forKey: "myMonthlyPoints")
        }
    }
    
    /// チームにポイントを付与する（サンプルチームは UserDefaults、本番は Firestore）
    func addTeamPoints(teamId: String, totalAmount: Int, monthlyAmount: Int, actionId: String? = nil) {
        guard totalAmount > 0 || monthlyAmount > 0 else { return }
        
        let isSampleTeam = teamId.hasPrefix("example_")
        if isSampleTeam {
            addTeamPointsLocal(teamId: teamId, totalAmount: totalAmount, monthlyAmount: monthlyAmount)
        } else {
            addTeamPointsFirestore(
                teamId: teamId,
                totalAmount: totalAmount,
                monthlyAmount: monthlyAmount,
                actionId: actionId ?? makeActionId(prefix: "team")
            )
        }
    }
    
    /// チームの累計・月間ポイントを取得（サンプルチーム用）
    func teamTotalPoints(teamId: String) -> Int {
        guard teamId.hasPrefix("example_") else { return 0 }
        return UserDefaults.standard.integer(forKey: "team_\(teamId)_totalPoints")
    }
    
    func teamMonthlyPoints(teamId: String) -> Int {
        guard teamId.hasPrefix("example_") else { return 0 }
        let defaults = UserDefaults.standard
        let monthKey = currentMonthKey()
        let storedMonth = defaults.string(forKey: "team_\(teamId)_pointsMonth")
        if storedMonth != monthKey { return 0 }
        return defaults.integer(forKey: "team_\(teamId)_monthlyPoints")
    }
    
    /// レース完了時にポイントを付与（1回のみ）
    func awardRacePointsIfNeeded(raceId: String, participants: [(id: String, name: String)], isSample: Bool) {
        // 本番レースは Cloud Functions で付与するため、クライアント側では加算しない。
        guard isSample else { return }
        let key = "racePointsAwarded_\(raceId)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard !participants.isEmpty else { return }
        
        let positionPoints: [Int] = [500, 400, 320, 260, 212, 170, 136, 109, 87, 70]
        let finishBonus = 100   // 完走ボーナス（区間DNFなし）
        let participationBonus = 50  // 参加ボーナス

        // クライアント側は「自分のポイント」だけを確定する。全体配布はサーバー実装で扱う前提。
        let myId = isSample ? "sample_user" : (Auth.auth().currentUser?.uid ?? "")
        guard let myIndex = participants.firstIndex(where: { $0.id == myId || (isSample && $0.name == "あなた") }) else {
            return
        }
        let posPoints = myIndex < positionPoints.count ? positionPoints[myIndex] : 0
        let amount = posPoints + finishBonus + participationBonus
        addPointsToCurrentUser(amount: amount)

        if let teamId = UserDefaults.standard.string(forKey: "myTeamId"), !teamId.isEmpty {
            addTeamPoints(teamId: teamId, totalAmount: amount, monthlyAmount: amount)
        }
        
        UserDefaults.standard.set(true, forKey: key)
    }
    
    // MARK: - Private
    
    private func addTeamPointsLocal(teamId: String, totalAmount: Int, monthlyAmount: Int) {
        let defaults = UserDefaults.standard
        let monthKey = currentMonthKey()
        let prefix = "team_\(teamId)_"
        
        var total = defaults.integer(forKey: prefix + "totalPoints")
        var monthly = defaults.integer(forKey: prefix + "monthlyPoints")
        let storedMonth = defaults.string(forKey: prefix + "pointsMonth")
        
        if storedMonth != monthKey { monthly = 0 }
        total += totalAmount
        monthly += monthlyAmount
        
        defaults.set(monthKey, forKey: prefix + "pointsMonth")
        defaults.set(total, forKey: prefix + "totalPoints")
        defaults.set(monthly, forKey: prefix + "monthlyPoints")
    }
    
    private func addTeamPointsFirestore(teamId: String, totalAmount: Int, monthlyAmount: Int, actionId: String) {
        functions.httpsCallable("grantTeamActivityPoints").call([
            "teamId": teamId,
            "totalAmount": totalAmount,
            "monthlyAmount": monthlyAmount,
            "actionId": actionId
        ]) { _, error in
            if let error = error {
                print("grantTeamActivityPoints failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncCurrentUserPointsToFirestore(totalIncrement: Int, monthlyIncrement: Int, actionId: String) {
        guard totalIncrement > 0, Auth.auth().currentUser != nil else { return }
        // monthly は現状アプリ側で total と同じ刻み。サーバー側でも同一値で加算する。
        let amount = totalIncrement
        functions.httpsCallable("grantActivityPoints").call([
            "amount": amount,
            "actionId": actionId
        ]) { _, error in
            if let error = error {
                print("grantActivityPoints failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// "yyyyMM" 形式の月キー
    private func currentMonthKey() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyyMM"
        return df.string(from: Date())
    }

    private func makeActionId(prefix: String) -> String {
        "\(prefix):\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }
}

