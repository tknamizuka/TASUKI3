//
//  PartnerMatchRequestsStore.swift
//  TASUKI
//
//  Find から送るパートナーマッチングリクエストの送受信（場所・日時候補）。
//  本番では Firestore 等に差し替え想定。現状はローカル永続化。
//

import Foundation
import Combine

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

struct PartnerMatchRequestItem: Identifiable, Codable, Equatable {
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

    var proposedDates: [Date] {
        proposedDateIntervals.map { Date(timeIntervalSince1970: $0) }
    }

    var counterDates: [Date]? {
        guard let intervals = counterDateIntervals else { return nil }
        return intervals.map { Date(timeIntervalSince1970: $0) }
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
        seedDemoIncomingIfNeeded()
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
        ConversationManager.shared.refreshUnreadCount()
    }

    /// 初回のみ、受信サンプルを 1 件入れる（一覧・ホームの見え方確認用）
    private func seedDemoIncomingIfNeeded() {
        guard items.filter({ $0.direction == .incoming }).isEmpty else { return }
        let cal = Calendar.current
        let base = Date()
        let d1 = cal.date(byAdding: .day, value: 3, to: base) ?? base
        let d2 = cal.date(byAdding: .day, value: 5, to: base) ?? base
        items.append(
            PartnerMatchRequestItem(
                id: "seed-incoming-kenji",
                peerDisplayName: "Kenji_Run",
                proposedPlace: "皇居外苑（竹橋口付近）",
                proposedDateIntervals: [d1, d2].map { $0.timeIntervalSince1970 },
                message: "一緒に朝ランしませんか？",
                createdAt: Date().timeIntervalSince1970,
                direction: .incoming,
                status: .pending,
                counterPlace: nil,
                counterDateIntervals: nil,
                rejectMessage: nil,
                conversationId: nil
            )
        )
        save()
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

    func sendCounterIncoming(id: String, place: String, dates: [Date]) {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !dates.isEmpty else { return }
        guard let idx = items.firstIndex(where: { $0.id == id && $0.direction == .incoming }) else { return }
        var it = items[idx]
        guard it.status == .pending else { return }
        it.counterPlace = trimmed
        it.counterDateIntervals = dates.map { $0.timeIntervalSince1970 }
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
        let labels = proposedDates.map { PartnerMatchRequestsStore.matchDateFormatter.string(from: $0) }
        let counterLabels = counterDates?.map { PartnerMatchRequestsStore.matchDateFormatter.string(from: $0) }
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
            partnerStatus: status
        )
    }
}
