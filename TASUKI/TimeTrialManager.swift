//
//  TimeTrialManager.swift
//  TASUKI
//
//  タイムトライアル部屋の作成・参加・タイム提出・順位取得（EKIDEN とは別）
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

final class TimeTrialManager: ObservableObject {
    static let shared = TimeTrialManager()
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "asia-northeast1")
    
    @Published var currentRoom: TimeTrialRoom?
    @Published var participants: [TimeTrialParticipant] = []
    @Published var errorMessage: String?
    
    private var roomListener: ListenerRegistration?
    private var participantsListener: ListenerRegistration?
    
    private init() {}
    
    /// ログイン中は Firebase UID、未ログインでサンプル部屋に入っている場合は "sample_user"
    var currentUserId: String? {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        if currentRoom?.id.hasPrefix("sample_") == true { return "sample_user" }
        return nil
    }
    
    private static let sampleRoomIdPrefix = "sample_"
    private func isSampleRoom(_ roomId: String) -> Bool { roomId.hasPrefix(Self.sampleRoomIdPrefix) }

    private func trackTimeTrialEvent(_ name: String, properties: [String: Any] = [:]) {
        RealityMiningManager.shared.trackEvent(name: name, properties: properties)
    }
    
    /// "Rank S" -> "S", "Rank A" -> "A" など
    static func rankTier(fromRank rank: String?) -> String {
        guard let r = rank, r.hasPrefix("Rank ") else { return "E" }
        let tier = String(r.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        return tier.isEmpty ? "E" : tier
    }
    
    // MARK: - Create or Join
    
    /// 同距離・同ランクで空きがある部屋を探す。なければ新規作成（期間1週間）
    func createOrJoinRoom(distance: TimeTrialDistance, userRank: String?, userName: String, completion: @escaping (Result<String, Error>) -> Void) {
        if Auth.auth().currentUser == nil {
            // サンプル: 未ログインでもマッチング以降に進める
            trackTimeTrialEvent("time_trial_match_sample", properties: ["distance_km": distance.distanceKm])
            completion(.success("sample_\(distance.rawValue)"))
            return
        }
        guard let uid = currentUserId else {
            completion(.failure(NSError(domain: "TimeTrialManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        let tier = Self.rankTier(fromRank: userRank)
        
        db.collection("time_trial_rooms")
            .whereField("distanceKm", isEqualTo: distance.distanceKm)
            .whereField("rankTier", isEqualTo: tier)
            .whereField("periodEnd", isGreaterThan: Timestamp(date: Date()))
            .order(by: "periodEnd", descending: false)
            .limit(to: 5)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    self?.trackTimeTrialEvent(
                        "time_trial_match_failed",
                        properties: ["distance_km": distance.distanceKm, "error_message": error.localizedDescription]
                    )
                    completion(.failure(error))
                    return
                }
                // 20名未満の部屋を探す
                let doc = snapshot?.documents.first { doc in
                    let count = doc.data()["participantCount"] as? Int ?? 0
                    return count < 20
                }
                if let d = doc {
                    self?.trackTimeTrialEvent(
                        "time_trial_room_matched",
                        properties: ["distance_km": distance.distanceKm, "room_id": d.documentID]
                    )
                    self?.joinRoom(roomId: d.documentID, userId: uid, name: userName, rank: userRank, completion: completion)
                } else {
                    self?.createRoom(distance: distance, rankTier: tier, userId: uid, userName: userName, userRank: userRank, completion: completion)
                }
            }
    }
    
    private func createRoom(distance: TimeTrialDistance, rankTier: String, userId: String, userName: String, userRank: String?, completion: @escaping (Result<String, Error>) -> Void) {
        let ref = db.collection("time_trial_rooms").document()
        let now = Date()
        let periodEnd = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let data: [String: Any] = [
            "distanceKm": distance.distanceKm,
            "rankTier": rankTier,
            "periodStart": Timestamp(date: now),
            "periodEnd": Timestamp(date: periodEnd),
            "createdAt": Timestamp(date: now),
            "participantCount": 0
        ]
        ref.setData(data) { [weak self] error in
            if let error = error {
                self?.trackTimeTrialEvent(
                    "time_trial_room_create_failed",
                    properties: ["distance_km": distance.distanceKm, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
                return
            }
            self?.trackTimeTrialEvent(
                "time_trial_room_created",
                properties: ["distance_km": distance.distanceKm, "room_id": ref.documentID, "rank_tier": rankTier]
            )
            self?.joinRoom(roomId: ref.documentID, userId: userId, name: userName, rank: userRank) { result in
                switch result {
                case .success: completion(.success(ref.documentID))
                case .failure(let e): completion(.failure(e))
                }
            }
        }
    }
    
    private func joinRoom(roomId: String, userId: String, name: String, rank: String?, completion: @escaping (Result<String, Error>) -> Void) {
        functions.httpsCallable("joinTimeTrialRoom").call([
            "roomId": roomId,
            "name": name,
            "rank": rank ?? ""
        ]) { [weak self] _, error in
            if let error = error {
                self?.trackTimeTrialEvent(
                    "time_trial_join_failed",
                    properties: ["room_id": roomId, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
                return
            }
            self?.trackTimeTrialEvent("time_trial_joined", properties: ["room_id": roomId, "rank": rank ?? ""])
            completion(.success(roomId))
        }
    }
    
    // MARK: - Submit Time（期間中1回のみ）
    
    func submitTime(roomId: String, timeSeconds: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        if isSampleRoom(roomId) {
            // サンプル: メモリ上の参加者を更新
            if let i = participants.firstIndex(where: { $0.id == "sample_user" }) {
                var p = participants[i]
                p.submittedTimeSeconds = timeSeconds
                p.submittedAt = Date()
                participants[i] = p
            }
            trackTimeTrialEvent(
                "time_trial_submitted",
                properties: ["room_id": roomId, "time_sec": timeSeconds, "mode": "sample"]
            )
            DispatchQueue.main.async { completion(.success(())) }
            return
        }
        guard currentUserId != nil else {
            completion(.failure(NSError(domain: "TimeTrialManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        functions.httpsCallable("submitTimeTrialResult").call([
            "roomId": roomId,
            "timeSeconds": timeSeconds
        ]) { _, error in
            if let error = error {
                self.trackTimeTrialEvent(
                    "time_trial_submit_failed",
                    properties: ["room_id": roomId, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
            } else {
                self.trackTimeTrialEvent(
                    "time_trial_submitted",
                    properties: ["room_id": roomId, "time_sec": timeSeconds, "mode": "live"]
                )
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Fetch
    
    func fetchRoom(roomId: String, completion: @escaping (Result<TimeTrialRoom, Error>) -> Void) {
        db.collection("time_trial_rooms").document(roomId).getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = snapshot?.data(), let room = self.parseRoom(id: snapshot!.documentID, data: data) else {
                completion(.failure(NSError(domain: "TimeTrialManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "部屋が見つかりません"])))
                return
            }
            completion(.success(room))
        }
    }
    
    func fetchParticipants(roomId: String, completion: @escaping (Result<[TimeTrialParticipant], Error>) -> Void) {
        db.collection("time_trial_rooms").document(roomId).collection("participants")
            .order(by: "joinedAt", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let list = (snapshot?.documents ?? []).map { self.parseParticipant(id: $0.documentID, data: $0.data()) }
                completion(.success(list))
            }
    }
    
    /// 提出済みタイムでソートした順位リスト＋ポイント
    func fetchRanking(roomId: String, completion: @escaping (Result<[TimeTrialRankingEntry], Error>) -> Void) {
        if isSampleRoom(roomId) {
            let submitted = participants.compactMap { p -> (TimeTrialParticipant, Double)? in
                guard let sec = p.submittedTimeSeconds else { return nil }
                return (p, sec)
            }
            let sorted = submitted.sorted { $0.1 < $1.1 }
            let entries = sorted.enumerated().map { index, item in
                TimeTrialRankingEntry(
                    id: item.0.id,
                    rank: index + 1,
                    name: item.0.name,
                    timeSeconds: item.1,
                    points: TimeTrialPoints.points(forRank: index + 1)
                )
            }
            completion(.success(entries))
            return
        }
        fetchParticipants(roomId: roomId) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let list):
                let submitted = list.compactMap { p -> (TimeTrialParticipant, Double)? in
                    guard let sec = p.submittedTimeSeconds else { return nil }
                    return (p, sec)
                }
                let sorted = submitted.sorted { $0.1 < $1.1 }
                let entries = sorted.enumerated().map { index, item in
                    TimeTrialRankingEntry(
                        id: item.0.id,
                        rank: index + 1,
                        name: item.0.name,
                        timeSeconds: item.1,
                        points: TimeTrialPoints.points(forRank: index + 1)
                    )
                }
                // ランク昇格判定（実戦タイムトライアルのみ）
                RankPromotionManager.shared.evaluateTimeTrialPromotion(
                    entries: entries,
                    myUserId: self.currentUserId
                )
                // 本番は Cloud Functions でポイント付与。サンプル部屋のみクライアント側で加算する。
                if self.isSampleRoom(roomId),
                   let myId = self.currentUserId,
                   let myEntry = entries.first(where: { $0.id == myId }) {
                    let key = "timeTrialPointsAwarded_\(roomId)"
                    if !UserDefaults.standard.bool(forKey: key), myEntry.points > 0 {
                        PointService.shared.addPointsToCurrentUser(amount: myEntry.points)
                        UserDefaults.standard.set(true, forKey: key)
                    }
                }
                completion(.success(entries))
            }
        }
    }
    
    // MARK: - Listeners
    
    func startListening(roomId: String) {
        if isSampleRoom(roomId) {
            roomListener?.remove()
            participantsListener?.remove()
            roomListener = nil
            participantsListener = nil
            let room = makeSampleRoom(roomId: roomId)
            let list = makeSampleParticipants()
            DispatchQueue.main.async { [weak self] in
                self?.currentRoom = room
                self?.participants = list
            }
            return
        }
        roomListener?.remove()
        roomListener = db.collection("time_trial_rooms").document(roomId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    return
                }
                guard let data = snapshot?.data() else {
                    DispatchQueue.main.async { self.currentRoom = nil }
                    return
                }
                let room = self.parseRoom(id: snapshot!.documentID, data: data)
                DispatchQueue.main.async { self.currentRoom = room }
            }
        participantsListener?.remove()
        participantsListener = db.collection("time_trial_rooms").document(roomId).collection("participants")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    return
                }
                let list = (snapshot?.documents ?? []).map { self.parseParticipant(id: $0.documentID, data: $0.data()) }
                DispatchQueue.main.async { self.participants = list }
            }
    }
    
    private func makeSampleRoom(roomId: String) -> TimeTrialRoom {
        let dist: Double
        if roomId == "sample_5k" { dist = 5.0 }
        else if roomId == "sample_10k" { dist = 10.0 }
        else if roomId == "sample_15k" { dist = 15.0 }
        else { dist = 5.0 }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? now
        return TimeTrialRoom(
            id: roomId,
            distanceKm: dist,
            rankTier: "B",
            periodStart: start,
            periodEnd: end,
            createdAt: now
        )
    }
    
    private func makeSampleParticipants() -> [TimeTrialParticipant] {
        let names = [
            "あなた",
            "ランナー1", "ランナー2", "ランナー3", "ランナー4", "ランナー5",
            "ランナー6", "ランナー7", "ランナー8", "ランナー9", "ランナー10",
            "ランナー11", "ランナー12", "ランナー13", "ランナー14", "ランナー15",
            "ランナー16", "ランナー17", "ランナー18", "ランナー19"
        ]
        let ids = ["sample_user"] + (1...19).map { "sample_p\($0)" }
        // 一部にサンプルタイムを入れて結果が見やすいように
        let sampleTimes: [Double?] = [
            nil, 18 * 60 + 30, 19 * 60, 19 * 60 + 15, 19 * 60 + 45, 20 * 60,
            20 * 60 + 10, 20 * 60 + 30, 20 * 60 + 50, 21 * 60, 21 * 60 + 20,
            21 * 60 + 40, 22 * 60, 22 * 60 + 15, 22 * 60 + 45, 23 * 60,
            23 * 60 + 30, 24 * 60, 24 * 60 + 30, 25 * 60
        ]
        let now = Date()
        return zip(ids, names).enumerated().map { index, pair in
            TimeTrialParticipant(
                id: pair.0,
                name: pair.1,
                rank: "Rank B",
                joinedAt: now,
                submittedTimeSeconds: sampleTimes[index],
                submittedAt: sampleTimes[index] != nil ? now : nil
            )
        }
    }
    
    func stopListening() {
        roomListener?.remove()
        participantsListener?.remove()
        roomListener = nil
        participantsListener = nil
        DispatchQueue.main.async {
            self.currentRoom = nil
            self.participants = []
        }
    }
    
    // MARK: - Parse
    
    private func parseRoom(id: String, data: [String: Any]) -> TimeTrialRoom? {
        guard let periodEnd = (data["periodEnd"] as? Timestamp)?.dateValue() else { return nil }
        let periodStart = (data["periodStart"] as? Timestamp)?.dateValue() ?? Date()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return TimeTrialRoom(
            id: id,
            distanceKm: data["distanceKm"] as? Double ?? 5.0,
            rankTier: data["rankTier"] as? String ?? "E",
            periodStart: periodStart,
            periodEnd: periodEnd,
            createdAt: createdAt
        )
    }
    
    private func parseParticipant(id: String, data: [String: Any]) -> TimeTrialParticipant {
        let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue() ?? Date()
        let submittedAt = (data["submittedAt"] as? Timestamp)?.dateValue()
        return TimeTrialParticipant(
            id: id,
            name: data["name"] as? String ?? "",
            rank: (data["rank"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            joinedAt: joinedAt,
            submittedTimeSeconds: data["submittedTimeSeconds"] as? Double,
            submittedAt: submittedAt
        )
    }
}
