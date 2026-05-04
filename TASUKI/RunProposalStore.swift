import Foundation
import Combine

/// チャット内で提案された「次回ラン」の日程（参加/不参加・上部アテンション用）
enum RunProposalAttendance: String, Codable {
    case attending
    case notAttending
}

struct RunProposal: Identifiable, Codable, Equatable {
    let id: String
    let conversationId: String
    let proposedStart: Date
    let location: String
    let isWeeklyRecurring: Bool
    let recurrenceWeekday: Int?
    let note: String
    let createdAt: Date
    /// 提案した側の表示名（受信者は myName と異なる）
    let fromSenderName: String
    var attendance: RunProposalAttendance?
}

final class RunProposalStore: ObservableObject {
    static let shared = RunProposalStore()

    @Published private(set) var proposals: [RunProposal] = []

    private let storageKey = "tasuki.run_proposals.v1"

    private init() {
        load()
        seedIfEmpty()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([RunProposal].self, from: data) else {
            return
        }
        proposals = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(proposals) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        objectWillChange.send()
    }

    private func seedIfEmpty() {
        guard proposals.isEmpty else { return }
        let cal = Calendar.current
        let now = Date()
        guard let inThreeDays = cal.date(byAdding: .day, value: 3, to: now),
              let atSeven = cal.date(bySettingHour: 7, minute: 0, second: 0, of: inThreeDays) else { return }
        proposals = [
            RunProposal(
                id: "seed-dummy-tanaka",
                conversationId: "dummy-tanaka",
                proposedStart: atSeven,
                location: "皇居（和田倉門前）",
                isWeeklyRecurring: false,
                recurrenceWeekday: nil,
                note: "次はこちらでどうでしょう？",
                createdAt: now,
                fromSenderName: "Tanaka-san",
                attendance: nil
            )
        ]
        save()
    }

    func addProposal(
        conversationId: String,
        fromSenderName: String,
        proposedStart: Date,
        location: String,
        isWeeklyRecurring: Bool,
        recurrenceWeekday: Int?,
        note: String
    ) {
        let p = RunProposal(
            id: UUID().uuidString,
            conversationId: conversationId,
            proposedStart: proposedStart,
            location: location,
            isWeeklyRecurring: isWeeklyRecurring,
            recurrenceWeekday: recurrenceWeekday,
            note: note,
            createdAt: Date(),
            fromSenderName: fromSenderName,
            attendance: nil
        )
        var next = proposals.filter { $0.conversationId != conversationId }
        next.append(p)
        proposals = next
        save()
    }

    func setAttendance(proposalId: String, _ status: RunProposalAttendance) {
        guard let i = proposals.firstIndex(where: { $0.id == proposalId }) else { return }
        var next = proposals
        next[i].attendance = status
        proposals = next
        save()
    }

    /// 受信者向け：相手からの提案があり、ラン当日終了まで上部に表示する
    func incomingAttentionProposal(conversationId: String, myDisplayName: String) -> RunProposal? {
        let candidates = proposals
            .filter { $0.conversationId == conversationId }
            .filter { $0.fromSenderName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame }
        guard let latest = candidates.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
        guard isStillWithinAttentionWindow(proposedStart: latest.proposedStart) else { return nil }
        return latest
    }

    private func isStillWithinAttentionWindow(proposedStart: Date) -> Bool {
        let cal = Calendar.current
        guard let endOfRunDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: proposedStart)) else { return false }
        return Date() < endOfRunDay
    }

    func scheduleLine(for proposal: RunProposal) -> String {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        if proposal.isWeeklyRecurring, proposal.recurrenceWeekday != nil {
            let wd = proposal.recurrenceWeekday ?? cal.component(.weekday, from: proposal.proposedStart)
            let idx = (wd + 6) % 7
            let symbols = cal.shortWeekdaySymbols
            let dayName = idx < symbols.count ? symbols[idx] : ""
            df.dateFormat = "HH:mm"
            let time = df.string(from: proposal.proposedStart)
            let loc = proposal.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let locPart = loc.isEmpty ? "" : " · \(loc)"
            return "毎週\(dayName) \(time)\(locPart)"
        }
        df.dateStyle = .medium
        df.timeStyle = .short
        var line = df.string(from: proposal.proposedStart)
        let loc = proposal.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loc.isEmpty { line += " · \(loc)" }
        return line
    }
}
