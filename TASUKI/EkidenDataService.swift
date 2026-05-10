//
//  EkidenDataService.swift
//  TASUKI
//
//  駅伝イベント・エントリー・区間データの取得
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

// MARK: - Mock State Holder（サンプルチーム用の可変状態）

/// サンプルチーム向けの駅伝状態を保持。submitLeg で更新し、loadMockEkidenState で読み取る
final class MockEkidenStateHolder {
    static let shared = MockEkidenStateHolder()
    private var stateByTeam: [String: EkidenViewState] = [:]
    private var usedRunActivityIdsByTeam: [String: Set<String>] = [:]
    private let lock = NSLock()

    private init() {}

    func getState(teamId: String) -> EkidenViewState? {
        lock.lock()
        defer { lock.unlock() }
        return stateByTeam[teamId]
    }

    func setState(_ state: EkidenViewState, teamId: String) {
        lock.lock()
        defer { lock.unlock() }
        stateByTeam[teamId] = state
    }

    func hasUsedRunActivityId(teamId: String, runActivityId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return usedRunActivityIdsByTeam[teamId]?.contains(runActivityId) ?? false
    }

    func registerRunActivityId(teamId: String, runActivityId: String) {
        lock.lock()
        defer { lock.unlock() }
        var set = usedRunActivityIdsByTeam[teamId] ?? Set<String>()
        set.insert(runActivityId)
        usedRunActivityIdsByTeam[teamId] = set
    }

    func applyLegSubmission(teamId: String, legIndex: Int, actualDistanceKm: Double, elapsedSeconds: Double, isUnderTarget: Bool, splitAtTargetSeconds: Double?, submittedByUid: String) -> EkidenViewState? {
        lock.lock()
        defer { lock.unlock() }
        guard var state = stateByTeam[teamId],
              legIndex < state.legs.count,
              state.legs[legIndex].status == .ready else {
            return nil
        }
        let now = Date()
        let current = state.legs[legIndex]
        let baseDistance = current.actualDistanceKm ?? 0
        let baseElapsed = current.elapsedSeconds ?? 0
        let rawDistance = max(0, baseDistance + actualDistanceKm)
        let accumulatedDistance = min(rawDistance, max(0, current.targetKm))
        let accumulatedElapsed = max(0, baseElapsed + elapsedSeconds)
        let reachedTarget = accumulatedDistance >= current.targetKm - 1e-9
        var newLegs = state.legs
        newLegs[legIndex] = EkidenLeg(
            id: legIndex,
            assignedUid: newLegs[legIndex].assignedUid,
            targetKm: newLegs[legIndex].targetKm,
            status: reachedTarget ? .submitted : .ready,
            submittedAt: reachedTarget ? now : nil,
            actualDistanceKm: accumulatedDistance,
            elapsedSeconds: accumulatedElapsed,
            isUnderTarget: !reachedTarget,
            splitAtTargetSeconds: reachedTarget ? (splitAtTargetSeconds ?? accumulatedElapsed) : nil,
            isPass: false
        )
        let nextIndex = legIndex + 1
        if reachedTarget, nextIndex < newLegs.count {
            newLegs[nextIndex] = EkidenLeg(
                id: nextIndex,
                assignedUid: newLegs[nextIndex].assignedUid,
                targetKm: newLegs[nextIndex].targetKm,
                status: .ready,
                submittedAt: nil,
                actualDistanceKm: nil,
                elapsedSeconds: nil,
                isUnderTarget: false,
                splitAtTargetSeconds: nil,
                isPass: false
            )
        }
        let newEntry = EkidenEntry(
            id: state.entry.id,
            teamId: state.entry.teamId,
            eventId: state.entry.eventId,
            ownerUid: state.entry.ownerUid,
            currentLegIndex: reachedTarget ? min(nextIndex, newLegs.count - 1) : legIndex,
            tasukiState: reachedTarget ? (nextIndex < newLegs.count ? "ready" : "finished") : "ready",
            createdAt: state.entry.createdAt,
            updatedAt: now,
            officialResultDisqualified: state.entry.officialResultDisqualified
        )
        let newState = EkidenViewState(
            event: state.event,
            entry: newEntry,
            legs: newLegs,
            memberNames: state.memberNames,
            provisionalRank: state.provisionalRank,
            outboundRank: state.outboundRank,
            totalTeams: state.totalTeams
        )
        stateByTeam[teamId] = newState
        return newState
    }

    func applyPassTasuki(teamId: String, legIndex: Int, submittedByUid: String) -> EkidenViewState? {
        lock.lock()
        defer { lock.unlock() }
        guard var state = stateByTeam[teamId],
              legIndex < state.legs.count,
              state.legs[legIndex].status == .ready else {
            return nil
        }
        let now = Date()
        var newLegs = state.legs
        newLegs[legIndex] = EkidenLeg(
            id: legIndex,
            assignedUid: newLegs[legIndex].assignedUid,
            targetKm: newLegs[legIndex].targetKm,
            status: .submitted,
            submittedAt: now,
            actualDistanceKm: 0,
            elapsedSeconds: 0,
            isUnderTarget: false,
            splitAtTargetSeconds: nil,
            isPass: true
        )
        let nextIndex = legIndex + 1
        if nextIndex < newLegs.count {
            newLegs[nextIndex] = EkidenLeg(
                id: nextIndex,
                assignedUid: newLegs[nextIndex].assignedUid,
                targetKm: newLegs[nextIndex].targetKm,
                status: .ready,
                submittedAt: nil,
                actualDistanceKm: nil,
                elapsedSeconds: nil,
                isUnderTarget: false,
                splitAtTargetSeconds: nil,
                isPass: false
            )
        }
        let newEntry = EkidenEntry(
            id: state.entry.id,
            teamId: state.entry.teamId,
            eventId: state.entry.eventId,
            ownerUid: state.entry.ownerUid,
            currentLegIndex: min(nextIndex, newLegs.count - 1),
            tasukiState: nextIndex < newLegs.count ? "ready" : "finished",
            createdAt: state.entry.createdAt,
            updatedAt: now,
            officialResultDisqualified: state.entry.officialResultDisqualified
        )
        let newState = EkidenViewState(
            event: state.event,
            entry: newEntry,
            legs: newLegs,
            memberNames: state.memberNames,
            provisionalRank: state.provisionalRank,
            outboundRank: state.outboundRank,
            totalTeams: state.totalTeams
        )
        stateByTeam[teamId] = newState
        return newState
    }

    func updateLegAssignment(teamId: String, legIndex: Int, newAssignedUid: String?) -> EkidenViewState? {
        lock.lock()
        defer { lock.unlock() }
        guard var state = stateByTeam[teamId],
              legIndex < state.legs.count,
              state.legs[legIndex].status != .submitted else {
            return nil
        }
        var newLegs = state.legs
        let leg = newLegs[legIndex]
        newLegs[legIndex] = EkidenLeg(
            id: leg.id,
            assignedUid: newAssignedUid,
            targetKm: leg.targetKm,
            status: leg.status,
            submittedAt: leg.submittedAt,
            actualDistanceKm: leg.actualDistanceKm,
            elapsedSeconds: leg.elapsedSeconds,
            isUnderTarget: leg.isUnderTarget,
            splitAtTargetSeconds: leg.splitAtTargetSeconds,
            isPass: leg.isPass
        )
        let newState = EkidenViewState(
            event: state.event,
            entry: state.entry,
            legs: newLegs,
            memberNames: state.memberNames,
            provisionalRank: state.provisionalRank,
            outboundRank: state.outboundRank,
            totalTeams: state.totalTeams
        )
        stateByTeam[teamId] = newState
        return newState
    }

