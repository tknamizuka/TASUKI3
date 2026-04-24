//
//  EkidenModels.swift
//  TASUKI
//
//  バーチャル駅伝: イベント・エントリー・区間・TASUKI状態・提出の Firestore モデル
//

import Foundation
import FirebaseFirestore

// MARK: - Firestore Collection Paths

/// Firestore コレクション・パス定数
enum EkidenFirestorePaths {
    static let events = "ekiden_events"
    static let entries = "ekiden_entries"
    static let legs = "legs"
    static let submissions = "submissions"
    static let rankings = "rankings"

    static func event(_ eventId: String) -> String { "\(events)/\(eventId)" }
    static func entry(_ entryId: String) -> String { "\(entries)/\(entryId)" }
    static func entryLegs(_ entryId: String) -> String { "\(entries)/\(entryId)/\(legs)" }
    static func entrySubmissions(_ entryId: String) -> String { "\(entries)/\(entryId)/\(submissions)" }
}

// MARK: - Ekiden Event Status

/// 駅伝イベントのステータス
enum EkidenEventStatus: String, Codable {
    case scheduled = "scheduled"   // 予定
    case active = "active"         // 開催中
    case finished = "finished"     // 終了
}

// MARK: - Ekiden Leg Status（TASUKIリレー状態）

/// 区間のTASUKI状態: 未開始 → 前区間完了待ち → TASUKI渡し済み・提出可能 → 提出済み
enum EkidenLegStatus: String, Codable {
    case awaitingTasuki = "awaitingTasuki"   // 前区間のTASUKI待ち（Firestoreキー互換）
    case ready = "ready"                     // TASUKI渡し済み・提出可能
    case submitted = "submitted"             // 提出済み
}

// MARK: - EkidenEvent（Firestore: ekiden_events/{eventId}）

/// 駅伝イベント定義: 開催期間、区間数、各区間の目標距離（参考値）、ルール文
struct EkidenEvent: Identifiable {
    let id: String
    let startAt: Date
    let endAt: Date
    let legCount: Int
    /// 各区間の目標距離（km）の配列。インデックスが区間番号（0=1区）
    let legs: [EkidenLegDefinition]
    let status: EkidenEventStatus
    let rulesText: String?
    let createdAt: Date
    /// チーム全体の目標距離（km）。累計モード用。未設定なら区間ベースUIにフォールバック
    let teamGoalKm: Double?
    /// コースプリセット（例: `"hakone"` で箱根10区・襷ルール・提出フィルタを有効化）
    let coursePreset: String?
    
    /// イベント期間内であるか
    var isWithinEventWindow: Bool {
        let now = Date()
        return now >= startAt && now <= endAt
    }
    
    /// イベント終了済みであるか
    var isFinished: Bool {
        Date() > endAt || status == .finished
    }
}

/// 区間定義（イベント側）: 順番と目標距離
struct EkidenLegDefinition: Identifiable {
    let id: Int  // 区間番号（0-indexed、0=1区）
    let targetKm: Double
    let order: Int  // 走順（1区=1, 2区=2, ...）
}

// MARK: - EkidenEntry（Firestore: ekiden_entries/{entryId}）

/// チームの駅伝エントリー: チーム・イベント・オーナー・TASUKI状態
struct EkidenEntry: Identifiable {
    let id: String
    let teamId: String
    let eventId: String
    let ownerUid: String
    /// 現在進行中の区間インデックス（0-indexed）
    var currentLegIndex: Int
    /// TASUKIの状態（オプションでCloud Functionsが管理）
    var tasukiState: String?
    let createdAt: Date
    let updatedAt: Date
    /// 棄権等で公式合計タイムランキングから除外（参考記録扱い）
    let officialResultDisqualified: Bool
}

// MARK: - EkidenLeg（Firestore: ekiden_entries/{entryId}/legs/{legIndex}）

