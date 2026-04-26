//
//  PendingNextPracticeReplyStore.swift
//  TASUKI
//
//  「次回練習の提案」に未回答のものを集計し、Home のメッセージバッジに反映する。
//

import Foundation
import Combine

/// UI スレッドから更新すること（`ChatView` 等）。
final class PendingNextPracticeReplyStore: ObservableObject {
    static let shared = PendingNextPracticeReplyStore()

    @Published private(set) var pendingKeys: [String] = []

    private let storageKey = "tasuki.pendingNextPracticeReplyKeys.v1"

    private init() {
        pendingKeys = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    var count: Int { pendingKeys.count }

    private func persist() {
        UserDefaults.standard.set(pendingKeys, forKey: storageKey)
    }

    /// 未回答の提案カードが表示されたとき
    func register(conversationId: String, messageId: String) {
        let key = "\(conversationId)|\(messageId)"
        guard !pendingKeys.contains(key) else { return }
        pendingKeys.append(key)
        persist()
        ConversationManager.shared.refreshUnreadCount()
    }

    /// 参加／不参加で回答したとき
    func clear(conversationId: String, messageId: String) {
        let key = "\(conversationId)|\(messageId)"
        guard let idx = pendingKeys.firstIndex(of: key) else { return }
        pendingKeys.remove(at: idx)
        persist()
        ConversationManager.shared.refreshUnreadCount()
    }
}
