import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Find のマッチング招待受信トレイ（`match_requests` を正とする）
final class MatchInvitationStore: ObservableObject {
    static let shared = MatchInvitationStore()

    @Published private(set) var inbox: [MatchRequestSummary] = []

    private lazy var db = Firestore.firestore()

    private init() {
        syncFromRemoteIfPossible()
    }

    private func notifyUnreadBadge() {
        DispatchQueue.main.async {
            ConversationManager.shared.refreshUnreadCount()
        }
    }

    /// 受信トレイから除去（承諾後など、サーバー側は既に処理済みのとき）
    func removeLocal(id: String) {
        inbox = inbox.filter { $0.id != id }
        notifyUnreadBadge()
    }

    /// 見送り・拒否（サーバーへ declined / cancelled を送信）
    func dismissRequest(id: String) {
        inbox = inbox.filter { $0.id != id }
        notifyUnreadBadge()
        Task {
            try? await FindComplianceService.shared.declineMatchRequest(requestId: id)
        }
    }

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
        notifyUnreadBadge()
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
            inbox = []
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
                    self.notifyUnreadBadge()
                }
            }
    }

    private func parseSummary(docId: String, data: [String: Any]) -> MatchRequestSummary? {
        let fromName = data["fromName"] as? String ?? ""
        let typeRaw = data["type"] as? String ?? "partner"
        let type: MatchRequestType = (typeRaw == "partner" || typeRaw == MatchRequestType.partner.rawValue) ? .partner : .partner
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
}
