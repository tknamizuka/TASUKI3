//
//  TasukiLocalNotifications.swift
//  TASUKI
//
//  襷・マッチング・練習会スケジュールなどのローカル通知（他端末への Push は別途 FCM 等が必要）。
//

import Foundation
import UserNotifications
import FirebaseAuth

enum TasukiLocalNotifications {
    private static let postedProposalIdsKey = "tasuki.postedNextPracticeProposalIds"
    private static let maxPostedProposalIds = 120

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: - Immediate

    static func postImmediate(identifier: String, title: String, body: String, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if !userInfo.isEmpty {
            content.userInfo = userInfo
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 区間完了／TASUKI 通過のあと、次の担当が自分なら通知
    static func notifyTasukiHandoffAfterCompletedLeg(state: EkidenViewState, completedLegIndex: Int) {
        guard state.usesOfficialHakoneRelayRules else { return }
        let nextIndex = completedLegIndex + 1
        guard nextIndex < state.legs.count,
              let nextUid = state.legs[nextIndex].assignedUid else { return }
        guard let uid = Auth.auth().currentUser?.uid, uid == nextUid else { return }

        postImmediate(
            identifier: "tasuki.handoff.\(state.entry.id)-leg-\(nextIndex)-\(UUID().uuidString)",
            title: "TASUKIが届きました",
            body: "今襷をもっているのはあなたです。EKIDEN で走行・記録の提出が可能です。",
            userInfo: ["kind": "tasuki_handoff", "entryId": state.entry.id, "legIndex": nextIndex]
        )
    }

    static func notifyPartnerMatchRequest(fromName: String, requestId: String) {
        postImmediate(
            identifier: "tasuki.partner-match.\(requestId)",
            title: "パートナーマッチング",
            body: "\(fromName)さんからマッチングリクエストが届きました。",
            userInfo: ["kind": "partner_match", "requestId": requestId]
        )
    }

    static func notifyPracticeJoinedCalendar(title: String) {
        postImmediate(
            identifier: "tasuki.practice-join.\(UUID().uuidString)",
            title: "練習会",
            body: "「\(title)」の参加がスケジュールに反映されました。",
            userInfo: ["kind": "practice_joined"]
        )
    }

    static func notifyMatchPromiseCalendar(title: String) {
        postImmediate(
            identifier: "tasuki.match-promise.\(UUID().uuidString)",
            title: "マッチング約束",
            body: "「\(title)」をスケジュールに追加しました。",
            userInfo: ["kind": "match_promise"]
        )
    }

    /// 次回練習の提案を初めて検知したときのみ（スクロールのたびに重複しないよう UserDefaults で抑止）
    static func notifyNextPracticeProposalIfUnposted(peerName: String, messageId: String) {
        var posted = Set(UserDefaults.standard.stringArray(forKey: postedProposalIdsKey) ?? [])
        guard !posted.contains(messageId) else { return }
        posted.insert(messageId)
        if posted.count > maxPostedProposalIds {
            posted = Set(Array(posted).suffix(maxPostedProposalIds))
        }
        UserDefaults.standard.set(Array(posted), forKey: postedProposalIdsKey)

        postImmediate(
            identifier: "tasuki.next-practice.\(messageId)",
            title: "次回練習の日程",
            body: "\(peerName)から次回練習の案内が届いています。メッセージで回答できます。",
            userInfo: ["kind": "next_practice_proposal", "messageId": messageId]
        )
    }
}

// MARK: - 前日・当日リマインド（参加練習会・マッチ約束）
//
// カレンダーに載った予定から端末ローカルで `UNCalendarNotificationTrigger` を再登録するだけ。
// 送信イベントでの FCM は不要（ユーザー要望どおり）。

enum TasukiScheduleReminderScheduler {
    private static let idPrefix = "tasuki.schedule."

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日（E）"
        return f
    }()

    static func reschedule(joined: [JoinedPracticeItem], promises: [MatchPromiseItem]) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let toRemove = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: toRemove)

            var requests: [UNNotificationRequest] = []
            let cal = Calendar.current

            for j in joined {
                appendPair(
                    eventDate: j.date,
                    idBase: "joined-\(j.id)",
                    titleEve: "明日の練習会",
                    bodyEve: "「\(j.title)」は明日 \(dayFormatter.string(from: j.date))。\(j.location)",
                    titleDay: "今日の練習会",
                    bodyDay: "本日「\(j.title)」の予定があります。\(j.location)",
                    calendar: cal,
                    into: &requests
                )
            }
            for p in promises {
                appendPair(
                    eventDate: p.date,
                    idBase: "promise-\(p.id)",
                    titleEve: "明日の予定",
                    bodyEve: "「\(p.title)」は明日 \(dayFormatter.string(from: p.date))。\(p.location)",
                    titleDay: "今日の予定",
                    bodyDay: "本日「\(p.title)」。\(p.location)",
                    calendar: cal,
                    into: &requests
                )
            }

            for req in requests {
                UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
            }
        }
    }

    private static func appendPair(
        eventDate: Date,
        idBase: String,
        titleEve: String,
        bodyEve: String,
        titleDay: String,
        bodyDay: String,
        calendar: Calendar,
        into requests: inout [UNNotificationRequest]
    ) {
        let startDay = calendar.startOfDay(for: eventDate)
        if let eve = calendar.date(byAdding: .day, value: -1, to: startDay),
           let fireEve = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: eve),
           fireEve > Date() {
            var dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireEve)
            let trigEve = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            let cEve = UNMutableNotificationContent()
            cEve.title = titleEve
            cEve.body = bodyEve
            cEve.sound = .default
            cEve.userInfo = ["kind": "schedule_reminder", "timing": "eve"]
            requests.append(UNNotificationRequest(identifier: "\(idPrefix)\(idBase).eve", content: cEve, trigger: trigEve))
        }
        if let fireDay = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: startDay),
           fireDay > Date() {
            var dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDay)
            let trigDay = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
            let cDay = UNMutableNotificationContent()
            cDay.title = titleDay
            cDay.body = bodyDay
            cDay.sound = .default
            cDay.userInfo = ["kind": "schedule_reminder", "timing": "day"]
            requests.append(UNNotificationRequest(identifier: "\(idPrefix)\(idBase).day", content: cDay, trigger: trigDay))
        }
    }
}
