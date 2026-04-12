//
//  MatchPromisesStore.swift
//  TASUKI
//
//  マッチングで決めた「一緒に走る」約束日（カレンダー・バッジ用）。
//  本番では Firestore 等と同期する想定（現状はローカルのみ）。
//

import Foundation
import Combine

/// マッチング約束 1 件
struct MatchPromiseItem: Identifiable, Equatable {
    let id: String
    /// 表示タイトル（例: 「Kenjiさんと朝ラン」）
    let title: String
    let date: Date
    let location: String
    /// 1対1チャット。あればカレンダーから ChatView へ
    let conversationId: String?

    var dateOnly: Date {
        Calendar.current.startOfDay(for: date)
    }
}

@MainActor
final class MatchPromisesStore: ObservableObject {
    @Published private(set) var items: [MatchPromiseItem] = []

    var scheduledCount: Int { items.count }

    func add(_ item: MatchPromiseItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        items.sort { $0.date < $1.date }
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
    }
}
