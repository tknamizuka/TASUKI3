import Foundation
import UserNotifications
import FirebaseAuth

/// 襷受け渡しの通知（現状は次走者が同一端末のときのローカル通知。他端末には FCM 等のサーバ送信が必要）
enum TasukiHandoffNotifier {

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// 区間提出が完了した直後に、次区間担当へ襷が渡ったことを通知する
    static func notifyAfterLegSubmission(state: EkidenViewState, completedLegIndex: Int) {
        guard state.usesOfficialHakoneRelayRules else { return }
        let nextIndex = completedLegIndex + 1
        guard nextIndex < state.legs.count,
              let nextUid = state.legs[nextIndex].assignedUid else { return }

        let content = UNMutableNotificationContent()
        content.title = "襷が渡りました"
        content.body = "今襷をもっているのはあなたです。EKIDEN の走行・記録の提出が可能です。"
        content.sound = .default

        // 次走者がログイン中ユーザーと一致するときのみローカル通知（他ユーザーにはサーバから Push が必要）
        guard let uid = Auth.auth().currentUser?.uid, uid == nextUid else {
            return
        }

        let request = UNNotificationRequest(
            identifier: "tasuki-\(state.entry.id)-leg-\(nextIndex)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
