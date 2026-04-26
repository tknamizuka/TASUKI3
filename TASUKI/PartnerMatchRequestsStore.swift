//
//  PartnerMatchRequestsStore.swift
//  TASUKI
//
//  Find から送るパートナーマッチングリクエストの送受信（場所・日時候補）。
//  本番では Firestore 等に差し替え想定。現状はローカル永続化。
//

import Foundation
import Combine
import FirebaseAuth

enum PartnerMatchDirection: String, Codable {
    case incoming
    case outgoing
}

enum PartnerMatchRequestStatus: String, Codable {
    /// 受信: 返答待ち / 送信: 相手の返答待ち
    case pending
    case accepted
    case rejected
    /// 受信側が日時・場所を送り返した状態（相手の返答待ち）
    case counterProposed
}

struct PartnerMatchRequestItem: Identifiable, Equatable {
    var id: String
    /// incoming なら送り主、outgoing なら宛先の表示名
    var peerDisplayName: String
    var proposedPlace: String
    var proposedDateIntervals: [TimeInterval]
    var message: String
    var createdAt: TimeInterval
    var direction: PartnerMatchDirection
    var status: PartnerMatchRequestStatus
    var counterPlace: String?
    var counterDateIntervals: [TimeInterval]?
    var rejectMessage: String?
    var conversationId: String?
    /// true のとき、候補日は「その曜日の直近の具体例」であり、継続的には毎週 `recurringWeekday` を希望する意味
    var isWeeklyPreferred: Bool
    /// `Calendar` の weekday（1=日 … 7=土）。`isWeeklyPreferred` のときに使用
    var recurringWeekday: Int?
    /// 送り返した日時候補を「毎週同じ曜日」として伝える
    var counterIsWeeklyPreferred: Bool
    /// `counterIsWeeklyPreferred` のときの曜日（1=日 … 7=土）
    var counterRecurringWeekday: Int?

    var proposedDates: [Date] {
        proposedDateIntervals.map { Date(timeIntervalSince1970: $0) }
    }

    var counterDates: [Date]? {
        guard let intervals = counterDateIntervals else { return nil }
        return intervals.map { Date(timeIntervalSince1970: $0) }
    }

    init(
        id: String,
        peerDisplayName: String,
        proposedPlace: String,
        proposedDateIntervals: [TimeInterval],
        message: String,
        createdAt: TimeInterval,
        direction: PartnerMatchDirection,
        status: PartnerMatchRequestStatus,
        counterPlace: String? = nil,
        counterDateIntervals: [TimeInterval]? = nil,
        rejectMessage: String? = nil,
        conversationId: String? = nil,
        isWeeklyPreferred: Bool = false,
        recurringWeekday: Int? = nil,
        counterIsWeeklyPreferred: Bool = false,
        counterRecurringWeekday: Int? = nil
    ) {
        self.id = id
        self.peerDisplayName = peerDisplayName
        self.proposedPlace = proposedPlace
        self.proposedDateIntervals = proposedDateIntervals
        self.message = message
        self.createdAt = createdAt
        self.direction = direction
        self.status = status
        self.counterPlace = counterPlace
        self.counterDateIntervals = counterDateIntervals
        self.rejectMessage = rejectMessage
        self.conversationId = conversationId
        self.isWeeklyPreferred = isWeeklyPreferred
        self.recurringWeekday = recurringWeekday
        self.counterIsWeeklyPreferred = counterIsWeeklyPreferred
        self.counterRecurringWeekday = counterRecurringWeekday
    }

