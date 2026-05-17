import Foundation

/// チーム参加・作成時の EKIDEN モード（Firestore `teams/{id}.ekidenMode` と対応）
enum EkidenJoinMode: String, CaseIterable, Identifiable, Hashable {
    /// 本番志向の駅伝運用
    case realEkiden = "real_ekiden"
    /// 指定期間（例: 2週間）のチーム合計走行距離チャレンジ（`enjoy_ekiden`）
    case enjoyEkiden = "enjoy_ekiden"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .realEkiden: return "EKIDEN"
        case .enjoyEkiden: return "Distance Challenge"
        }
    }

    var shortLabel: String {
        switch self {
        case .realEkiden: return "EKIDEN"
        case .enjoyEkiden: return "Distance"
        }
    }

    var description: String {
        switch self {
        case .realEkiden:
            return "箱根10区相当の距離・1チーム10名・襷リレー。前走者が記録を保存した後の走行のみ提出できます。公式順位・コース進捗はこのモードのチーム同士で揃います。"
        case .enjoyEkiden:
            return "イベントで指定された期間（例: 2週間）のうち、チーム全員の走行距離を合算して競うモードです。区間襷や箱根コースの制約はありません。未分類の既存チームもこのモードとして扱われます。"
        }
    }

    /// モード選択カード上部のイメージ（`Assets.xcassets` の名前。`nil` のときはシステムアイコンを表示）
    var selectionHeroAssetName: String? {
        switch self {
        case .realEkiden:
            // バンドルに `runner` が無い環境では毎回アセット探索ログが出るため、SF Symbol ヒーローを使う。
            return nil
        case .enjoyEkiden: return nil
        }
    }

    /// `selectionHeroAssetName` がないときに使う SF Symbol
    var selectionHeroSystemImage: String {
        switch self {
        case .realEkiden: return "figure.run.circle.fill"
        case .enjoyEkiden: return "hands.and.sparkles.fill"
        }
    }

    /// Firestore に保存する値
    var firestoreValue: String { rawValue }

    /// `teams` ドキュメントのデータが、この参加モードの画面に表示・参加してよいか。
    /// - Real: `ekidenMode == real_ekiden` のみ。
    /// - Distance Challenge: `ekidenMode` 未設定（移行前）または `enjoy_ekiden`。
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