/// エントリー内の区間: 担当者・目標距離・TASUKI状態・提出結果
struct EkidenLeg: Identifiable {
    let id: Int  // legIndex（0=1区）
    let assignedUid: String?
    let targetKm: Double
    var status: EkidenLegStatus
    var submittedAt: Date?
    var actualDistanceKm: Double?
    var elapsedSeconds: Double?
    /// 目標距離未達で提出した場合は true
    var isUnderTarget: Bool
    /// 目標距離超過時に、目標距離到達時点の通過タイム（秒）。超過時のみ
    var splitAtTargetSeconds: Double?
    /// パス（走らずTASUKIだけ次へ）の場合は true。累計距離に加算しない
    var isPass: Bool
    
    var isSubmitted: Bool { status == .submitted }
    
    /// TASUKIが渡っていて提出可能か
    var canSubmit: Bool { status == .ready }
}

// MARK: - EkidenSubmission（Firestore: ekiden_entries/{entryId}/submissions/{submissionId}）

/// 提出の監査ログ: ソース、走行アクティビティID等
struct EkidenSubmission: Identifiable {
    let id: String
    let legIndex: Int
    let submittedByUid: String
    let submittedAt: Date
    let source: String           // "health_kit" | "manual" | "time_trial" 等
    let runActivityId: String?   // HealthKit 等の記録ID
    let actualDistanceKm: Double
    let elapsedSeconds: Double
    let isUnderTarget: Bool
    let splitAtTargetSeconds: Double?
}

// MARK: - Firestore パースヘルパー

extension EkidenEvent {
    /// Firestore ドキュメントからパース
    /// legs は目標距離の配列 [Double] または [{targetKm: Double}, ...] 形式をサポート
    static func parse(id: String, data: [String: Any]) -> EkidenEvent? {
        guard let startTs = data["startAt"] as? Timestamp,
              let endTs = data["endAt"] as? Timestamp else { return nil }
        let legCount = data["legCount"] as? Int ?? 0
        let legs: [EkidenLegDefinition]
        if let numbers = data["legs"] as? [Double] {
            legs = numbers.enumerated().map { EkidenLegDefinition(id: $0.offset, targetKm: $0.element, order: $0.offset + 1) }
        } else if let legsData = data["legs"] as? [[String: Any]] {
            legs = legsData.enumerated().compactMap { index, legData -> EkidenLegDefinition? in
                guard let targetKm = legData["targetKm"] as? Double else { return nil }
                return EkidenLegDefinition(id: index, targetKm: targetKm, order: index + 1)
            }
        } else {
            legs = (0..<max(1, legCount)).map { EkidenLegDefinition(id: $0, targetKm: 5.0, order: $0 + 1) }
        }
        let statusRaw = data["status"] as? String ?? EkidenEventStatus.scheduled.rawValue
        let status = EkidenEventStatus(rawValue: statusRaw) ?? .scheduled
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let teamGoalKm = data["teamGoalKm"] as? Double
        let coursePreset = data["coursePreset"] as? String
        return EkidenEvent(
            id: id,
            startAt: startTs.dateValue(),
            endAt: endTs.dateValue(),
            legCount: max(legCount, legs.count),
            legs: legs.isEmpty ? (0..<max(1, legCount)).map { EkidenLegDefinition(id: $0, targetKm: 5.0, order: $0 + 1) } : legs,
            status: status,
            rulesText: data["rulesText"] as? String,
            createdAt: createdAt,
            teamGoalKm: teamGoalKm,
            coursePreset: coursePreset
        )
    }
}