    func markOfficialResultDisqualified(teamId: String, isDisqualified: Bool) -> EkidenViewState? {
        lock.lock()
        defer { lock.unlock() }
        guard let state = stateByTeam[teamId] else { return nil }
        let updatedEntry = EkidenEntry(
            id: state.entry.id,
            teamId: state.entry.teamId,
            eventId: state.entry.eventId,
            ownerUid: state.entry.ownerUid,
            currentLegIndex: state.entry.currentLegIndex,
            tasukiState: state.entry.tasukiState,
            createdAt: state.entry.createdAt,
            updatedAt: Date(),
            officialResultDisqualified: isDisqualified
        )
        let newState = EkidenViewState(
            event: state.event,
            entry: updatedEntry,
            legs: state.legs,
            memberNames: state.memberNames,
            provisionalRank: state.provisionalRank,
            outboundRank: state.outboundRank,
            totalTeams: state.totalTeams
        )
        stateByTeam[teamId] = newState
        return newState
    }
}

// MARK: - 総合マップ用ランキング行の日次キャッシュ（同一イベント・同日中は再フェッチしない）
private enum EkidenTeamRankingMapDailyCache {
    static let lock = NSLock()
    static var storage: [String: (day: Date, rows: [EkidenTeamRankingMapRow])] = [:]
}

/// 駅伝データ取得サービス
final class EkidenDataService {
    static let shared = EkidenDataService()
    private lazy var db = Firestore.firestore()

    private init() {}

    /// チームのアクティブ駅伝イベント・エントリー・区間を取得
    /// - Parameters:
    ///   - teamId: チームID
    ///   - isSampleTeam: サンプルチームの場合 true（モックデータを返す）
    /// - Returns: イベント・エントリー・区間・メンバー名・暫定順位（イベントがない場合は nil）
    func loadEkidenState(teamId: String, isSampleTeam: Bool) async -> EkidenViewState? {
        if isSampleTeam || teamId.hasPrefix("example") {
            return await loadMockEkidenState(teamId: teamId)
        }

        return await loadFirestoreEkidenState(teamId: teamId)
    }

    private func loadMockEkidenState(teamId: String) async -> EkidenViewState? {
        let isDistanceChallengeSample = (teamId == "example_member")
        let expectedLegCount = isDistanceChallengeSample ? 7 : 10
        let base: EkidenViewState?
        if let existing = MockEkidenStateHolder.shared.getState(teamId: teamId),
           existing.event.legCount == expectedLegCount,
           mockReadyLegAssigneeMatchesSchema(existing: existing, teamId: teamId) {
            base = existing
        } else if isDistanceChallengeSample {
            base = await loadMockDistanceChallengeEkidenState(teamId: teamId)
        } else {
            base = await loadMockOfficialHakoneEkidenState(teamId: teamId)
        }
        guard let found = base else { return nil }
        let synced = await ekidenViewStateSyncingMapRank(state: found, teamId: teamId)
        await MainActor.run {
            MockEkidenStateHolder.shared.setState(synced, teamId: teamId)
        }
        return synced
    }

    /// マップ用ランキング行と同じ基準で `provisionalRank` / `totalTeams` を埋める（サムネ・一覧の数字を一致させる）
    private func ekidenViewStateSyncingMapRank(state: EkidenViewState, teamId: String) async -> EkidenViewState {
        let isSample = teamId.hasPrefix("example_")
        let rows = await loadEventTeamRankingMapRowsDailyCached(
            eventId: state.event.id,
            isSampleTeam: isSample
        )
        let idx = rows.firstIndex { $0.teamId == teamId } ?? rows.firstIndex { $0.entryId == state.entry.id }
        let rank = idx.map { $0 + 1 }
        let total = rows.isEmpty ? max(1, state.totalTeams) : rows.count
        return EkidenViewState(
            event: state.event,
            entry: state.entry,
            legs: state.legs,
            memberNames: state.memberNames,
            provisionalRank: rank ?? state.provisionalRank,
            outboundRank: state.outboundRank,
            totalTeams: total
        )
    }

