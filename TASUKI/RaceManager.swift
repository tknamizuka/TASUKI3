//
//  RaceManager.swift
//  TASUKI
//
//  レースの作成・参加・スタート・距離更新・ゴール記録
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

final class RaceManager: ObservableObject {
    static let shared = RaceManager()
    /// プレビューでインスタンス生成時に Firestore に触れないよう lazy にしている
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "asia-northeast1")
    
    @Published var currentRace: Race?
    @Published var participants: [RaceParticipant] = []
    @Published var errorMessage: String?
    
    private var raceListener: ListenerRegistration?
    private var participantsListener: ListenerRegistration?
    
    private init() {}
    
    /// ログイン中は Firebase UID、未ログインでサンプルレースのときは "sample_user"
    var currentUserId: String? {
        if let uid = Auth.auth().currentUser?.uid { return uid }
        if currentRace?.id.hasPrefix("sample_") == true { return "sample_user" }
        return nil
    }
    
    private static let sampleRaceIdPrefix = "sample_"
    private func isSampleRace(_ raceId: String) -> Bool { raceId.hasPrefix(Self.sampleRaceIdPrefix) }

    private func trackRaceEvent(_ name: String, properties: [String: Any] = [:]) {
        RealityMiningManager.shared.trackEvent(name: name, properties: properties)
    }
    
    // MARK: - Create / Join
    
    /// 指定カテゴリで新規レースを作成し、作成者を参加させる
    func createRace(category: LiveRaceCategory, userName: String, userRank: String?, completion: @escaping (Result<String, Error>) -> Void) {
        guard let uid = currentUserId else {
            completion(.failure(NSError(domain: "RaceManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        let ref = db.collection("races").document()
        let now = Timestamp(date: Date())
        let data: [String: Any] = [
            "distanceCategory": category.rawValue,
            "targetDistanceKm": category.targetDistanceKm,
            "status": RaceStatus.waiting.rawValue,
            "createdAt": now,
            "hostUserId": uid
        ]
        ref.setData(data) { [weak self] error in
            if let error = error {
                self?.trackRaceEvent(
                    "race_create_failed",
                    properties: ["category": category.rawValue, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
                return
            }
            self?.trackRaceEvent("race_created", properties: ["category": category.rawValue, "race_id": ref.documentID])
            self?.joinRace(raceId: ref.documentID, userId: uid, name: userName, rank: userRank) { result in
                switch result {
                case .success: completion(.success(ref.documentID))
                case .failure(let e): completion(.failure(e))
                }
            }
        }
    }
    
    /// 既存の「待機中」レースを検索（カテゴリ一致）
    func findWaitingRace(category: LiveRaceCategory, completion: @escaping (Result<String?, Error>) -> Void) {
        db.collection("races")
            .whereField("distanceCategory", isEqualTo: category.rawValue)
            .whereField("status", isEqualTo: RaceStatus.waiting.rawValue)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                let id = snapshot?.documents.first?.documentID
                completion(.success(id))
            }
    }
    
    /// レースに参加
    func joinRace(raceId: String, userId: String, name: String, rank: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let ref = db.collection("races").document(raceId).collection("participants").document(userId)
        let data: [String: Any] = [
            "name": name,
            "rank": rank ?? "",
            "currentDistanceKm": 0.0,
            "joinedAt": Timestamp(date: Date())
        ]
        ref.setData(data, merge: true) { error in
            if let error = error {
                self.trackRaceEvent(
                    "race_join_failed",
                    properties: ["race_id": raceId, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
            } else {
                self.trackRaceEvent("race_joined", properties: ["race_id": raceId, "rank": rank ?? ""])
                completion(.success(()))
            }
        }
    }
    
    /// マッチング: 待機中のレースがあれば参加、なければ作成
    func matchOrCreate(category: LiveRaceCategory, userName: String, userRank: String?, completion: @escaping (Result<String, Error>) -> Void) {
        if Auth.auth().currentUser == nil {
            // モック: 未ログインでもエントリ以降に進める
            let sampleId = "sample_\(category.rawValue)"
            completion(.success(sampleId))
            return
        }
        findWaitingRace(category: category) { [weak self] result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let raceId):
                if let raceId = raceId, let uid = self?.currentUserId {
                    self?.joinRace(raceId: raceId, userId: uid, name: userName, rank: userRank) { joinResult in
                        switch joinResult {
                        case .success: completion(.success(raceId))
                        case .failure(let e): completion(.failure(e))
                        }
                    }
                } else {
                    self?.createRace(category: category, userName: userName, userRank: userRank, completion: completion)
                }
            }
        }
    }
    
    // MARK: - Start Race (Host)
    
    /// レースをスタート（カウントダウン後に startTime を設定）
    func startRace(raceId: String, countdownSeconds: Int = 5, completion: @escaping (Result<Void, Error>) -> Void) {
        if isSampleRace(raceId), var race = currentRace, race.id == raceId {
            let startTime = Date().addingTimeInterval(TimeInterval(countdownSeconds))
            race.status = .starting
            race.startTime = startTime
            DispatchQueue.main.async { [weak self] in
                self?.currentRace = race
                self?.trackRaceEvent(
                    "race_start_requested",
                    properties: ["race_id": raceId, "countdown_sec": countdownSeconds, "mode": "sample"]
                )
                completion(.success(()))
            }
            return
        }
        let startTime = Date().addingTimeInterval(TimeInterval(countdownSeconds))
        db.collection("races").document(raceId).updateData([
            "status": RaceStatus.starting.rawValue,
            "startTime": Timestamp(date: startTime)
        ]) { error in
            if let error = error {
                self.trackRaceEvent(
                    "race_start_failed",
                    properties: ["race_id": raceId, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
            } else {
                self.trackRaceEvent(
                    "race_start_requested",
                    properties: ["race_id": raceId, "countdown_sec": countdownSeconds, "mode": "live"]
                )
                completion(.success(()))
            }
        }
    }
    
    /// startTime を過ぎていたら status を running に更新（どれか1クライアントが呼ぶ）
    func ensureRaceRunning(raceId: String, startTime: Date?) {
        guard let start = startTime, Date() >= start else { return }
        if isSampleRace(raceId), var race = currentRace, race.id == raceId, race.status == .starting {
            race.status = .running
            DispatchQueue.main.async { [weak self] in self?.currentRace = race }
            return
        }
        db.collection("races").document(raceId).getDocument { [weak self] snapshot, _ in
            guard let data = snapshot?.data(),
                  (data["status"] as? String) == RaceStatus.starting.rawValue else { return }
            self?.db.collection("races").document(raceId).updateData([
                "status": RaceStatus.running.rawValue
            ]) { _ in }
        }
    }
    
    // MARK: - Listeners
    
    /// レースドキュメントをリアルタイム監視
    func listenToRace(raceId: String) {
        raceListener?.remove()
        raceListener = db.collection("races").document(raceId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    return
                }
                guard let data = snapshot?.data() else {
                    DispatchQueue.main.async { self.currentRace = nil }
                    return
                }
                let race = self.parseRace(id: snapshot!.documentID, data: data)
                DispatchQueue.main.async {
                    self.currentRace = race
                    if race.status == .running && race.startTime == nil {
                        // startTime が無い場合は starting の startTime をそのまま使う
                    }
                }
            }
    }
    
    /// 参加者一覧をリアルタイム監視
    func listenToParticipants(raceId: String) {
        participantsListener?.remove()
        participantsListener = db.collection("races").document(raceId).collection("participants")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                    return
                }
                let list = (snapshot?.documents ?? []).map { doc in
                    self.parseParticipant(id: doc.documentID, data: doc.data())
                }
                DispatchQueue.main.async { self.participants = list }
            }
    }
    
    /// レース監視を開始（race + participants）
    func startListening(raceId: String) {
        if isSampleRace(raceId) {
            raceListener?.remove()
            participantsListener?.remove()
            raceListener = nil
            participantsListener = nil
            // 既に同じサンプルレースの状態があれば上書きしない（ゴール記録を保持）
            if currentRace?.id == raceId {
                return
            }
            let race = makeSampleRace(raceId: raceId)
            let list = makeSampleParticipants()
            DispatchQueue.main.async { [weak self] in
                self?.currentRace = race
                self?.participants = list
            }
            return
        }
        listenToRace(raceId: raceId)
        listenToParticipants(raceId: raceId)
    }
    
    private func makeSampleRace(raceId: String) -> Race {
        let (category, targetKm): (String, Double) = {
            if raceId == "sample_5k" { return ("5k", 5.0) }
            if raceId == "sample_10k" { return ("10k", 10.0) }
            if raceId == "sample_half" { return ("half", 21.0975) }
            return ("5k", 5.0)
        }()
        return Race(
            id: raceId,
            distanceCategory: category,
            targetDistanceKm: targetKm,
            status: .waiting,
            startTime: nil,
            createdAt: Date(),
            hostUserId: "sample_user"
        )
    }
    
    private func makeSampleParticipants() -> [RaceParticipant] {
        let now = Date()
        return [
            RaceParticipant(id: "sample_user", name: "あなた", rank: "Rank B", currentDistanceKm: 0, finishTimeSeconds: nil, joinedAt: now),
            RaceParticipant(id: "p1", name: "ランナー1", rank: "Rank A", currentDistanceKm: 0, finishTimeSeconds: nil, joinedAt: now),
            RaceParticipant(id: "p2", name: "ランナー2", rank: "Rank B", currentDistanceKm: 0, finishTimeSeconds: nil, joinedAt: now),
            RaceParticipant(id: "p3", name: "ランナー3", rank: "Rank C", currentDistanceKm: 0, finishTimeSeconds: nil, joinedAt: now)
        ]
    }
    
    func stopListening() {
        raceListener?.remove()
        participantsListener?.remove()
        raceListener = nil
        participantsListener = nil
        DispatchQueue.main.async {
            self.currentRace = nil
            self.participants = []
        }
    }
    
    // MARK: - During Race
    
    /// 現在の走行距離を更新（定期的に呼ぶ）
    func updateMyDistance(raceId: String, distanceKm: Double) {
        if isSampleRace(raceId), let idx = participants.firstIndex(where: { $0.id == currentUserId }) {
            var p = participants[idx]
            p.currentDistanceKm = distanceKm
            participants[idx] = p
            return
        }
        guard let uid = currentUserId else { return }
        db.collection("races").document(raceId).collection("participants").document(uid)
            .updateData(["currentDistanceKm": distanceKm]) { _ in }
        if distanceKm > 0 {
            let bucket = Int(distanceKm)
            if bucket > 0 && abs(distanceKm - Double(bucket)) < 0.02 {
                trackRaceEvent("race_distance_progress", properties: ["race_id": raceId, "distance_bucket_km": bucket])
            }
        }
    }
    
    /// ゴールを記録（経過秒数を送信）
    func submitFinish(raceId: String, finishTimeSeconds: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        if isSampleRace(raceId), let idx = participants.firstIndex(where: { $0.id == currentUserId }) {
            var p = participants[idx]
            p.finishTimeSeconds = finishTimeSeconds
            participants[idx] = p
            trackRaceEvent(
                "race_finish_submitted",
                properties: ["race_id": raceId, "finish_time_sec": finishTimeSeconds, "mode": "sample"]
            )
            DispatchQueue.main.async { completion(.success(())) }
            return
        }
        guard currentUserId != nil else {
            completion(.failure(NSError(domain: "RaceManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "未ログイン"])))
            return
        }
        functions.httpsCallable("submitRaceFinish").call(["raceId": raceId]) { _, error in
                if let error = error {
                    self.trackRaceEvent(
                        "race_finish_submit_failed",
                        properties: ["race_id": raceId, "error_message": error.localizedDescription]
                    )
                    completion(.failure(error))
                } else {
                    self.trackRaceEvent(
                        "race_finish_submitted",
                        properties: ["race_id": raceId, "finish_time_sec": finishTimeSeconds, "mode": "live"]
                    )
                    completion(.success(()))
                }
            }
    }
    
    /// レースを終了状態にする（全員ゴール後や制限時間でホストが呼ぶ）
    func finishRace(raceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        if isSampleRace(raceId), var race = currentRace, race.id == raceId {
            race.status = .finished
            DispatchQueue.main.async { [weak self] in
                self?.currentRace = race
                self?.trackRaceEvent("race_finished", properties: ["race_id": raceId, "mode": "sample"])
                completion(.success(()))
            }
            return
        }
        db.collection("races").document(raceId).updateData([
            "status": RaceStatus.finished.rawValue
        ]) { error in
            if let error = error {
                self.trackRaceEvent(
                    "race_finish_failed",
                    properties: ["race_id": raceId, "error_message": error.localizedDescription]
                )
                completion(.failure(error))
            } else {
                self.trackRaceEvent("race_finished", properties: ["race_id": raceId, "mode": "live"])
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Parse
    
    private func parseRace(id: String, data: [String: Any]) -> Race {
        let statusRaw = data["status"] as? String ?? RaceStatus.waiting.rawValue
        let status = RaceStatus(rawValue: statusRaw) ?? .waiting
        let startTime = (data["startTime"] as? Timestamp)?.dateValue()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        return Race(
            id: id,
            distanceCategory: data["distanceCategory"] as? String ?? "5k",
            targetDistanceKm: data["targetDistanceKm"] as? Double ?? 5.0,
            status: status,
            startTime: startTime,
            createdAt: createdAt,
            hostUserId: data["hostUserId"] as? String
        )
    }
    
    private func parseParticipant(id: String, data: [String: Any]) -> RaceParticipant {
        let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue() ?? Date()
        return RaceParticipant(
            id: id,
            name: data["name"] as? String ?? "",
            rank: (data["rank"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            currentDistanceKm: data["currentDistanceKm"] as? Double ?? 0,
            finishTimeSeconds: data["finishTimeSeconds"] as? Double,
            joinedAt: joinedAt
        )
    }
}