extension EkidenEntry {
    /// Firestore ドキュメントからパース
    static func parse(id: String, data: [String: Any]) -> EkidenEntry? {
        guard let teamId = data["teamId"] as? String,
              let eventId = data["eventId"] as? String,
              let ownerUid = data["ownerUid"] as? String else { return nil }
        let currentLegIndex = data["currentLegIndex"] as? Int ?? 0
        let tasukiState = data["tasukiState"] as? String
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        let officialResultDisqualified = data["officialResultDisqualified"] as? Bool ?? false
        return EkidenEntry(
            id: id,
            teamId: teamId,
            eventId: eventId,
            ownerUid: ownerUid,
            currentLegIndex: currentLegIndex,
            tasukiState: tasukiState,
            createdAt: createdAt,
            updatedAt: updatedAt,
            officialResultDisqualified: officialResultDisqualified
        )
    }
}

extension EkidenLeg {
    /// Firestore ドキュメントからパース（legs サブコレクションのドキュメントIDが legIndex）
    static func parse(legIndex: Int, data: [String: Any]) -> EkidenLeg {
        let statusRaw = data["status"] as? String ?? EkidenLegStatus.awaitingTasuki.rawValue
        let status = EkidenLegStatus(rawValue: statusRaw) ?? .awaitingTasuki
        let submittedAt = (data["submittedAt"] as? Timestamp)?.dateValue()
        let actualDistanceKm = data["actualDistanceKm"] as? Double
        let elapsedSeconds = data["elapsedSeconds"] as? Double
        let isUnderTarget = data["isUnderTarget"] as? Bool ?? false
        let splitAtTargetSeconds = data["splitAtTargetSeconds"] as? Double
        let isPass = data["isPass"] as? Bool ?? false
        return EkidenLeg(
            id: legIndex,
            assignedUid: data["assignedUid"] as? String,
            targetKm: data["targetKm"] as? Double ?? 5.0,
            status: status,
            submittedAt: submittedAt,
            actualDistanceKm: actualDistanceKm,
            elapsedSeconds: elapsedSeconds,
            isUnderTarget: isUnderTarget,
            splitAtTargetSeconds: splitAtTargetSeconds,
            isPass: isPass
        )
    }
}

extension EkidenSubmission {
    /// Firestore ドキュメントからパース
    static func parse(id: String, data: [String: Any]) -> EkidenSubmission? {
        guard let legIndex = data["legIndex"] as? Int,
              let submittedByUid = data["submittedByUid"] as? String,
              let source = data["source"] as? String,
              let actualDistanceKm = data["actualDistanceKm"] as? Double,
              let elapsedSeconds = data["elapsedSeconds"] as? Double else { return nil }
        let submittedAt = (data["submittedAt"] as? Timestamp)?.dateValue() ?? Date()
        let isUnderTarget = data["isUnderTarget"] as? Bool ?? false
        let splitAtTargetSeconds = data["splitAtTargetSeconds"] as? Double
        return EkidenSubmission(
            id: id,
            legIndex: legIndex,
            submittedByUid: submittedByUid,
            submittedAt: submittedAt,
            source: source,
            runActivityId: data["runActivityId"] as? String,
            actualDistanceKm: actualDistanceKm,
            elapsedSeconds: elapsedSeconds,
            isUnderTarget: isUnderTarget,
            splitAtTargetSeconds: splitAtTargetSeconds
        )
    }
}

// MARK: - 区間賞（leg_rankings スナップショット）

/// Cloud Functions が `ekiden_events/{eventId}/leg_rankings/{legIndex}` に書き込む1区間分のランキング
struct EkidenLegRankingRow: Identifiable {
    var id: String { "\(rank)-\(entryId)" }
    let rank: Int
    let entryId: String
    let teamId: String
    let runnerUid: String
    let elapsedSeconds: Double
    let displayName: String
}

struct EkidenLegRankingSnapshot {
    let legIndex: Int
    let top: [EkidenLegRankingRow]
    let ranksByEntryId: [String: Int]
    let totalFinishers: Int
    let updatedAt: Date?

    /// 自チームのエントリーが上位表にいない場合でも `ranksByEntryId` で順位を表示
    func rank(forEntryId entryId: String) -> Int? {
        ranksByEntryId[entryId]
    }

