import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Find のプロフィールから送るマッチング招待を保持し、リクエスト一覧・詳細で参照する（デモは UserDefaults）
final class MatchInvitationStore: ObservableObject {
    static let shared = MatchInvitationStore()

    @Published private(set) var inbox: [MatchRequestSummary] = []

    private let storageKey = "tasuki.match_invitations.inbox.v1"
    private lazy var db = Firestore.firestore()

    private init() {
        load()
        if inbox.isEmpty {
            seedDefaultsIfNeeded()
        }
        syncFromRemoteIfPossible()
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
        upsertRemote(summary)
    }

    func remove(id: String) {
        inbox = inbox.filter { $0.id != id }
        save()
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("match_requests").document(id).setData([
            "toUid": uid,
            "status": "dismissed",
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
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
        guard Auth.auth().currentUser?.uid != nil else { return }
        db.collection("match_requests").document(id).setData([
            "counterLocation": location,
            "counterProposedStart": Timestamp(date: proposedStart),
            "counterIsWeeklyRecurring": isWeeklyRecurring,
            "counterRecurrenceWeekday": recurrenceWeekday as Any,
            "message": message,
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    func syncFromRemoteIfPossible(completion: (() -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }
        db.collection("match_requests")
            .whereField("toUid", isEqualTo: uid)
            .whereField("status", isEqualTo: "open")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments { [weak self] snapshot, _ in
                defer { completion?() }
                guard let self, let docs = snapshot?.documents else { return }
                let remote = docs.compactMap { self.parseSummary(docId: $0.documentID, data: $0.data()) }
                DispatchQueue.main.async {
                    self.inbox = remote
                    self.save()
                }
            }
    }

    private func upsertRemote(_ summary: MatchRequestSummary) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [
            "toUid": uid,
            "fromName": summary.fromName,
            "type": summary.type.rawValue,
            "message": summary.message,
            "createdAt": Timestamp(date: summary.createdAt),
            "isNew": summary.isNew,
            "isWeeklyRecurring": summary.isWeeklyRecurring,
            "counterIsWeeklyRecurring": summary.counterIsWeeklyRecurring,
            "status": "open",
            "updatedAt": Timestamp(date: Date())
        ]
        if let proposedStart = summary.proposedStart {
            data["proposedStart"] = Timestamp(date: proposedStart)
        }
        if let location = summary.location, !location.isEmpty {
            data["location"] = location
        }
        if let recurrenceWeekday = summary.recurrenceWeekday {
            data["recurrenceWeekday"] = recurrenceWeekday
        }
        if let counterLocation = summary.counterLocation, !counterLocation.isEmpty {
            data["counterLocation"] = counterLocation
        }
        if let counterProposedStart = summary.counterProposedStart {
            data["counterProposedStart"] = Timestamp(date: counterProposedStart)
        }
        if let counterRecurrenceWeekday = summary.counterRecurrenceWeekday {
            data["counterRecurrenceWeekday"] = counterRecurrenceWeekday
        }
        db.collection("match_requests").document(summary.id).setData(data, merge: true)
    }

    private func parseSummary(docId: String, data: [String: Any]) -> MatchRequestSummary? {
        let fromName = data["fromName"] as? String ?? ""
        let typeRaw = data["type"] as? String ?? MatchRequestType.partner.rawValue
        let type = MatchRequestType(rawValue: typeRaw) ?? .partner
        let message = data["message"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let isNew = data["isNew"] as? Bool ?? false
        let proposedStart = (data["proposedStart"] as? Timestamp)?.dateValue()
        let location = data["location"] as? String
        let isWeeklyRecurring = data["isWeeklyRecurring"] as? Bool ?? false
        let recurrenceWeekday = data["recurrenceWeekday"] as? Int
        let counterLocation = data["counterLocation"] as? String
        let counterProposedStart = (data["counterProposedStart"] as? Timestamp)?.dateValue()
        let counterIsWeeklyRecurring = data["counterIsWeeklyRecurring"] as? Bool ?? false
        let counterRecurrenceWeekday = data["counterRecurrenceWeekday"] as? Int
        return MatchRequestSummary(
            id: docId,
            fromName: fromName,
            type: type,
            message: message,
            createdAt: createdAt,
            isNew: isNew,
            proposedStart: proposedStart,
            location: location,
            isWeeklyRecurring: isWeeklyRecurring,
            recurrenceWeekday: recurrenceWeekday,
            counterLocation: counterLocation,
            counterProposedStart: counterProposedStart,
            counterIsWeeklyRecurring: counterIsWeeklyRecurring,
            counterRecurrenceWeekday: counterRecurrenceWeekday
        )
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
