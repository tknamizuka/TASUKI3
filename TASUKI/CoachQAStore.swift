//
//  CoachQAStore.swift
//  TASUKI
//
//  ユーザー→コーチの質問一覧（単一アプリ内）。将来 Firestore に載せ替え可能。
//

import Foundation
import Combine

@MainActor
final class CoachQAStore: ObservableObject {
    static let shared = CoachQAStore()

    @Published private(set) var items: [QAItem] = []

    private let storageKey = "tasuki.coach_qa_items.v1"

    private init() {
        load()
    }

    var pendingQuestions: [QAItem] {
        items.filter { $0.answer == nil }.sorted { $0.postedDate > $1.postedDate }
    }

    func addQuestion(question: String, category: String, askerName: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = QAItem(
            question: trimmed,
            answer: nil,
            askerName: askerName,
            coachName: nil,
            category: category,
            postedDate: Date()
        )
        items.insert(item, at: 0)
        save()
    }

    func submitAnswer(itemId: UUID, answer: String, coachName: String) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let i = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[i] = items[i].withAnswer(trimmed, coachName: coachName)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            items = []
            return
        }
        do {
            items = try JSONDecoder().decode([QAItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // ignore
        }
    }
}
