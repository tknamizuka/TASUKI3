//
//  PracticeRecruitmentsStore.swift
//  TASUKI
//
//  Find の練習会募集一覧をアプリ全体で共有し、練習会チャットから PracticeDetail へ辿れるようにする。
//

import Foundation
import Combine

@MainActor
final class PracticeRecruitmentsStore: ObservableObject {
    static let shared = PracticeRecruitmentsStore()

    @Published private(set) var recruitments: [PracticeRecruitment]

    private init() {
        recruitments = mockRecruitments
    }

    func upsertAtStart(_ recruitment: PracticeRecruitment) {
        recruitments.removeAll { $0.practiceId == recruitment.practiceId }
        recruitments.insert(recruitment, at: 0)
    }

    func recruitment(forPracticeId id: String?) -> PracticeRecruitment? {
        guard let id, !id.isEmpty else { return nil }
        return recruitments.first { $0.practiceId == id }
    }

    /// `partnerName` 例: 「練習会: 皇居ペース走 15km」（タイトルに `:` が含まれても先頭の接頭辞だけ除去）
    func recruitment(matchingPracticeChatPartnerName partnerName: String) -> PracticeRecruitment? {
        let prefix = "練習会:"
        if partnerName.hasPrefix(prefix) {
            let rest = partnerName.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty, let r = recruitments.first(where: { $0.title == rest }) {
                return r
            }
        }
        return recruitments.first { partnerName.contains($0.title) }
    }
}