    /// 一覧・詳細・サマリ用の候補ラベル（毎週希望のとき先頭に要約）
    var proposedDateLabelsForUI: [String] {
        let formatter = PartnerMatchRequestsStore.matchDateFormatter
        let concrete = proposedDates.map { formatter.string(from: $0) }
        guard isWeeklyPreferred, let w = recurringWeekday, (1...7).contains(w) else {
            return concrete
        }
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        let sym = symbols[w - 1]
        let timeStr: String = {
            guard let first = proposedDates.first else { return "" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "H:mm"
            return f.string(from: first)
        }()
        let head = "毎週\(sym) \(timeStr)〜（希望）"
        if concrete.isEmpty {
            return [head]
        }
        return [head] + concrete.map { "直近の例: \($0)" }
    }

    /// 送り返した日時の表示用ラベル（毎週希望のとき先頭に要約）
    var counterDateLabelsForUI: [String]? {
        guard let dates = counterDates, !dates.isEmpty else { return nil }
        let formatter = PartnerMatchRequestsStore.matchDateFormatter
        let concrete = dates.map { formatter.string(from: $0) }
        guard counterIsWeeklyPreferred, let w = counterRecurringWeekday, (1...7).contains(w) else {
            return concrete
        }
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        let sym = symbols[w - 1]
        let timeStr: String = {
            guard let first = dates.first else { return "" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "H:mm"
            return f.string(from: first)
        }()
        let head = "毎週\(sym) \(timeStr)〜（送り返し）"
        return [head] + concrete.map { "直近の例: \($0)" }
    }
}

// MARK: - Codable（UserDefaults 互換: 旧データに新フィールドが無い場合はデフォルト）
extension PartnerMatchRequestItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, peerDisplayName, proposedPlace, proposedDateIntervals, message, createdAt
        case direction, status, counterPlace, counterDateIntervals, rejectMessage, conversationId
        case isWeeklyPreferred, recurringWeekday
        case counterIsWeeklyPreferred, counterRecurringWeekday
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        peerDisplayName = try c.decode(String.self, forKey: .peerDisplayName)
        proposedPlace = try c.decode(String.self, forKey: .proposedPlace)
        proposedDateIntervals = try c.decodeIfPresent([TimeInterval].self, forKey: .proposedDateIntervals) ?? []
        message = try c.decode(String.self, forKey: .message)
        createdAt = try c.decode(TimeInterval.self, forKey: .createdAt)
        direction = try c.decode(PartnerMatchDirection.self, forKey: .direction)
        status = try c.decode(PartnerMatchRequestStatus.self, forKey: .status)
        counterPlace = try c.decodeIfPresent(String.self, forKey: .counterPlace)
        counterDateIntervals = try c.decodeIfPresent([TimeInterval].self, forKey: .counterDateIntervals)
        rejectMessage = try c.decodeIfPresent(String.self, forKey: .rejectMessage)
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationId)
        isWeeklyPreferred = try c.decodeIfPresent(Bool.self, forKey: .isWeeklyPreferred) ?? false
        recurringWeekday = try c.decodeIfPresent(Int.self, forKey: .recurringWeekday)
        counterIsWeeklyPreferred = try c.decodeIfPresent(Bool.self, forKey: .counterIsWeeklyPreferred) ?? false
        counterRecurringWeekday = try c.decodeIfPresent(Int.self, forKey: .counterRecurringWeekday)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(peerDisplayName, forKey: .peerDisplayName)
        try c.encode(proposedPlace, forKey: .proposedPlace)
        try c.encode(proposedDateIntervals, forKey: .proposedDateIntervals)
        try c.encode(message, forKey: .message)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(direction, forKey: .direction)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(counterPlace, forKey: .counterPlace)
        try c.encodeIfPresent(counterDateIntervals, forKey: .counterDateIntervals)
        try c.encodeIfPresent(rejectMessage, forKey: .rejectMessage)
        try c.encodeIfPresent(conversationId, forKey: .conversationId)
        try c.encode(isWeeklyPreferred, forKey: .isWeeklyPreferred)
        try c.encodeIfPresent(recurringWeekday, forKey: .recurringWeekday)
        try c.encode(counterIsWeeklyPreferred, forKey: .counterIsWeeklyPreferred)
        try c.encodeIfPresent(counterRecurringWeekday, forKey: .counterRecurringWeekday)
    }
}

@MainActor
final class PartnerMatchRequestsStore: ObservableObject {
    static let shared = PartnerMatchRequestsStore()

    static let matchDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    @Published private(set) var items: [PartnerMatchRequestItem] = []

    private let storageKey = "PartnerMatchRequestsStore.v1"

