//
//  EkidenDataService.swift
//  TASUKI
//
//  駅伝イベント・エントリー・区間データの取得
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Mock State Holder（サンプルチーム用の可変状態）

/// サンプルチーム向けの駅伝状態を保持。submitLeg で更新し、loadMockEkidenState で読み取る
final class MockEkidenStateHolder {
    static let shared = MockEkidenStateHolder()
    private var stateByTeam: [String: EkidenViewState] = [:]
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

    func applyLegSubmission(teamId: String, legIndex: Int, actualDistanceKm: Double, elapsedSeconds: Double, isUnderTarget: Bool, splitAtTargetSeconds: Double?, submittedByUid: String) -> EkidenViewState? {
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
            actualDistanceKm: actualDistanceKm,
            elapsedSeconds: elapsedSeconds,
            isUnderTarget: isUnderTarget,
            splitAtTargetSeconds: splitAtTargetSeconds,
            isPass: false
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
            updatedAt: now
        )
        let newState = EkidenViewState(
            event: state.event,
            entry: newEntry,
            legs: newLegs,
            memberNames: state.memberNames,
            provisionalRank: state.provisionalRank,
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
            updatedAt: now
        )
        let newState = EkidenViewState(
            event: state.event,
            entry: newEntry,
            legs: newLegs,
            memberNames: state.memberNames,
            provisionalRank: state.provisionalRank,
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
            totalTeams: state.totalTeams
        )
        stateByTeam[teamId] = newState
        return newState
    }
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
        if let existing = MockEkidenStateHolder.shared.getState(teamId: teamId),
           existing.event.legCount == 7 {
            return await MainActor.run { existing }
        }
        let calendar = Calendar.current
        let now = Date()
        let startAt = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let endAt = calendar.date(byAdding: .day, value: 23, to: now) ?? now

        // 7区・各区の参考目標距離。チーム累計目標 teamGoalKm は 100（1区あたりおおよそ 100/7 km 前後のイメージ）。
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
            rulesText: nil,
            createdAt: startAt,
            teamGoalKm: 100
        )

        let memberUids: [String]
        let memberNames: [String: String]
        if teamId == "example_owner" {
            memberUids = ["sample_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
            memberNames = [
                "sample_owner": "あなた（オーナー）",
                "u_kenji": "Kenji_Run",
                "u_sacchan": "さっちゃん",
                "u_taka": "Taka@Sub3",
                "u_momo": "Momo",
                "u_runner123": "Runner123",
                "u_yuki": "Yuki"
            ]
        } else if teamId == "example_member" {
            memberUids = ["u_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
            memberNames = [
                "u_owner": "オーナー",
                "u_kenji": "Kenji_Run",
                "u_sacchan": "さっちゃん",
                "u_taka": "Taka@Sub3",
                "u_momo": "Momo",
                "u_runner123": "Runner123",
                "u_yuki": "Yuki"
            ]
        } else {
            memberUids = ["sample_owner", "u_kenji", "u_sacchan", "u_taka", "u_momo", "u_runner123", "u_yuki"]
            memberNames = [
                "sample_owner": "あなた",
                "u_kenji": "Kenji_Run",
                "u_sacchan": "さっちゃん",
                "u_taka": "Taka@Sub3",
                "u_momo": "Momo",
                "u_runner123": "Runner123",
                "u_yuki": "Yuki"
            ]
        }

        let legTargets = legsDef.map(\.targetKm)

        var legs: [EkidenLeg] = []
        for i in 0..<7 {
            let uid = memberUids.indices.contains(i) ? memberUids[i] : nil
            let targetKm = legTargets.indices.contains(i) ? legTargets[i] : 6.0
            let status: EkidenLegStatus
            let submittedAt: Date?
            let actualKm: Double?
            let elapsed: Double?
            let isUnder: Bool

            switch i {
            case 0:
                // 1区完了（約14km / 5:00/km 前後）
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -3, to: now)
                actualKm = 14.2
                elapsed = 70 * 60 + 30  // 70:30
                isUnder = false
            case 1:
                // 2区：目標に対し距離不足で提出（ペースは遅め）
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -2, to: now)
                actualKm = 12.6
                elapsed = 82 * 60 + 10  // 82:10
                isUnder = true
            case 2:
                status = .submitted
                submittedAt = calendar.date(byAdding: .hour, value: -1, to: now)
                actualKm = 13.8
                elapsed = 71 * 60 + 5  // 71:05
                isUnder = false
            case 3:
                status = .ready  // TASUKI渡し済み・提出可能（4区）
                submittedAt = nil
                actualKm = nil
                elapsed = nil
                isUnder = false
            default:
                status = .awaitingTasuki
                submittedAt = nil
                actualKm = nil
                elapsed = nil
                isUnder = false
            }

            legs.append(EkidenLeg(
                id: i,
                assignedUid: uid,
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
            updatedAt: now
        )

        let state = EkidenViewState(
            event: event,
            entry: entry,
            legs: legs,
            memberNames: memberNames,
            provisionalRank: 5,
            totalTeams: 12
        )
        MockEkidenStateHolder.shared.setState(state, teamId: teamId)
        return await MainActor.run { state }
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
                if let userDoc = try? await db.collection("users").document(uid).getDocument(),
                   let data = userDoc.data(),
                   let name = data["name"] as? String {
                    memberNames[uid] = name
                } else {
                    memberNames[uid] = uid
                }
            }

            var provisionalRank: Int?
            let rankingsSnapshot = try? await db.collection("ekiden_events").document(event.id)
                .collection("rankings")
                .order(by: "totalElapsedSeconds", descending: false)
                .getDocuments()

            if let docs = rankingsSnapshot?.documents {
                for (index, doc) in docs.enumerated() {
                    if doc.documentID == entry.id || (doc.data()["teamId"] as? String) == teamId {
                        provisionalRank = index + 1
                        break
                    }
                }
            }

            return EkidenViewState(
                event: event,
                entry: entry,
                legs: legs,
                memberNames: memberNames,
                provisionalRank: provisionalRank,
                totalTeams: rankingsSnapshot?.documents.count ?? 0
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
        runActivityId: String? = nil
    ) async -> Result<Void, Error> {
        if isSampleTeam || teamId.hasPrefix("example") {
            return await submitLegMock(
                teamId: teamId,
                legIndex: legIndex,
                actualDistanceKm: actualDistanceKm,
                elapsedSeconds: elapsedSeconds,
                isUnderTarget: isUnderTarget,
                splitAtTargetSeconds: splitAtTargetSeconds,
                submittedByUid: submittedByUid
            )
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
            runActivityId: runActivityId
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
        runActivityId: String? = nil
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
                var updateData: [String: Any] = [
                    "status": EkidenLegStatus.submitted.rawValue,
                    "submittedAt": Timestamp(date: now),
                    "actualDistanceKm": actualDistanceKm,
                    "elapsedSeconds": elapsedSeconds,
                    "isUnderTarget": isUnderTarget
                ]
                if let s = splitAtTargetSeconds { updateData["splitAtTargetSeconds"] = s }
                transaction.updateData(updateData, forDocument: legDoc)

                let nextIndex = legIndex + 1
                let nextLegDoc = legsRef.document("\(nextIndex)")
                if let nextSnap = try? transaction.getDocument(nextLegDoc), nextSnap.exists {
                    transaction.updateData(["status": EkidenLegStatus.ready.rawValue], forDocument: nextLegDoc)
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
}

// MARK: - TeamView 用の駅伝表示状態
struct EkidenViewState {
    let event: EkidenEvent
    let entry: EkidenEntry
    let legs: [EkidenLeg]
    let memberNames: [String: String]
    let provisionalRank: Int?
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

    /// チーム累計走行距離（km）。提出済み区間の actualDistanceKm の合計。パス（isPass）区間は除外
    var cumulativeDistanceKm: Double {
        legs.filter { $0.status == .submitted && !($0.isPass) }
            .compactMap { $0.actualDistanceKm }
            .reduce(0, +)
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

    /// 区間を秒から MM:SS フォーマット
    static func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