    static func parse(legIndex: Int, data: [String: Any]) -> EkidenLegRankingSnapshot? {
        let topRaw = data["top"] as? [[String: Any]] ?? []
        var rankMap = data["ranksByEntryId"] as? [String: Int] ?? [:]
        if rankMap.isEmpty, let nested = data["ranksByEntryId"] as? [String: Any] {
            for (k, v) in nested {
                if let i = v as? Int {
                    rankMap[k] = i
                } else if let d = v as? Double {
                    rankMap[k] = Int(d)
                }
            }
        }
        let total = data["totalFinishers"] as? Int ?? rankMap.count
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        let top: [EkidenLegRankingRow] = topRaw.compactMap { row in
            guard let entryId = row["entryId"] as? String,
                  let teamId = row["teamId"] as? String,
                  let runnerUid = row["runnerUid"] as? String else { return nil }
            let rank = row["rank"] as? Int ?? 0
            let elapsed = row["elapsedSeconds"] as? Double ?? Double(row["elapsedSeconds"] as? Int ?? 0)
            let name = row["displayName"] as? String ?? runnerUid
            return EkidenLegRankingRow(
                rank: rank,
                entryId: entryId,
                teamId: teamId,
                runnerUid: runnerUid,
                elapsedSeconds: elapsed,
                displayName: name
            )
        }
        return EkidenLegRankingSnapshot(
            legIndex: legIndex,
            top: top,
            ranksByEntryId: rankMap,
            totalFinishers: total,
            updatedAt: updatedAt
        )
    }

    /// サンプルチーム用: 同一 `EkidenViewState` からデモ用ランキングを合成
    static func buildMock(from state: EkidenViewState, legIndex: Int) -> EkidenLegRankingSnapshot {
        guard legIndex >= 0, legIndex < state.legs.count else {
            return EkidenLegRankingSnapshot(legIndex: legIndex, top: [], ranksByEntryId: [:], totalFinishers: 0, updatedAt: Date())
        }
        let leg = state.legs[legIndex]
        guard leg.status == .submitted, !leg.isPass,
              let myElapsed = leg.splitAtTargetSeconds ?? leg.elapsedSeconds else {
            return EkidenLegRankingSnapshot(legIndex: legIndex, top: [], ranksByEntryId: [:], totalFinishers: 0, updatedAt: Date())
        }
        let uid = leg.assignedUid ?? ""
        let myName = state.memberNames[uid] ?? "あなた"
        var rows: [(entryId: String, teamId: String, runnerUid: String, elapsed: Double, name: String)] = []
        rows.append((state.entry.id, state.entry.teamId, uid, myElapsed, myName))
        var h = Hasher()
        h.combine(state.event.id)
        h.combine(legIndex)
        let baseSeed = UInt64(truncatingIfNeeded: h.finalize())
        for i in 0..<9 {
            let jitter = Double((baseSeed &+ UInt64(i) * 7919) % 240) - 120.0
            let t = max(120, myElapsed + jitter)
            rows.append(("mock_e_\(i)", "mock_t_\(i)", "mock_u_\(i)", t, "ランナー \(i + 1)"))
        }
        rows.sort { a, b in
            if a.elapsed != b.elapsed { return a.elapsed < b.elapsed }
            return a.entryId < b.entryId
        }
        let top = rows.enumerated().map { idx, r in
            EkidenLegRankingRow(
                rank: idx + 1,
                entryId: r.entryId,
                teamId: r.teamId,
                runnerUid: r.runnerUid,
                elapsedSeconds: r.elapsed,
                displayName: r.name
            )
        }
        var ranks: [String: Int] = [:]
        for (idx, r) in rows.enumerated() {
            ranks[r.entryId] = idx + 1
        }
        return EkidenLegRankingSnapshot(
            legIndex: legIndex,
            top: top,
            ranksByEntryId: ranks,
            totalFinishers: rows.count,
            updatedAt: Date()
        )
    }
}
