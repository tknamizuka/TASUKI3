import Foundation

/// 駅伝の襷まわりの通知エントリ（実装は `TasukiLocalNotifications` に集約）
enum TasukiHandoffNotifier {

    static func requestAuthorizationIfNeeded() {
        TasukiLocalNotifications.requestAuthorizationIfNeeded()
    }

    /// 区間提出が完了した直後に、次区間担当へ襷が渡ったことを通知する
    static func notifyAfterLegSubmission(state: EkidenViewState, completedLegIndex: Int) {
        TasukiLocalNotifications.notifyTasukiHandoffAfterCompletedLeg(state: state, completedLegIndex: completedLegIndex)
    }

    /// TASUKI をつなぐ（距離加算なし）直後に、次区間担当へ渡ったことを通知する
    static func notifyAfterPassTasuki(state: EkidenViewState, passedLegIndex: Int) {
        TasukiLocalNotifications.notifyTasukiHandoffAfterCompletedLeg(state: state, completedLegIndex: passedLegIndex)
    }
}
