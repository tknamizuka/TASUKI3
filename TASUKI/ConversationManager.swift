//
//  ConversationManager.swift
//  TASUKI
//
//  チャット・メッセージの会話をバックエンド（Firestore）で一意ID管理
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// 未読数表示用の共通ベース（@EnvironmentObject は具象型が必要なためクラスで定義）
class UnreadCountProviderBase: ObservableObject {
    @Published var unreadCount: Int = 0
    func refreshUnreadCount(completion: (() -> Void)? = nil) { completion?() }
}

final class ConversationManager: UnreadCountProviderBase {
    static let shared = ConversationManager()
    private lazy var db: Firestore = {
        FirebaseBootstrap.configureIfNeeded()
        return Firestore.firestore()
    }()
    
    private override init() { super.init() }
    
    var currentUserId: String? { Auth.auth().currentUser?.uid }

    private func trackConversationEvent(_ name: String, properties: [String: Any] = [:]) {
        RealityMiningManager.shared.trackEvent(name: name, properties: properties)
    }
    
    /// 新規会話を開始し、バックエンドで一意の会話IDを発行して返す
    func createConversation(partnerUserId: String, partnerName: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let myUid = currentUserId else {
            completion(.failure(NSError(domain: "ConversationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        let ref = db.collection("conversations").document()
        let now = Timestamp(date: Date())
        var data: [String: Any] = [
            "participantIds": [myUid, partnerUserId],
            "partnerName": partnerName,
            "createdAt": now,
            "lastMessageAt": now
        ]
        // 作成者は既読扱い（lastReadAt を設定）
        data["lastReadAt"] = [myUid: now]
        ref.setData(data) { error in
            if let error = error {
                self.trackConversationEvent(
                    "conversation_create_failed",
                    properties: ["error_message": error.localizedDescription]
                )
                completion(.failure(error))
            } else {
                self.trackConversationEvent(
                    "conversation_created",
                    properties: ["conversation_id": ref.documentID]
                )
                completion(.success(ref.documentID))
            }
        }
    }
    
    /// 既存の会話IDを取得（自分と相手の組み合わせで検索）。無ければ nil
    func findExistingConversation(partnerUserId: String, completion: @escaping (Result<String?, Error>) -> Void) {
        guard let myUid = currentUserId else {
            completion(.failure(NSError(domain: "ConversationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        db.collection("conversations")
            .whereField("participantIds", arrayContains: myUid)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let doc = snapshot?.documents.first { doc in
                    let ids = doc.data()["participantIds"] as? [String] ?? []
                    return ids.contains(partnerUserId) && ids.contains(myUid)
                }
                completion(.success(doc?.documentID))
            }
    }
    
    /// 練習会に紐づくチャットを新規作成（practiceID 作成時に呼ぶ）。会話ID（chatID）を返す
    func createPracticeConversation(practiceId: String, hostUserId: String, practiceTitle: String, completion: @escaping (Result<String, Error>) -> Void) {
        let ref = db.collection("conversations").document()
        let now = Timestamp(date: Date())
        let partnerName = "練習会: \(practiceTitle)"
        var data: [String: Any] = [
            "participantIds": [hostUserId],
            "partnerName": partnerName,
            "practiceId": practiceId,
            "createdAt": now,
            "lastMessageAt": now,
            "lastReadAt": [hostUserId: now]
        ]
        ref.setData(data) { error in
            if let error = error {
                self.trackConversationEvent(
                    "practice_conversation_create_failed",
                    properties: ["practice_id": practiceId, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
            } else {
                self.trackConversationEvent(
                    "practice_conversation_created",
                    properties: ["practice_id": practiceId, "conversation_id": ref.documentID]
                )
                completion(.success(ref.documentID))
            }
        }
    }
    
    /// 練習会チャットに参加者を追加（参加者が MessageListView でそのチャットに参加できるようにする）
    func addParticipantToPracticeChat(conversationId: String, userId: String, completion: ((Error?) -> Void)? = nil) {
        let ref = db.collection("conversations").document(conversationId)
        ref.getDocument { [weak self] snapshot, error in
            if let error = error {
                completion?(error)
                return
            }
            guard let self = self else {
                completion?(NSError(domain: "ConversationManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "内部エラー"]))
                return
            }
            guard let data = snapshot?.data(),
                  var ids = data["participantIds"] as? [String] else {
                completion?(NSError(domain: "ConversationManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "会話が見つかりません"]))
                return
            }
            if ids.contains(userId) {
                completion?(nil)
                return
            }
            ids.append(userId)
            ref.updateData(["participantIds": ids]) { err in
                if let err = err {
                    self.trackConversationEvent(
                        "practice_chat_participant_add_failed",
                        properties: ["conversation_id": conversationId, "error_message": err.localizedDescription]
                    )
                } else {
                    self.trackConversationEvent(
                        "practice_chat_participant_added",
                        properties: ["conversation_id": conversationId]
                    )
                }
                completion?(err)
            }
        }
    }
    
    /// 会話開始: 既存があればそのID、無ければ新規作成してIDを返す
    func startOrGetConversation(partnerUserId: String, partnerName: String, completion: @escaping (Result<String, Error>) -> Void) {
        findExistingConversation(partnerUserId: partnerUserId) { [weak self] result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let existingId):
                if let id = existingId {
                    completion(.success(id))
                } else {
                    self?.createConversation(partnerUserId: partnerUserId, partnerName: partnerName, completion: completion)
                }
            }
        }
    }
    
    /// 自分の会話一覧を取得（バックエンドの一意ID付き）
    func fetchMyConversations(completion: @escaping (Result<[MessageConversation], Error>) -> Void) {
        guard let myUid = currentUserId else {
            completion(.failure(NSError(domain: "ConversationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        db.collection("conversations")
            .whereField("participantIds", arrayContains: myUid)
            .order(by: "lastMessageAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let list = (snapshot?.documents ?? []).map { doc in
                    let data = doc.data()
                    let partnerName = data["partnerName"] as? String ?? ""
                    let partnerUserId = data["partnerUserId"] as? String
                    let practiceId = data["practiceId"] as? String
                    let lastMessage = data["lastMessage"] as? String ?? ""
                    let lastMessageAt = (data["lastMessageAt"] as? Timestamp)?.dateValue() ?? (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let lastReadAt: Date? = {
                        guard let map = data["lastReadAt"] as? [String: Timestamp],
                              let ts = map[myUid] else { return nil }
                        return ts.dateValue()
                    }()
                    let hasUnread = lastMessageAt > (lastReadAt ?? .distantPast)
                    // practiceId を持つ会話は「練習会チャット」として扱う
                    let isPractice = practiceId != nil || partnerName.hasPrefix("練習会:")
                    return MessageConversation(
                        conversationId: doc.documentID,
                        partnerName: partnerName,
                        avatarImage: "person.circle.fill",
                        lastMessage: lastMessage.isEmpty ? "メッセージがありません" : lastMessage,
                        timestamp: lastMessageAt,
                        hasUnread: hasUnread,
                        isPractice: isPractice,
                        partnerUserId: partnerUserId,
                        practiceId: practiceId
                    )
                }
                completion(.success(list))
            }
    }
    
    /// 会話を既読にする（lastReadAt を更新）
    func markConversationAsRead(conversationId: String, completion: ((Error?) -> Void)? = nil) {
        guard let myUid = currentUserId else {
            completion?(NSError(domain: "ConversationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"]))
            return
        }
        let now = Timestamp(date: Date())
        db.collection("conversations").document(conversationId).updateData(["lastReadAt.\(myUid)": now]) { error in
            DispatchQueue.main.async {
                if error == nil { self.refreshUnreadCount() }
                completion?(error)
            }
        }
    }
    
    /// 自分宛のマッチングリクエスト一覧を取得（現状はダミーデータ）
    func fetchMyMatchRequests(completion: @escaping (Result<[MatchRequestSummary], Error>) -> Void) {
        // TODO: Firestore の match_requests コレクションから取得する実装に差し替え
        let cal = Calendar.current
        let now = Date()
        func daysAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now) ?? now }
        
        let samples: [MatchRequestSummary] = [
            MatchRequestSummary(
                id: "req-partner-1",
                fromName: "Kenji_Run",
                type: .partner,
                message: "一緒に皇居で朝ランしませんか？",
                createdAt: daysAgo(0),
                isNew: true
            ),
            MatchRequestSummary(
                id: "req-practice-1",
                fromName: "皇居ラン募集",
                type: .practice,
                message: "皇居ラン 2周 ゆっくりペース（6:00/km）への参加リクエストです。",
                createdAt: daysAgo(1),
                isNew: true
            ),
            MatchRequestSummary(
                id: "req-partner-2",
                fromName: "Momo",
                type: .partner,
                message: "週末のジョグ仲間を探しています。",
                createdAt: daysAgo(3),
                isNew: false
            )
        ]
        Task { @MainActor in
            let fromStore = PartnerMatchRequestsStore.shared.matchRequestSummaries()
            var merged: [String: MatchRequestSummary] = [:]
            for s in samples { merged[s.id] = s }
            for s in fromStore { merged[s.id] = s }
            let list = merged.values.sorted { $0.createdAt > $1.createdAt }
            completion(.success(list))
        }
    }
    
    /// 未読会話数を再取得して unreadCount を更新（HomeView のバッジ用）
    override func refreshUnreadCount(completion: (() -> Void)? = nil) {
        guard currentUserId != nil else {
            DispatchQueue.main.async { self.unreadCount = 0; completion?() }
            return
        }
        fetchMyConversations { [weak self] result in
            switch result {
            case .success(let list):
                let unreadChats = list.filter { $0.hasUnread }.count
                // マッチングリクエスト数もバッジに含める
                self?.fetchMyMatchRequests { reqResult in
                    let pending = (try? reqResult.get().filter { $0.isNew }.count) ?? 0
                    DispatchQueue.main.async {
                        self?.unreadCount = unreadChats + pending
                        completion?()
                    }
                }
            case .failure:
                // 会話取得に失敗した場合でも、リクエストだけは表示する
                self?.fetchMyMatchRequests { reqResult in
                    let pending = (try? reqResult.get().filter { $0.isNew }.count) ?? 0
                    DispatchQueue.main.async {
                        self?.unreadCount = pending
                        completion?()
                    }
                }
            }
        }
    }
    
    // MARK: - Messages（conversationId に紐づく。各メッセージは replyToMessageId で返信先を参照可能）
    
    /// メッセージを送信し、バックエンドで発行された messageId を返す
    func sendMessage(conversationId: String, text: String, replyToMessageId: String?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let myUid = currentUserId else {
            completion(.failure(NSError(domain: "ConversationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        let ref = db.collection("conversations").document(conversationId).collection("messages").document()
        let now = Timestamp(date: Date())
        var data: [String: Any] = [
            "text": text,
            "senderId": myUid,
            "timestamp": now
        ]
        if let replyId = replyToMessageId, !replyId.isEmpty {
            data["replyToMessageId"] = replyId
        }
        ref.setData(data) { error in
            if let error = error {
                self.trackConversationEvent(
                    "message_send_failed",
                    properties: ["conversation_id": conversationId, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
            } else {
                self.trackConversationEvent(
                    "message_sent",
                    properties: ["conversation_id": conversationId, "message_id": ref.documentID]
                )
                completion(.success(ref.documentID))
            }
        }
    }
    
    /// 会話のメッセージ一覧を取得（replyToMessageId 付き）
    func fetchMessages(conversationId: String, completion: @escaping (Result<[ChatMessage], Error>) -> Void) {
        guard let myUid = currentUserId else {
            completion(.failure(NSError(domain: "ConversationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        db.collection("conversations").document(conversationId).collection("messages")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let list = (snapshot?.documents ?? []).map { doc in
                    let data = doc.data()
                    let text = data["text"] as? String ?? ""
                    let senderId = data["senderId"] as? String ?? ""
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                    let replyToMessageId = data["replyToMessageId"] as? String
                    return ChatMessage(
                        id: doc.documentID,
                        text: text,
                        isFromMe: senderId == myUid,
                        timestamp: timestamp,
                        replyToMessageId: replyToMessageId
                    )
                }
                completion(.success(list))
            }
    }
    
    // MARK: - Reports
    
    /// 会話の通報を `reports` コレクションに保存する
    func submitConversationReport(conversationId: String, partnerName: String, reasonCategory: String, detail: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = currentUserId else {
            completion(.failure(NSError(domain: "ConversationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        let ref = db.collection("reports").document()
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var data: [String: Any] = [
            "kind": "conversation",
            "conversationId": conversationId,
            "partnerName": partnerName,
            "reporterUid": uid,
            "reasonCategory": reasonCategory,
            "createdAt": Timestamp(date: Date())
        ]
        if !trimmedDetail.isEmpty {
            data["detail"] = trimmedDetail
        }
        data["reason"] = trimmedDetail.isEmpty ? reasonCategory : "\(reasonCategory): \(trimmedDetail)"
        ref.setData(data) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.trackConversationEvent(
                        "conversation_report_failed",
                        properties: ["conversation_id": conversationId, "error_message": error.localizedDescription]
                    )
                    completion(.failure(error))
                } else {
                    self.trackConversationEvent(
                        "conversation_reported",
                        properties: ["conversation_id": conversationId, "reason_category": reasonCategory]
                    )
                    completion(.success(()))
                }
            }
        }
    }
}

// MARK: - プレビュー用モック（Firebase に触れず HomeView プレビューを表示）
final class PreviewUnreadProvider: UnreadCountProviderBase {
    override init() { super.init() }
    init(unreadCount: Int = 0) { super.init(); self.unreadCount = unreadCount }
}