    init() {
        load()
        ensureDemoIncomingPartnerSamples()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PartnerMatchRequestItem].self, from: data) else {
            items = []
            return
        }
        items = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        notifyNewIncomingPartnerMatchesIfNeeded()
        ConversationManager.shared.refreshUnreadCount()
    }

    private static let notifiedPartnerMatchIdsKey = "tasuki.notifiedPartnerMatchIds"

    private func notifyNewIncomingPartnerMatchesIfNeeded() {
        let pending = items.filter { $0.direction == .incoming && $0.status == .pending }
        var arr = UserDefaults.standard.stringArray(forKey: Self.notifiedPartnerMatchIdsKey) ?? []
        var seen = Set(arr)
        for it in pending {
            if it.id.hasPrefix("seed-") { continue }
            guard !seen.contains(it.id) else { continue }
            TasukiLocalNotifications.notifyPartnerMatchRequest(fromName: it.peerDisplayName, requestId: it.id)
            seen.insert(it.id)
            arr.append(it.id)
        }
        if arr.count > 120 {
            arr = Array(arr.suffix(120))
        }
        UserDefaults.standard.set(arr, forKey: Self.notifiedPartnerMatchIdsKey)
    }

    /// Kenji / Momo の受信デモを ID 単位で不足分だけ補う（既に他の受信がある場合でも追加可能）
    private func ensureDemoIncomingPartnerSamples() {
        let cal = Calendar.current
        let base = Date()
        let d1 = cal.date(byAdding: .day, value: 3, to: base) ?? base
        let d2 = cal.date(byAdding: .day, value: 5, to: base) ?? base
        let d3 = cal.date(byAdding: .day, value: 6, to: base) ?? base
        let d4 = cal.date(byAdding: .day, value: 8, to: base) ?? base
        var changed = false

        if !items.contains(where: { $0.id == "seed-incoming-kenji" }) {
            items.append(
                PartnerMatchRequestItem(
                    id: "seed-incoming-kenji",
                    peerDisplayName: "Kenji_Run",
                    proposedPlace: "皇居外苑（和田堀門付近）",
                    proposedDateIntervals: [d1, d2].map { $0.timeIntervalSince1970 },
                    message: "一緒に皇居で朝ランしませんか？",
                    createdAt: Date().timeIntervalSince1970,
                    direction: .incoming,
                    status: .pending,
                    counterPlace: nil,
                    counterDateIntervals: nil,
                    rejectMessage: nil,
                    conversationId: nil
                )
            )
            changed = true
        }

        if !items.contains(where: { $0.id == "seed-incoming-momo" }) {
            items.append(
                PartnerMatchRequestItem(
                    id: "seed-incoming-momo",
                    peerDisplayName: "Momo",
                    proposedPlace: "代々木公園（ケヤキ並木付近）",
                    proposedDateIntervals: [d3, d4].map { $0.timeIntervalSince1970 },
                    message: "週末のジョグ仲間を探しています。",
                    createdAt: Date().timeIntervalSince1970 - 60 * 60 * 24 * 3,
                    direction: .incoming,
                    status: .pending,
                    counterPlace: nil,
                    counterDateIntervals: nil,
                    rejectMessage: nil,
                    conversationId: nil
                )
            )
            changed = true
        }

        /// 毎週希望のマッチングリクエスト（候補日は「水曜 7:00」の直近2回分の具体例）
        if !items.contains(where: { $0.id == "seed-incoming-weekly" }) {
            let wednesday = 4 // Calendar.weekday: 1=日 … 4=水
            var comps = DateComponents()
            comps.weekday = wednesday
            comps.hour = 7
            comps.minute = 0
            let firstWed = cal.nextDate(after: base, matching: comps, matchingPolicy: .nextTime) ?? d1
            let secondWed = cal.date(byAdding: .weekOfYear, value: 1, to: firstWed) ?? firstWed
            items.append(
                PartnerMatchRequestItem(
                    id: "seed-incoming-weekly",
                    peerDisplayName: "さっちゃん",
                    proposedPlace: "皇居外苑（青山口付近）",
                    proposedDateIntervals: [firstWed, secondWed].map { $0.timeIntervalSince1970 },
                    message: "仕事前に毎週ゆるく走りたいです。まずは一度だけでも大丈夫です。",
                    createdAt: Date().timeIntervalSince1970 - 60 * 45,
                    direction: .incoming,
                    status: .pending,
                    counterPlace: nil,
                    counterDateIntervals: nil,
                    rejectMessage: nil,
                    conversationId: nil,
                    isWeeklyPreferred: true,
                    recurringWeekday: wednesday
                )
            )
            changed = true
        }

        if changed {
            items.sort { $0.createdAt > $1.createdAt }
            save()
        }
    }

    func recordOutgoing(to peer: User, place: String, dates: [Date], message: String) {
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlace.isEmpty, !dates.isEmpty else { return }
        let id = UUID().uuidString
        let item = PartnerMatchRequestItem(
            id: id,
            peerDisplayName: peer.name,
            proposedPlace: trimmedPlace,
            proposedDateIntervals: dates.map { $0.timeIntervalSince1970 },
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date().timeIntervalSince1970,
            direction: .outgoing,
            status: .pending,
            counterPlace: nil,
            counterDateIntervals: nil,
            rejectMessage: nil,
            conversationId: nil
        )
        items.insert(item, at: 0)
        save()
        let senderName = Auth.auth().currentUser?.displayName
            ?? Auth.auth().currentUser?.email
            ?? "TASUKIユーザー"
        PartnerMatchPushOutbox.enqueue(
            recipientFirebaseUid: peer.firebaseUid,
            senderDisplayName: senderName,
            requestId: id
        )
    }

    func item(id: String) -> PartnerMatchRequestItem? {
        items.first { $0.id == id }
    }

    /// 承認して 1on1 用の会話 ID を発行
    func acceptIncoming(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id && $0.direction == .incoming }) else { return }
        var it = items[idx]
        guard it.status == .pending else { return }
        it.status = .accepted
        it.conversationId = it.conversationId ?? "match-\(UUID().uuidString)"
        items[idx] = it
        save()
    }

    func rejectIncoming(id: String, message: String) {
        guard let idx = items.firstIndex(where: { $0.id == id && $0.direction == .incoming }) else { return }
        var it = items[idx]
        guard it.status == .pending else { return }
        it.status = .rejected
        it.rejectMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx] = it
        save()
    }

    func sendCounterIncoming(
        id: String,
        place: String,
        dates: [Date],
        counterWeeklyPreferred: Bool = false,
        counterWeekday: Int? = nil
    ) {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !dates.isEmpty else { return }
        guard let idx = items.firstIndex(where: { $0.id == id && $0.direction == .incoming }) else { return }
        var it = items[idx]
        guard it.status == .pending else { return }
        it.counterPlace = trimmed
        it.counterDateIntervals = dates.map { $0.timeIntervalSince1970 }
        it.counterIsWeeklyPreferred = counterWeeklyPreferred
        if counterWeeklyPreferred {
            let inferred = counterWeekday ?? Calendar.current.component(.weekday, from: dates[0])
            it.counterRecurringWeekday = (1...7).contains(inferred) ? inferred : nil
        } else {
            it.counterRecurringWeekday = nil
        }
        it.status = .counterProposed
        items[idx] = it
        save()
    }

    func matchRequestSummaries() -> [MatchRequestSummary] {
        items.map { $0.toMatchRequestSummary() }
    }

    /// ホーム「受信」用（終了済みは除外）
    var homeIncomingItems: [PartnerMatchRequestItem] {
        items.filter { $0.direction == .incoming && $0.status != .rejected && $0.status != .accepted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// ホーム「送信・返答待ち」
    var homeOutgoingPendingItems: [PartnerMatchRequestItem] {
        items.filter { $0.direction == .outgoing && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// チャットの「次回練習」既定の場所: 会話IDに紐づくマッチング、なければ同じ表示名の相手の最新リクエストから
    func lastKnownPlace(peerName: String, conversationId: String) -> String? {
        if let it = items.first(where: { $0.conversationId == conversationId }) {
            return placeString(from: it)
        }
        let nameMatches = items.filter { $0.peerDisplayName == peerName }
            .sorted { $0.createdAt > $1.createdAt }
        guard let it = nameMatches.first else { return nil }
        return placeString(from: it)
    }

    private func placeString(from it: PartnerMatchRequestItem) -> String? {
        if let cp = it.counterPlace?.trimmingCharacters(in: .whitespacesAndNewlines), !cp.isEmpty {
            return cp
        }
        let p = it.proposedPlace.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }
}

extension PartnerMatchRequestItem {
    func toMatchRequestSummary() -> MatchRequestSummary {
        let labels = proposedDateLabelsForUI
        let counterLabels = counterDateLabelsForUI
            ?? counterDates?.map { PartnerMatchRequestsStore.matchDateFormatter.string(from: $0) }
        let isNew = direction == .incoming && status == .pending
        return MatchRequestSummary(
            id: id,
            fromName: peerDisplayName,
            type: .partner,
            message: message,
            createdAt: Date(timeIntervalSince1970: createdAt),
            isNew: isNew,
            proposedPlace: proposedPlace,
            proposedDateLabels: labels,
            counterProposedPlace: counterPlace,
            counterProposedDateLabels: counterLabels,
            storeRequestId: id,
            isOutgoing: direction == .outgoing,
            partnerStatus: status,
            isWeeklyRecurringProposal: isWeeklyPreferred,
            counterIsWeeklyRecurringProposal: counterIsWeeklyPreferred
        )
    }
}