    /// Distance Challenge 用モック（2週間ウィンドウ・チーム累計距離チャレンジ。UI は区間行で進捗表示）
    private func loadMockDistanceChallengeEkidenState(teamId: String) async -> EkidenViewState? {
        let calendar = Calendar.current
        let now = Date()
        let startAt = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -3, to: now) ?? now)
        let lastChallengeDay = calendar.date(byAdding: .day, value: 13, to: startAt) ?? startAt
        let endAt = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: lastChallengeDay) ?? lastChallengeDay

        let legsDef = [
            EkidenLegDefinition(id: 0, targetKm: 14.5, order: 1),
            EkidenLegDefinition(id: 1, targetKm: 14.5, order: 2),
            EkidenLegDefinition(id: 2, targetKm: 14.0, order: 3),
            EkidenLegDefinition(id: 3, targetKm: 14.0, order: 4),
            EkidenLegDefinition(id: 4, targetKm: 14.2, order: 5),
            EkidenLegDefinition(id: 5, targetKm: 13.8, order: 6),
            EkidenLegDefinition(id: 6, targetKm: 14.0, order: 7)
        ]

        let event = EkidenEvent(
            id: "mock_event_1",
            startAt: startAt,
            endAt: endAt,
            legCount: 7,
            legs: legsDef,
            status: .active,
            rulesText: "指定期間（本モックでは開始から14日）に、チーム全員の走行距離を合算します。目標累計は teamGoalKm（例: 100km）を参考に表示されます。",
            createdAt: startAt,
            teamGoalKm: 100,
            coursePreset: nil
        )

        let memberUids = ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
        let memberNames: [String: String] = [
            "u_owner": "オーナー",
            "u_kenji": "Kenji_Run",
            "u_sacchan": "さっちゃん",
            "u_taka": "Taka@Sub3",
            "u_momo": "Momo",
            "u_runner123": "Runner123",
            "u_yuki": "Yuki"
        ]

        let legTargets = legsDef.map(\.targetKm)
        var legs: [EkidenLeg] = []
        for i in 0..<7 {
            var assignedUid: String? = memberUids.indices.contains(i) ? memberUids[i] : nil
            let targetKm = legTargets.indices.contains(i) ? legTargets[i] : 6.0
            let status: EkidenLegStatus
            let submittedAt: Date?
            let actualKm: Double?
            let elapsed: Double?
            let isUnder: Bool

            switch i {
            case 0:
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -3, to: now)
                actualKm = 14.2
                elapsed = 70 * 60 + 30
                isUnder = false
            case 1:
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -2, to: now)
                actualKm = 12.6
                elapsed = 82 * 60 + 10
                isUnder = true
            case 2:
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -1, to: now)
                actualKm = 13.8
                elapsed = 71 * 60 + 5
                isUnder = false
            case 3:
                status = .ready
                submittedAt = nil
                actualKm = nil
                elapsed = nil
                isUnder = false
                assignedUid = "u_kenji"
            default:
                status = .awaitingTasuki
                submittedAt = nil
                actualKm = nil
                elapsed = nil
                isUnder = false
            }

            legs.append(EkidenLeg(
                id: i,
                assignedUid: assignedUid,
                targetKm: targetKm,
                status: status,
                submittedAt: submittedAt,
                actualDistanceKm: actualKm,
                elapsedSeconds: elapsed,
                isUnderTarget: isUnder,
                splitAtTargetSeconds: nil,
                isPass: false
            ))
        }

        let entry = EkidenEntry(
            id: "mock_entry_1",
            teamId: teamId,
            eventId: event.id,
            ownerUid: memberUids.first ?? "",
            currentLegIndex: 3,
            tasukiState: "ready",
            createdAt: startAt,
            updatedAt: now,
            officialResultDisqualified: false
        )

        let state = EkidenViewState(
            event: event,
            entry: entry,
            legs: legs,
            memberNames: memberNames,
            provisionalRank: nil,
            outboundRank: nil,
            totalTeams: 0
        )
        MockEkidenStateHolder.shared.setState(state, teamId: teamId)
        return await MainActor.run { state }
    }

    /// EKIDEN（箱根10区）公式襷ルール用モック
    private func loadMockOfficialHakoneEkidenState(teamId: String) async -> EkidenViewState? {
        let calendar = Calendar.current
        let now = Date()
        let startAt = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let endAt = calendar.date(byAdding: .day, value: 23, to: now) ?? now

        let legsDef = HakoneEkidenCourse.segments.map {
            EkidenLegDefinition(id: $0.id, targetKm: $0.targetKm, order: $0.order)
        }

        let event = EkidenEvent(
            id: "mock_event_hakone",
            startAt: startAt,
            endAt: endAt,
            legCount: 10,
            legs: legsDef,
            status: .active,
            rulesText: "1チーム10名固定。前区間の走者が記録を保存した日時以降の走行のみ提出可。棄権・区間制限時間超過時は公式記録失格（繰り上げ完走は可・参考扱い）。",
            createdAt: startAt,
            teamGoalKm: nil,
            coursePreset: "hakone"
        )

        let memberUids: [String]
        let memberNames: [String: String]
        if teamId == "example_owner" {
            memberUids = ["sample_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki", "u_leg8", "u_leg9", "u_leg10"]
            memberNames = [
                "sample_owner": "あなた（オーナー）",
                "u_kenji": "Kenji_Run",
                "u_sacchan": "さっちゃん",
                "u_taka": "Taka@Sub3",
                "u_momo": "Momo",
                "u_runner123": "Runner123",
                "u_yuki": "Yuki",
                "u_leg8": "8区走",
                "u_leg9": "9区走",
                "u_leg10": "10区走"
            ]
        } else {
            memberUids = ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki", "u_leg8", "u_leg9", "u_leg10"]
            memberNames = [
                "u_owner": "オーナー",
                "u_kenji": "Kenji_Run",
                "u_sacchan": "さっちゃん",
                "u_taka": "Taka@Sub3",
                "u_momo": "Momo",
                "u_runner123": "Runner123",
                "u_yuki": "Yuki",
                "u_leg8": "8区走",
                "u_leg9": "9区走",
                "u_leg10": "10区走"
            ]
        }

        let legTargets = legsDef.map(\.targetKm)
        var legs: [EkidenLeg] = []
        for i in 0..<10 {
            var assignedUid: String? = memberUids.indices.contains(i) ? memberUids[i] : nil
            let targetKm = legTargets.indices.contains(i) ? legTargets[i] : 5.0
            let status: EkidenLegStatus
            let submittedAt: Date?
            let actualKm: Double?
            let elapsed: Double?
            let isUnder: Bool

            switch i {
            case 0:
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -5, to: now)
                actualKm = 21.2
                elapsed = 68 * 60 + 20
                isUnder = false
            case 1:
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -4, to: now)
                actualKm = 22.9
                elapsed = 72 * 60 + 40
                isUnder = false
            case 2:
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -2, to: now)
                actualKm = 21.0
                elapsed = 70 * 60 + 5
                isUnder = false
            case 3:
                status = .ready
                submittedAt = nil
                actualKm = nil
                elapsed = nil
                isUnder = false
                if teamId == "example_owner" {
                    assignedUid = "sample_owner"
                } else {
                    assignedUid = "u_kenji"
                }
            default:
                status = .awaitingTasuki
                submittedAt = nil
                actualKm = nil
                elapsed = nil
                isUnder = false
            }

            legs.append(EkidenLeg(
                id: i,
                assignedUid: assignedUid,
                targetKm: targetKm,
                status: status,
                submittedAt: submittedAt,
                actualDistanceKm: actualKm,
                elapsedSeconds: elapsed,
                isUnderTarget: isUnder,
                splitAtTargetSeconds: nil,
                isPass: false
            ))
        }

        let entryIdSafe = teamId.replacingOccurrences(of: "/", with: "_")
        let entry = EkidenEntry(
            id: "mock_entry_hakone_\(entryIdSafe)",
            teamId: teamId,
            eventId: event.id,
            ownerUid: memberUids.first ?? "",
            currentLegIndex: 3,
            tasukiState: "ready",
            createdAt: startAt,
            updatedAt: now,
            officialResultDisqualified: false
        )

        let state = EkidenViewState(
            event: event,
            entry: entry,
            legs: legs,
            memberNames: memberNames,
            provisionalRank: nil,
            outboundRank: nil,
            totalTeams: 0
        )
        MockEkidenStateHolder.shared.setState(state, teamId: teamId)
        return await MainActor.run { state }
    }

    /// 初期モックで 4 区が提出可能のときの担当 UID が現在の定義と一致するか（古いキャッシュを捨てる）。
    private func mockReadyLegAssigneeMatchesSchema(existing: EkidenViewState, teamId: String) -> Bool {
        let expectedLeg3: String
        switch teamId {
        case "example_owner":
            expectedLeg3 = "sample_owner"
        case "example_member", "example_ekiden_real":
            expectedLeg3 = "u_kenji"
        default:
            expectedLeg3 = "sample_owner"
        }
        guard let leg3 = existing.legs.first(where: { $0.id == 3 }) else { return true }
        if leg3.status == .ready {
            return leg3.assignedUid == expectedLeg3
        }
        return true
    }

    private func loadFirestoreEkidenState(teamId: String) async -> EkidenViewState? {
        do {
            let eventsSnapshot = try await db.collection("ekiden_events")
                .whereField("status", isEqualTo: EkidenEventStatus.active.rawValue)
                .whereField("endAt", isGreaterThan: Timestamp(date: Date()))
                .limit(to: 1)
                .getDocuments()

            guard let eventDoc = eventsSnapshot.documents.first,
                  let event = EkidenEvent.parse(id: eventDoc.documentID, data: eventDoc.data()) else {
                return nil
            }

            let entriesSnapshot = try await db.collection("ekiden_entries")
                .whereField("teamId", isEqualTo: teamId)
                .whereField("eventId", isEqualTo: event.id)
                .limit(to: 1)
                .getDocuments()

            guard let entryDoc = entriesSnapshot.documents.first,
                  let entry = EkidenEntry.parse(id: entryDoc.documentID, data: entryDoc.data()) else {
                return nil
            }

            var legs: [EkidenLeg] = []
            let legsSnapshot = try await db.collection("ekiden_entries").document(entry.id)
                .collection("legs")
                .getDocuments()

            for doc in legsSnapshot.documents {
                if let legIndex = Int(doc.documentID) {
                    let leg = EkidenLeg.parse(legIndex: legIndex, data: doc.data())
                    legs.append(leg)
                }
            }
            legs.sort { $0.id < $1.id }

            var memberNames: [String: String] = [:]
            let uids = legs.compactMap { $0.assignedUid }
            for uid in Set(uids) {
                if let userDoc = try? await db.collection("public_profiles").document(uid).getDocument(),
                   let data = userDoc.data(),
                   let name = data["name"] as? String {
                    memberNames[uid] = name
                } else {
                    memberNames[uid] = uid
                }
            }

            var outboundRank: Int?
            let outboundRankingsSnapshot = try? await db.collection("ekiden_events").document(event.id)
                .collection("rankings")
                .order(by: "outboundElapsedSeconds", descending: false)
                .getDocuments()

            if let docs = outboundRankingsSnapshot?.documents {
                for (index, doc) in docs.enumerated() {
                    if doc.documentID == entry.id || (doc.data()["teamId"] as? String) == teamId {
                        outboundRank = index + 1
                        break
                    }
                }
            }

            let mapRows = await loadEventTeamRankingMapRowsDailyCached(
                eventId: event.id,
                isSampleTeam: teamId.hasPrefix("example_")
            )
            let provisionalRank = mapRows.firstIndex { $0.entryId == entry.id }.map { $0 + 1 }

            return EkidenViewState(
                event: event,
                entry: entry,
                legs: legs,
                memberNames: memberNames,
                provisionalRank: provisionalRank,
                outboundRank: outboundRank,
                totalTeams: mapRows.isEmpty ? 1 : mapRows.count
            )
        } catch {
            return nil
        }
    }

    /// 区間賞ランキング（`ekiden_events/{eventId}/leg_rankings/{legIndex}`）
    func loadLegRankingSnapshot(eventId: String, legIndex: Int) async -> EkidenLegRankingSnapshot? {
        guard legIndex >= 0 else { return nil }
        do {
            let doc = try await db.collection("ekiden_events").document(eventId)
                .collection("leg_rankings")
                .document("\(legIndex)")
                .getDocument()
            guard doc.exists, let data = doc.data() else { return nil }
            return EkidenLegRankingSnapshot.parse(legIndex: legIndex, data: data)
        } catch {
            return nil
        }
    }

    /// 区間提出を実行
    /// - Parameters:
    ///   - teamId: チームID
    ///   - entryId: エントリーID
    ///   - eventId: イベントID
    ///   - legIndex: 区間インデックス
    ///   - actualDistanceKm: 実際の走行距離（km）
    ///   - elapsedSeconds: 経過時間（秒）
    ///   - isUnderTarget: 目標距離未達か
    ///   - splitAtTargetSeconds: 超過時の目標距離通過タイム（オプション）
    ///   - totalLegCount: 今回のイベントで走る総区間数（最大10人・各1回）
    ///   - submittedByUid: 提出者UID
    ///   - isSampleTeam: サンプルチームの場合 true
    ///   - source: 提出ソース ("health_kit" | "manual" | "app_record")
    ///   - runActivityId: HealthKit 等の記録ID（オプション）
    ///   - healthKitFirestorePayload: HealthKit ワークアウト詳細（`submissions` にマージ）
    func submitLeg(
        teamId: String,
        entryId: String,
        eventId: String,
        legIndex: Int,
        actualDistanceKm: Double,
        elapsedSeconds: Double,
        isUnderTarget: Bool,
        splitAtTargetSeconds: Double?,
        totalLegCount: Int,
        submittedByUid: String,
        isSampleTeam: Bool,
        source: String = "manual",
        runActivityId: String? = nil,
        healthKitFirestorePayload: [String: Any]? = nil
    ) async -> Result<Void, Error> {
        if let rid = runActivityId, !rid.isEmpty {
            if isSampleTeam || teamId.hasPrefix("example") {
                if MockEkidenStateHolder.shared.hasUsedRunActivityId(teamId: teamId, runActivityId: rid) {
                    return .failure(NSError(domain: "EkidenDataService", code: -2, userInfo: [NSLocalizedDescriptionKey: "同じ記録はすでに提出済みです。別の記録を選択してください。"]))
                }
            } else {
                do {
                    let dup = try await db.collection("ekiden_entries").document(entryId)
                        .collection("submissions")
                        .whereField("runActivityId", isEqualTo: rid)
                        .limit(to: 1)
                        .getDocuments()
                    if !dup.documents.isEmpty {
                        return .failure(NSError(domain: "EkidenDataService", code: -2, userInfo: [NSLocalizedDescriptionKey: "同じ記録はすでに提出済みです。別の記録を選択してください。"]))
                    }
                } catch {
                    return .failure(error)
                }
            }
        }
        if isSampleTeam || teamId.hasPrefix("example") {
            let result = await submitLegMock(
                teamId: teamId,
                legIndex: legIndex,
                actualDistanceKm: actualDistanceKm,
                elapsedSeconds: elapsedSeconds,
                isUnderTarget: isUnderTarget,
                splitAtTargetSeconds: splitAtTargetSeconds,
                submittedByUid: submittedByUid
            )
            if case .success = result, let rid = runActivityId, !rid.isEmpty {
                MockEkidenStateHolder.shared.registerRunActivityId(teamId: teamId, runActivityId: rid)
            }
            return result
        }
        return await submitLegFirestore(
            teamId: teamId,
            entryId: entryId,
            eventId: eventId,
            legIndex: legIndex,
            actualDistanceKm: actualDistanceKm,
            elapsedSeconds: elapsedSeconds,
            isUnderTarget: isUnderTarget,
            splitAtTargetSeconds: splitAtTargetSeconds,
            totalLegCount: totalLegCount,
            submittedByUid: submittedByUid,
            source: source,
            runActivityId: runActivityId,
            healthKitFirestorePayload: healthKitFirestorePayload
        )
    }

    private func submitLegMock(
        teamId: String,
        legIndex: Int,
        actualDistanceKm: Double,
        elapsedSeconds: Double,
        isUnderTarget: Bool,
        splitAtTargetSeconds: Double?,
        submittedByUid: String
    ) async -> Result<Void, Error> {
        guard MockEkidenStateHolder.shared.applyLegSubmission(
            teamId: teamId,
            legIndex: legIndex,
            actualDistanceKm: actualDistanceKm,
            elapsedSeconds: elapsedSeconds,
            isUnderTarget: isUnderTarget,
            splitAtTargetSeconds: splitAtTargetSeconds,
            submittedByUid: submittedByUid
        ) != nil else {
            return .failure(NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "提出に失敗しました（TASUKI状態の不一致など）"]))
        }
        return .success(())
    }

    private func submitLegFirestore(
        teamId: String,
        entryId: String,
        eventId: String,
        legIndex: Int,
        actualDistanceKm: Double,
        elapsedSeconds: Double,
        isUnderTarget: Bool,
        splitAtTargetSeconds: Double?,
        totalLegCount: Int,
        submittedByUid: String,
        source: String = "manual",
        runActivityId: String? = nil,
        healthKitFirestorePayload: [String: Any]? = nil
    ) async -> Result<Void, Error> {
        let now = Date()
        let legsRef = db.collection("ekiden_entries").document(entryId).collection("legs")
        let entryRef = db.collection("ekiden_entries").document(entryId)

        return await withCheckedContinuation { continuation in
            db.runTransaction({ transaction, errorPtr in
                let legDoc = legsRef.document("\(legIndex)")
                guard let legSnap = try? transaction.getDocument(legDoc),
                      let legData = legSnap.data(),
                      (legData["status"] as? String) == EkidenLegStatus.ready.rawValue else {
                    let err = NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "提出可能な状態ではありません"])
                    errorPtr?.pointee = err
                    return nil
                }
                // 担当者が設定されている場合、実行者と一致することを確認
                if let assignedUid = legData["assignedUid"] as? String, !assignedUid.isEmpty,
                   assignedUid != submittedByUid {
                    let err = NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "この区間の担当者ではありません"])
                    errorPtr?.pointee = err
                    return nil
                }
                let targetKm = legData["targetKm"] as? Double ?? 0
                let existingDistance = legData["actualDistanceKm"] as? Double ?? 0
                let existingElapsed = legData["elapsedSeconds"] as? Double ?? 0
                let rawDistance = max(0, existingDistance + actualDistanceKm)
                let accumulatedDistance = min(rawDistance, max(0, targetKm))
                let accumulatedElapsed = max(0, existingElapsed + elapsedSeconds)
                let reachedTarget = accumulatedDistance >= targetKm - 1e-9

                var updateData: [String: Any] = [
                    "status": reachedTarget ? EkidenLegStatus.submitted.rawValue : EkidenLegStatus.ready.rawValue,
                    "actualDistanceKm": accumulatedDistance,
                    "elapsedSeconds": accumulatedElapsed,
                    "isUnderTarget": !reachedTarget
                ]
                if reachedTarget {
                    updateData["submittedAt"] = Timestamp(date: now)
                    if let s = splitAtTargetSeconds {
                        updateData["splitAtTargetSeconds"] = existingElapsed + s
                    } else {
                        updateData["splitAtTargetSeconds"] = accumulatedElapsed
                    }
                } else {
                    updateData["submittedAt"] = FieldValue.delete()
                    updateData["splitAtTargetSeconds"] = FieldValue.delete()
                }
                transaction.updateData(updateData, forDocument: legDoc)

                let nextIndex = legIndex + 1
                let nextLegDoc = legsRef.document("\(nextIndex)")
                if reachedTarget, let nextSnap = try? transaction.getDocument(nextLegDoc), nextSnap.exists {
                    transaction.updateData(["status": EkidenLegStatus.ready.rawValue], forDocument: nextLegDoc)
                }

                if reachedTarget {
                    let hasNextRunner = nextIndex < totalLegCount
                    let tasukiState = hasNextRunner ? "ready" : "finished"
                    transaction.updateData([
                        "currentLegIndex": min(nextIndex, max(totalLegCount - 1, 0)),
                        "tasukiState": tasukiState,
                        "updatedAt": Timestamp(date: now)
                    ], forDocument: entryRef)
                } else {
                    transaction.updateData(["updatedAt": Timestamp(date: now)], forDocument: entryRef)
                }

                let submissionRef = self.db.collection("ekiden_entries").document(entryId)
                    .collection("submissions").document()
                var subData: [String: Any] = [
                    "legIndex": legIndex,
                    "submittedByUid": submittedByUid,
                    "submittedAt": Timestamp(date: now),
                    "source": source,
                    "actualDistanceKm": actualDistanceKm,
                    "elapsedSeconds": elapsedSeconds,
                    "isUnderTarget": isUnderTarget
                ]
                if let s = splitAtTargetSeconds { subData["splitAtTargetSeconds"] = s }
                if let rid = runActivityId { subData["runActivityId"] = rid }
                if let hk = healthKitFirestorePayload {
                    for (k, v) in hk {
                        subData[k] = v
                    }
                }
                transaction.setData(subData, forDocument: submissionRef)

                return true
            }) { _, error in
                if let error = error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }

    /// TASUKIを走らずに次の担当へ渡す（TASUKIをつなぐ）。距離加算なしでTASUKIのみ進行
    /// - Parameters:
    ///   - teamId: チームID
    ///   - entryId: エントリーID
    ///   - legIndex: TASUKI保持中の区間インデックス（status == .ready の区間）
    ///   - totalLegCount: 今回のイベントで走る総区間数（最大10人・各1回）
    ///   - submittedByUid: TASUKI保持者（実行者）のUID
    ///   - isSampleTeam: サンプルチームの場合 true
    func passTasuki(
        teamId: String,
        entryId: String,
        legIndex: Int,
        totalLegCount: Int,
        submittedByUid: String,
        isSampleTeam: Bool
    ) async -> Result<Void, Error> {
        if isSampleTeam || teamId.hasPrefix("example") {
            guard MockEkidenStateHolder.shared.applyPassTasuki(
                teamId: teamId,
                legIndex: legIndex,
                submittedByUid: submittedByUid
            ) != nil else {
                return .failure(NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "TASUKIを渡せません（TASUKI保持者がいないか、期間外です）"]))
            }
            return .success(())
        }
        return await passTasukiFirestore(
            teamId: teamId,
            entryId: entryId,
            legIndex: legIndex,
            totalLegCount: totalLegCount,
            submittedByUid: submittedByUid
        )
    }

    private func passTasukiFirestore(
        teamId: String,
        entryId: String,
        legIndex: Int,
        totalLegCount: Int,
        submittedByUid: String
    ) async -> Result<Void, Error> {
        let now = Date()
        let legsRef = db.collection("ekiden_entries").document(entryId).collection("legs")
        let entryRef = db.collection("ekiden_entries").document(entryId)
        let legRef = legsRef.document("\(legIndex)")

        return await withCheckedContinuation { continuation in
            db.runTransaction({ transaction, errorPtr in
                guard let legSnap = try? transaction.getDocument(legRef),
                      let legData = legSnap.data(),
                      (legData["status"] as? String) == EkidenLegStatus.ready.rawValue,
                      (legData["assignedUid"] as? String) == submittedByUid else {
                    errorPtr?.pointee = NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "TASUKIを渡せません（TASUKI保持者ではありません）"])
                    return nil
                }
                var updateData: [String: Any] = [
                    "status": EkidenLegStatus.submitted.rawValue,
                    "submittedAt": Timestamp(date: now),
                    "actualDistanceKm": 0,
                    "elapsedSeconds": 0,
                    "isUnderTarget": false,
                    "isPass": true
                ]
                transaction.updateData(updateData, forDocument: legRef)

                let nextIndex = legIndex + 1
                let nextLegRef = legsRef.document("\(nextIndex)")
                if let nextSnap = try? transaction.getDocument(nextLegRef), nextSnap.exists {
                    transaction.updateData(["status": EkidenLegStatus.ready.rawValue], forDocument: nextLegRef)
                }

                let hasNextRunner = nextIndex < totalLegCount
                let tasukiState = hasNextRunner ? "ready" : "finished"
                transaction.updateData([
                    "currentLegIndex": min(nextIndex, max(totalLegCount - 1, 0)),
                    "tasukiState": tasukiState,
                    "updatedAt": Timestamp(date: now)
                ], forDocument: entryRef)

                let submissionRef = self.db.collection("ekiden_entries").document(entryId)
                    .collection("submissions").document()
                let subData: [String: Any] = [
                    "legIndex": legIndex,
                    "submittedByUid": submittedByUid,
                    "submittedAt": Timestamp(date: now),
                    "source": "pass",
                    "actualDistanceKm": 0,
                    "elapsedSeconds": 0,
                    "isUnderTarget": false,
                    "isPass": true
                ]
                transaction.setData(subData, forDocument: submissionRef)

                return true
            }) { _, error in
                if let error = error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }
    }

    /// チームの公式記録を棄権扱い（参考記録）に切り替える。想定呼び出し元はオーナーUI。
    func setOfficialResultDisqualified(
        teamId: String,
        entryId: String,
        isSampleTeam: Bool,
        isDisqualified: Bool = true
    ) async -> Result<Void, Error> {
        if isSampleTeam || teamId.hasPrefix("example") {
            guard MockEkidenStateHolder.shared.markOfficialResultDisqualified(teamId: teamId, isDisqualified: isDisqualified) != nil else {
                return .failure(NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "棄権状態の更新に失敗しました。"]))
            }
            return .success(())
        }
        do {
            try await db.collection("ekiden_entries").document(entryId).updateData([
                "officialResultDisqualified": isDisqualified,
                "updatedAt": Timestamp(date: Date())
            ])
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// 区間担当者を変更（代走: オーナー承認）
    /// - Parameters:
    ///   - teamId: チームID（サンプル時はモック更新に使用）
    ///   - entryId: エントリーID
    ///   - legIndex: 区間インデックス
    ///   - newAssignedUid: 新しい担当者UID
    ///   - isSampleTeam: サンプルチームの場合 true
    func updateLegAssignment(
        teamId: String,
        entryId: String,
        legIndex: Int,
        newAssignedUid: String?,
        isSampleTeam: Bool
    ) async -> Result<Void, Error> {
        if isSampleTeam || teamId.hasPrefix("example") {
            if MockEkidenStateHolder.shared.updateLegAssignment(teamId: teamId, legIndex: legIndex, newAssignedUid: newAssignedUid) != nil {
                return .success(())
            }
            return .success(())  // モック更新失敗時も成功扱い（UI更新で再取得）
        }
        let legRef = db.collection("ekiden_entries").document(entryId)
            .collection("legs").document("\(legIndex)")
        do {
            let snap = try await legRef.getDocument()
            guard snap.exists, let data = snap.data() else {
                return .failure(NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "区間が見つかりません"]))
            }
            if (data["status"] as? String) == EkidenLegStatus.submitted.rawValue {
                return .failure(NSError(domain: "EkidenDataService", code: -1, userInfo: [NSLocalizedDescriptionKey: "提出済みの区間は変更できません"]))
            }
            var update: [String: Any] = [:]
            if let uid = newAssignedUid {
                update["assignedUid"] = uid
            } else {
                update["assignedUid"] = FieldValue.delete()
            }
            try await legRef.updateData(update)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func loadActiveEkidenSpectatorStatuses(isSampleTeam: Bool) async -> [EkidenSpectatorTeamStatus] {
        if isSampleTeam {
            let sampleTeams: [(String, String)] = [
                ("example_owner", "皇居ランナーズ"),
                ("example_member", "東京スピードスターズ"),
                ("example_ekiden_real", "EKIDENチャレンジャーズ")
            ]
            let now = Date()
            var statuses: [EkidenSpectatorTeamStatus] = []
            for (teamId, name) in sampleTeams {
                guard let state = await loadMockEkidenState(teamId: teamId) else { continue }
                let coordinate = HakoneEkidenCourse.currentCoordinate(cumulativeRunKm: state.cumulativeDistanceKm)
                statuses.append(EkidenSpectatorTeamStatus(
                    teamId: teamId,
                    teamName: name,
                    eventId: state.event.id,
                    currentRunnerName: state.nextRunnerName(),
                    cumulativeDistanceKm: state.cumulativeDistanceKm,
                    mapCoordinate: coordinate,
                    lastUpdatedAt: now
                ))
            }
            return statuses
        }

        do {
            let now = Date()
            let eventsSnapshot = try await db.collection("ekiden_events")
                .whereField("status", isEqualTo: EkidenEventStatus.active.rawValue)
                .whereField("endAt", isGreaterThan: Timestamp(date: now))
                .limit(to: 1)
                .getDocuments()
            guard let eventDoc = eventsSnapshot.documents.first,
                  let event = EkidenEvent.parse(id: eventDoc.documentID, data: eventDoc.data()) else {
                return []
            }

            let entriesSnapshot = try await db.collection("ekiden_entries")
                .whereField("eventId", isEqualTo: event.id)
                .getDocuments()

            var result: [EkidenSpectatorTeamStatus] = []
            for entryDoc in entriesSnapshot.documents {
                guard let entry = EkidenEntry.parse(id: entryDoc.documentID, data: entryDoc.data()) else { continue }
                let teamDoc = try? await db.collection("teams").document(entry.teamId).getDocument()
                let teamName = teamDoc?.data()?["name"] as? String ?? "Team \(entry.teamId.prefix(6))"

                let legsSnapshot = try await db.collection("ekiden_entries").document(entry.id)
                    .collection("legs")
                    .getDocuments()
                var legs: [EkidenLeg] = []
                for doc in legsSnapshot.documents {
                    if let legIndex = Int(doc.documentID) {
                        legs.append(EkidenLeg.parse(legIndex: legIndex, data: doc.data()))
                    }
                }
                legs.sort { $0.id < $1.id }

                var memberNames: [String: String] = [:]
                let uids = Set(legs.compactMap { $0.assignedUid })
                for uid in uids {
                    if let userDoc = try? await db.collection("public_profiles").document(uid).getDocument(),
                       let data = userDoc.data(),
                       let name = data["name"] as? String {
                        memberNames[uid] = name
                    } else {
                        memberNames[uid] = uid
                    }
                }

                let state = EkidenViewState(
                    event: event,
                    entry: entry,
                    legs: legs,
                    memberNames: memberNames,
                    provisionalRank: nil,
                    outboundRank: nil,
                    totalTeams: entriesSnapshot.documents.count
                )
                let coordinate = HakoneEkidenCourse.currentCoordinate(cumulativeRunKm: state.cumulativeDistanceKm)
                result.append(
                    EkidenSpectatorTeamStatus(
                        teamId: entry.teamId,
                        teamName: teamName,
                        eventId: event.id,
                        currentRunnerName: state.nextRunnerName(),
                        cumulativeDistanceKm: state.cumulativeDistanceKm,
                        mapCoordinate: coordinate,
                        lastUpdatedAt: entry.updatedAt
                    )
                )
            }
            return result
        } catch {
            return []
        }
    }

    /// サンプル用: コースマップに常に12チーム（同一イベントのモック実チーム＋ダミーで埋める）
    /// - Note: `loadMockEkidenState` を呼ばずシードのみ行い、`ekidenViewStateSyncingMapRank` との再帰を避ける。
    private func buildSampleTeamRankingMapRows12(eventId: String) async -> [EkidenTeamRankingMapRow] {
        let pairs: [(teamId: String, displayName: String)] = [
            ("example_owner", "皇居ランナーズ"),
            ("example_member", "東京スピードスターズ"),
            ("example_ekiden_real", "EKIDENチャレンジャーズ")
        ]
        var drafts: [(row: EkidenTeamRankingMapRow, st: EkidenViewState?)] = []
        for p in pairs {
            if MockEkidenStateHolder.shared.getState(teamId: p.teamId) == nil {
                if p.teamId == "example_member" {
                    _ = await loadMockDistanceChallengeEkidenState(teamId: p.teamId)
                } else {
                    _ = await loadMockOfficialHakoneEkidenState(teamId: p.teamId)
                }
            }
            guard let st = MockEkidenStateHolder.shared.getState(teamId: p.teamId), st.event.id == eventId else { continue }
            drafts.append((
                EkidenTeamRankingMapRow(
                    entryId: st.entry.id,
                    teamId: p.teamId,
                    teamDisplayName: p.displayName,
                    cumulativeDistanceKm: st.cumulativeDistanceKm,
                    currentLegIndex: st.entry.currentLegIndex,
                    overallRank: 0,
                    totalElapsedSeconds: st.totalElapsedSeconds
                ),
                st
            ))
        }
        let dummyTeamNames: [String] = [
            "多摩川AC", "湘南国際RC", "山梨大学OB会", "秩父連合", "石垣島走友会",
            "大阪ベイランナーズ", "千葉シーサイド", "筑波ステップ", "札幌ウィンター走友",
            "横浜ベイサイド", "名古屋東海RC", "広島アトミックRC"
        ]
        let totalKm = HakoneEkidenCourse.totalKm
        for j in drafts.count..<12 {
            let name = dummyTeamNames[j]
            let seed = j &* 7919 &+ eventId.hashValue
            let progress = 0.12 + 0.78 * (Double(j + 1) / 12.0) + Double(seed % 80) / 800.0
            let elapsed = Double(j + 1) * 2600 + Double(abs(seed % 900))
            let (cumulative, legIdx): (Double, Int)
            if eventId == "mock_event_hakone" {
                let c = min(totalKm, max(0, totalKm * progress))
                cumulative = c
                legIdx = HakoneEkidenCourse.currentLegIndex(forCumulativeRunKm: c)
            } else if let ref = drafts.first?.st {
                let cap = max(
                    HakoneEkidenCourse.totalTargetKm(fromLegDefinitions: ref.event.legs),
                    ref.teamGoalKm
                )
                let c = min(cap, max(0, cap * progress))
                cumulative = c
                legIdx = HakoneEkidenCourse.currentLegIndex(forCumulativeRunKm: c, legDefinitions: ref.event.legs)
            } else {
                cumulative = min(totalKm, max(0, totalKm * progress))
                legIdx = HakoneEkidenCourse.currentLegIndex(forCumulativeRunKm: cumulative)
            }
            drafts.append((
                EkidenTeamRankingMapRow(
                    entryId: "mock_map_entry_\(j)",
                    teamId: "mock_map_team_\(j)",
                    teamDisplayName: name,
                    cumulativeDistanceKm: cumulative,
                    currentLegIndex: legIdx,
                    overallRank: 0,
                    totalElapsedSeconds: elapsed
                ),
                nil
            ))
        }
        let hakoneBoard = (eventId == "mock_event_hakone")
        drafts.sort { a, b in
            sampleDraftPairPrecedes(a, b, hakoneBoard: hakoneBoard, totalKm: totalKm)
        }
        return drafts.enumerated().map { item in
            let idx = item.offset
            let r = item.element.row
            return EkidenTeamRankingMapRow(
                entryId: r.entryId,
                teamId: r.teamId,
                teamDisplayName: r.teamDisplayName,
                cumulativeDistanceKm: r.cumulativeDistanceKm,
                currentLegIndex: r.currentLegIndex,
                overallRank: idx + 1,
                totalElapsedSeconds: r.totalElapsedSeconds
            )
        }
    }

    /// `true` なら `a` を `b` より前（上位）に並べる
    private func sampleDraftPairPrecedes(
        _ a: (row: EkidenTeamRankingMapRow, st: EkidenViewState?),
        _ b: (row: EkidenTeamRankingMapRow, st: EkidenViewState?),
        hakoneBoard: Bool,
        totalKm: Double
    ) -> Bool {
        if !hakoneBoard {
            if a.row.cumulativeDistanceKm != b.row.cumulativeDistanceKm {
                return a.row.cumulativeDistanceKm > b.row.cumulativeDistanceKm
            }
            if a.row.currentLegIndex != b.row.currentLegIndex {
                return a.row.currentLegIndex > b.row.currentLegIndex
            }
            if a.row.totalElapsedSeconds != b.row.totalElapsedSeconds {
                return a.row.totalElapsedSeconds < b.row.totalElapsedSeconds
            }
            return a.row.teamId < b.row.teamId
        }
        let doneA = a.st?.legs.hasCompletedAllNonPassLegs(legCount: 10) == true
            || (a.st == nil && a.row.cumulativeDistanceKm >= totalKm - 0.05)
        let doneB = b.st?.legs.hasCompletedAllNonPassLegs(legCount: 10) == true
            || (b.st == nil && b.row.cumulativeDistanceKm >= totalKm - 0.05)
        if doneA != doneB { return doneA && !doneB }
        if doneA && doneB {
            if a.row.totalElapsedSeconds != b.row.totalElapsedSeconds {
                return a.row.totalElapsedSeconds < b.row.totalElapsedSeconds
            }
            let ta = a.st?.legs.submittedAtForLeg(legIndex: 9)?.timeIntervalSince1970 ?? .infinity
            let tb = b.st?.legs.submittedAtForLeg(legIndex: 9)?.timeIntervalSince1970 ?? .infinity
            if ta != tb { return ta < tb }
            return a.row.teamId < b.row.teamId
        }
        if a.row.cumulativeDistanceKm != b.row.cumulativeDistanceKm {
            return a.row.cumulativeDistanceKm > b.row.cumulativeDistanceKm
        }
        if a.row.currentLegIndex != b.row.currentLegIndex {
            return a.row.currentLegIndex > b.row.currentLegIndex
        }
        if a.row.totalElapsedSeconds != b.row.totalElapsedSeconds {
            return a.row.totalElapsedSeconds < b.row.totalElapsedSeconds
        }
        return a.row.teamId < b.row.teamId
    }

    /// イベント内の全エントリーの順位を返す（コースマップ UI 用）。
    /// 箱根10区プリセットでは「全区間を規定提出で完走したチーム」は合計タイム昇順（早いほど上位）、それ以外は進捗（距離・区間）優先。
    func loadEventTeamRankingMapRows(eventId: String, isSampleTeam: Bool) async -> [EkidenTeamRankingMapRow] {
        if isSampleTeam {
            return await buildSampleTeamRankingMapRows12(eventId: eventId)
        }

        do {
            let entriesSnapshot = try await db.collection("ekiden_entries")
                .whereField("eventId", isEqualTo: eventId)
                .getDocuments()

            var built: [(entry: EkidenEntry, legs: [EkidenLeg], teamName: String)] = []
            for entryDoc in entriesSnapshot.documents {
                guard let entry = EkidenEntry.parse(id: entryDoc.documentID, data: entryDoc.data()) else { continue }
                let legsSnapshot = try await db.collection("ekiden_entries").document(entry.id)
                    .collection("legs")
                    .getDocuments()
                var legs: [EkidenLeg] = []
                for doc in legsSnapshot.documents {
                    if let legIndex = Int(doc.documentID) {
                        legs.append(EkidenLeg.parse(legIndex: legIndex, data: doc.data()))
                    }
                }
                legs.sort { $0.id < $1.id }
                let teamDoc = try? await db.collection("teams").document(entry.teamId).getDocument()
                let teamName = teamDoc?.data()?["name"] as? String ?? "Team \(entry.teamId.prefix(6))"
                built.append((entry, legs, teamName))
            }

            let eventDoc = try await db.collection("ekiden_events").document(eventId).getDocument()
            let event = eventDoc.exists ? EkidenEvent.parse(id: eventId, data: eventDoc.data() ?? [:]) : nil
            let hakoneFinishLegCount: Int? = {
                guard let event,
                      event.coursePreset == "hakone",
                      event.legCount == HakoneEkidenCourse.segments.count else { return nil }
                return event.legCount
            }()

            let ordered = built.sorted { a, b in
                let dqA = a.entry.officialResultDisqualified
                let dqB = b.entry.officialResultDisqualified
                if dqA != dqB { return !dqA && dqB }
                if let legN = hakoneFinishLegCount {
                    let doneA = a.legs.hasCompletedAllNonPassLegs(legCount: legN)
                    let doneB = b.legs.hasCompletedAllNonPassLegs(legCount: legN)
                    if doneA != doneB { return doneA && !doneB }
                    if doneA && doneB {
                        let elapsedA = a.legs.compactMap { $0.elapsedSeconds }.reduce(0, +)
                        let elapsedB = b.legs.compactMap { $0.elapsedSeconds }.reduce(0, +)
                        if elapsedA != elapsedB { return elapsedA < elapsedB }
                        let ta = a.legs.submittedAtForLeg(legIndex: legN - 1)?.timeIntervalSince1970 ?? .infinity
                        let tb = b.legs.submittedAtForLeg(legIndex: legN - 1)?.timeIntervalSince1970 ?? .infinity
                        if ta != tb { return ta < tb }
                        return a.entry.id < b.entry.id
                    }
                }
                let kmA = a.legs.cumulativeProgressKmForStandings()
                let kmB = b.legs.cumulativeProgressKmForStandings()
                if kmA != kmB { return kmA > kmB }
                if a.entry.currentLegIndex != b.entry.currentLegIndex {
                    return a.entry.currentLegIndex > b.entry.currentLegIndex
                }
                let elapsedA = a.legs.compactMap { $0.elapsedSeconds }.reduce(0, +)
                let elapsedB = b.legs.compactMap { $0.elapsedSeconds }.reduce(0, +)
                if elapsedA != elapsedB { return elapsedA < elapsedB }
                return a.entry.id < b.entry.id
            }

            return ordered.enumerated().map { idx, item in
                let cumulative = item.legs.cumulativeProgressKmForStandings()
                let elapsed = item.legs.compactMap { $0.elapsedSeconds }.reduce(0, +)
                return EkidenTeamRankingMapRow(
                    entryId: item.entry.id,
                    teamId: item.entry.teamId,
                    teamDisplayName: item.teamName,
                    cumulativeDistanceKm: cumulative,
                    currentLegIndex: item.entry.currentLegIndex,
                    overallRank: idx + 1,
                    totalElapsedSeconds: elapsed
                )
            }
        } catch {
            return []
        }
    }

    /// 各チームの累計距離・総合順位をマップ表示する用。同一カレンダー日・同一イベントではキャッシュを返す。
    func loadEventTeamRankingMapRowsDailyCached(eventId: String, isSampleTeam: Bool) async -> [EkidenTeamRankingMapRow] {
        // 順位ロジック変更時はサフィックスを上げて当日キャッシュを無効化
        let key = "\(eventId)|\(isSampleTeam)|progressRank_v3"
        let today = Calendar.current.startOfDay(for: Date())
        EkidenTeamRankingMapDailyCache.lock.lock()
        if let pair = EkidenTeamRankingMapDailyCache.storage[key],
           Calendar.current.isDate(pair.day, inSameDayAs: today) {
            let rows = pair.rows
            EkidenTeamRankingMapDailyCache.lock.unlock()
            return rows
        }
        EkidenTeamRankingMapDailyCache.lock.unlock()
        let fetched = await loadEventTeamRankingMapRows(eventId: eventId, isSampleTeam: isSampleTeam)
        EkidenTeamRankingMapDailyCache.lock.lock()
        EkidenTeamRankingMapDailyCache.storage[key] = (today, fetched)
        EkidenTeamRankingMapDailyCache.lock.unlock()
        return fetched
    }

    func sendSpectatorCheerOncePerDay(
        teamId: String,
        eventId: String,
        spectatorUid: String,
        cheerDateKey: String
    ) async -> Result<Void, Error> {
        let cheerId = "\(eventId)_\(spectatorUid)_\(cheerDateKey)"
        do {
            try await db.collection("teams").document(teamId)
                .collection("spectator_cheer_daily")
                .document(cheerId)
                .setData([
                    "eventId": eventId,
                    "spectatorUid": spectatorUid,
                    "dateKey": cheerDateKey,
                    "createdAt": Timestamp(date: Date())
                ], merge: false)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - TeamView 用の駅伝表示状態
struct EkidenViewState {
    let event: EkidenEvent
    let entry: EkidenEntry
    let legs: [EkidenLeg]
    let memberNames: [String: String]
    let provisionalRank: Int?
    let outboundRank: Int?
    let totalTeams: Int

    /// イベント期間内であるか
    var isWithinEventWindow: Bool {
        event.isWithinEventWindow
    }

    /// TASUKIを持っている（提出可能な）区間の担当者 UID
    var tasukiHolderUid: String? {
        legs.first { $0.status == .ready }?.assignedUid
    }

    /// TASUKIを持っている担当者の表示名
    func tasukiHolderName() -> String? {
        guard let uid = tasukiHolderUid else { return nil }
        return memberNames[uid] ?? uid
    }

    /// 次走者（TASUKIが渡っている人）の表示名
    func nextRunnerName() -> String? {
        tasukiHolderName()
    }

    /// 提出済み区間数
    var submittedLegCount: Int {
        legs.filter { $0.status == .submitted }.count
    }

    /// チーム累計走行距離（km）。提出済み＋走行中（ready）の実走を合算。パス（isPass）区間は除外。
    var cumulativeDistanceKm: Double {
        legs.cumulativeProgressKmForStandings()
    }

    /// チーム目標距離（km）。累計モード用。未設定なら legCount * 5 をデフォルト
    var teamGoalKm: Double {
        event.teamGoalKm ?? Double(event.legCount) * 5.0
    }

    /// 累計モードか（teamGoalKm が設定されている場合 true）
    var isCumulativeMode: Bool {
        event.teamGoalKm != nil
    }

    /// 総合タイム（秒）
    var totalElapsedSeconds: Double {
        legs.compactMap { $0.elapsedSeconds }.reduce(0, +)
    }

    /// 箱根10区プリセット＋公式襷ルール（前走者完了後のみ走行提出可など）
    var usesOfficialHakoneRelayRules: Bool {
        event.coursePreset == "hakone"
    }

    /// 仮想コース上の進捗（0〜1）。`usesOfficialHakoneRelayRules` でない場合は 0
    var hakoneCourseProgressFraction: Double {
        let total = HakoneEkidenCourse.totalKm
        guard usesOfficialHakoneRelayRules, total > 0 else { return 0 }
        return min(1.0, cumulativeDistanceKm / total)
    }

    /// ランキングバーで「全区間 = 100%」の右端に使う規定距離（km）。`累計 ÷ この値` で横位置を決める（順位とは独立）。
    var rankingProgressReferenceKm: Double {
        if usesOfficialHakoneRelayRules {
            return max(HakoneEkidenCourse.totalKm, 0.001)
        }
        if let g = event.teamGoalKm, g > 0 {
            return max(g, 0.001)
        }
        return max(HakoneEkidenCourse.totalTargetKm(fromLegDefinitions: event.legs), 0.001)
    }

    /// EKIDEN 公式襷: この区間に提出する走行の開始時刻がこれより前なら不可（前区 `submittedAt`）
    func minimumActivityStartDateForRelay(legIndex: Int) -> Date? {
        guard usesOfficialHakoneRelayRules, legIndex > 0 else { return nil }
        let prev = legIndex - 1
        guard legs.indices.contains(prev) else { return nil }
        return legs[prev].submittedAt
    }

    /// 区間を秒から MM:SS フォーマット
    static func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct EkidenSpectatorTeamStatus: Identifiable {
    let id = UUID()
    let teamId: String
    let teamName: String
    let eventId: String
    let currentRunnerName: String?
    let cumulativeDistanceKm: Double
    let mapCoordinate: CLLocationCoordinate2D
    let lastUpdatedAt: Date
}
