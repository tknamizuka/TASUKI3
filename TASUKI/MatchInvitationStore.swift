import Foundation
import Combine

/// Find のプロフィールから送るマッチング招待を保持し、リクエスト一覧・詳細で参照する（デモは UserDefaults）
final class MatchInvitationStore: ObservableObject {
    static let shared = MatchInvitationStore()

    @Published private(set) var inbox: [MatchRequestSummary] = []

    private let storageKey = "tasuki.match_invitations.inbox.v1"

    private init() {
        load()
        if inbox.isEmpty {
            seedDefaultsIfNeeded()
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PersistedMatchRequest].self, from: data) else {
            return
        }
        inbox = decoded.map(\.summary)
    }

    private func save() {
        let persisted = inbox.map { PersistedMatchRequest(summary: $0) }
        if let data = try? JSONEncoder().encode(persisted) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        notifyUnreadBadge()
    }

    private func notifyUnreadBadge() {
        DispatchQueue.main.async {
            ConversationManager.shared.refreshUnreadCount()
        }
    }

    /// 受信トレイにマッチング招待を追加（デモ・将来のプッシュ想定）
    func ingestIncoming(_ summary: MatchRequestSummary) {
        var next = inbox.filter { $0.id != summary.id }
        next.insert(summary, at: 0)
        inbox = next
        save()
    }

    func remove(id: String) {
        inbox = inbox.filter { $0.id != id }
        save()
    }

    /// 相手の初回提案はそのまま残し、送り返した日程・場所だけを `counter*` に保存（一覧・詳細の予定表示と整合）
    func updateCounterProposal(id: String, proposedStart: Date, location: String, isWeeklyRecurring: Bool, recurrenceWeekday: Int?, message: String) {
        guard let idx = inbox.firstIndex(where: { $0.id == id }) else { return }
        let old = inbox[idx]
        var next = inbox
        next[idx] = MatchRequestSummary(
            id: old.id,
            fromName: old.fromName,
            type: old.type,
            message: message,
            createdAt: Date(),
            isNew: true,
            proposedStart: old.proposedStart,
            location: old.location,
            isWeeklyRecurring: old.isWeeklyRecurring,
            recurrenceWeekday: old.recurrenceWeekday,
            counterLocation: location,
            counterProposedStart: proposedStart,
            counterIsWeeklyRecurring: isWeeklyRecurring,
            counterRecurrenceWeekday: recurrenceWeekday
        )
        inbox = next
        save()
    }

    private func seedDefaultsIfNeeded() {
        let cal = Calendar.current
        let now = Date()
        func daysAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now) ?? now }
        inbox = [
            MatchRequestSummary(
                id: "req-partner-1",
                fromName: "Kenji_Run",
                type: .partner,
                message: "一緒に皇居で朝ランしませんか？",
                createdAt: daysAgo(0),
                isNew: true,
                proposedStart: cal.date(bySettingHour: 7, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 3, to: now)!) ?? now,
                location: "皇居（和田倉門前）",
                isWeeklyRecurring: false,
                recurrenceWeekday: nil
            ),
            MatchRequestSummary(
                id: "req-partner-2",
                fromName: "Momo",
                type: .partner,
                message: "週末のジョグ仲間を探しています。",
                createdAt: daysAgo(3),
                isNew: false,
                proposedStart: cal.date(bySettingHour: 8, minute: 30, second: 0, of: now) ?? now,
                location: "代々木公園",
                isWeeklyRecurring: true,
                recurrenceWeekday: Calendar.current.component(.weekday, from: now)
            )
        ]
        save()
    }
}

private struct PersistedMatchRequest: Codable {
    let summary: MatchRequestSummary
}
