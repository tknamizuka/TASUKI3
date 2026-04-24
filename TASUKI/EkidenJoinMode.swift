import Foundation

/// チーム参加・作成時の EKIDEN モード（Firestore `teams/{id}.ekidenMode` と対応）
enum EkidenJoinMode: String, CaseIterable, Identifiable, Hashable {
    /// 本番志向の駅伝運用
    case realEkiden = "real_ekiden"
    /// ゆるく楽しむ駅伝
    case enjoyEkiden = "enjoy_ekiden"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .realEkiden: return "リアルEKIDENモード"
        case .enjoyEkiden: return "Enjoy EKIDENモード"
        }
    }

    var shortLabel: String {
        switch self {
        case .realEkiden: return "リアル"
        case .enjoyEkiden: return "Enjoy"
        }
    }

    var description: String {
        switch self {
        case .realEkiden:
            return "区間・記録・ルールを重視したチーム向け。同じモードのチームだけが一覧・検索に表示されます。"
        case .enjoyEkiden:
            return "気軽に参加・交流を楽しむチーム向け。従来の未分類チームもこのモードとして扱われます。"
        }
    }

    /// Firestore に保存する値
    var firestoreValue: String { rawValue }

    /// `teams` ドキュメントのデータが、この参加モードの画面に表示・参加してよいか。
    /// - Real: `ekidenMode == real_ekiden` のみ。
    /// - Enjoy: `ekidenMode` 未設定（移行前）または `enjoy_ekiden`。
    func matchesTeamDocument(_ data: [String: Any]) -> Bool {
        let stored = data["ekidenMode"] as? String
        switch self {
        case .realEkiden:
            return stored == Self.realEkiden.rawValue
        case .enjoyEkiden:
            return stored == nil || stored?.isEmpty == true || stored == Self.enjoyEkiden.rawValue
        }
    }
}
