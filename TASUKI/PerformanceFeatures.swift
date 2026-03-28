import Foundation
import CoreLocation
import Combine
import FirebaseAuth
import FirebaseFirestore

struct CodableCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RunActivity: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval
    let distanceKm: Double
    let route: [CodableCoordinate]
    let source: String
    /// 1〜5（主観のきつさ）。記録直後のアンケート任意。
    var perceivedEffort: Int?
    /// 1〜5（走後の気分）。記録直後のアンケート任意。
    var postRunMood: Int?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        durationSeconds: TimeInterval,
        distanceKm: Double,
        route: [CodableCoordinate],
        source: String,
        perceivedEffort: Int? = nil,
        postRunMood: Int? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.route = route
        self.source = source
        self.perceivedEffort = perceivedEffort
        self.postRunMood = postRunMood
    }

    var paceSecondsPerKm: Double? {
        guard distanceKm > 0 else { return nil }
        return durationSeconds / distanceKm
    }

    var paceLabel: String {
        guard let sec = paceSecondsPerKm else { return "--:--/km" }
        let minutes = Int(sec) / 60
        let seconds = Int(sec) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}

@MainActor
final class RunActivityStore: ObservableObject {
    static let shared = RunActivityStore()

    @Published private(set) var activities: [RunActivity] = []

    private let storageKey = "tasuki.run_activities.v1"
    private let maxStoredCount = 300
    private lazy var db = Firestore.firestore()

    private init() {
        load()
        syncFromRemoteIfNeeded()
    }

    func refreshFromRemote() {
        syncFromRemoteIfNeeded()
    }

    @discardableResult
    func addActivity(
        distanceKm: Double,
        durationSeconds: TimeInterval,
        routeCoordinates: [CLLocationCoordinate2D],
        source: String,
        perceivedEffort: Int? = nil,
        postRunMood: Int? = nil
    ) -> RunActivity {
        let sanitizedDistance = max(0, distanceKm)
        let sanitizedDuration = max(1, durationSeconds)
        let endedAt = Date()
        let startedAt = endedAt.addingTimeInterval(-sanitizedDuration)
        let activity = RunActivity(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: sanitizedDuration,
            distanceKm: sanitizedDistance,
            route: routeCoordinates.map(CodableCoordinate.init),
            source: source,
            perceivedEffort: perceivedEffort,
            postRunMood: postRunMood
        )
        activities.insert(activity, at: 0)
        if activities.count > maxStoredCount {
            activities = Array(activities.prefix(maxStoredCount))
        }
        save()
        uploadActivityIfPossible(activity)
        EngagementSignals.touchSignificantInteraction()
        RealityMiningManager.shared.trackEvent(
            name: "run_activity_saved",
            properties: [
                "distance_km": sanitizedDistance,
                "duration_sec": sanitizedDuration,
                "source": source
            ]
        )
        return activity
    }

    func updateActivitySubjective(id: UUID, perceivedEffort: Int?, postRunMood: Int?) {
        guard let idx = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[idx].perceivedEffort = perceivedEffort
        activities[idx].postRunMood = postRunMood
        save()
        uploadActivityIfPossible(activities[idx])
        RealityMiningManager.shared.trackEvent(
            name: "run_activity_subjective_updated",
            properties: [:]
        )
    }

    func daysSinceLastRun(now: Date = Date()) -> Int {
        guard let last = activities.map(\.startedAt).max() else { return 0 }
        let cal = Calendar.current
        let a = cal.startOfDay(for: last)
        let b = cal.startOfDay(for: now)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    func activitiesInCurrentMonth(now: Date = Date()) -> [RunActivity] {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }
        return activities.filter { $0.startedAt >= startOfMonth && $0.startedAt <= now }
    }

    func monthlyDistanceKm(now: Date = Date()) -> Double {
        activitiesInCurrentMonth(now: now).reduce(0) { $0 + $1.distanceKm }
    }

    func monthlyRunCount(now: Date = Date()) -> Int {
        activitiesInCurrentMonth(now: now).count
    }

    func weeklyRunCount(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return activities.filter { weekInterval.contains($0.startedAt) }.count
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            activities = []
            return
        }
        do {
            activities = try JSONDecoder().decode([RunActivity].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            activities = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(activities)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Intentionally ignore persistence failures.
        }
    }

    private func uploadActivityIfPossible(_ activity: RunActivity) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let route = activity.route.map { ["lat": $0.latitude, "lon": $0.longitude] }
        var payload: [String: Any] = [
            "id": activity.id.uuidString,
            "startedAt": Timestamp(date: activity.startedAt),
            "endedAt": Timestamp(date: activity.endedAt),
            "durationSeconds": activity.durationSeconds,
            "distanceKm": activity.distanceKm,
            "route": route,
            "source": activity.source
        ]
        if let e = activity.perceivedEffort { payload["perceivedEffort"] = e }
        if let m = activity.postRunMood { payload["postRunMood"] = m }
        db.collection("users")
            .document(uid)
            .collection("activities")
            .document(activity.id.uuidString)
            .setData(payload, merge: true)
    }

    private func syncFromRemoteIfNeeded() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users")
            .document(uid)
            .collection("activities")
            .order(by: "startedAt", descending: true)
            .limit(to: maxStoredCount)
            .getDocuments { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                let remote = docs.compactMap { doc -> RunActivity? in
                    let data = doc.data()
                    guard
                        let idString = data["id"] as? String,
                        let id = UUID(uuidString: idString),
                        let startedAt = (data["startedAt"] as? Timestamp)?.dateValue(),
                        let endedAt = (data["endedAt"] as? Timestamp)?.dateValue(),
                        let durationSeconds = data["durationSeconds"] as? Double,
                        let distanceKm = data["distanceKm"] as? Double
                    else {
                        return nil
                    }
                    let routeRaw = data["route"] as? [[String: Double]] ?? []
                    let route = routeRaw.compactMap { item -> CodableCoordinate? in
                        guard let lat = item["lat"], let lon = item["lon"] else { return nil }
                        return CodableCoordinate(latitude: lat, longitude: lon)
                    }
                    let source = data["source"] as? String ?? "unknown"
                    let perceivedEffort = data["perceivedEffort"] as? Int
                    let postRunMood = data["postRunMood"] as? Int
                    return RunActivity(
                        id: id,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        durationSeconds: durationSeconds,
                        distanceKm: distanceKm,
                        route: route,
                        source: source,
                        perceivedEffort: perceivedEffort,
                        postRunMood: postRunMood
                    )
                }
                if remote.isEmpty { return }
                DispatchQueue.main.async {
                    var mergedById: [UUID: RunActivity] = Dictionary(uniqueKeysWithValues: self.activities.map { ($0.id, $0) })
                    for item in remote {
                        mergedById[item.id] = item
                    }
                    self.activities = mergedById.values
                        .sorted { $0.startedAt > $1.startedAt }
                    if self.activities.count > self.maxStoredCount {
                        self.activities = Array(self.activities.prefix(self.maxStoredCount))
                    }
                    self.save()
                }
            }
    }
}

enum TrainingPlanTemplate: String, CaseIterable, Identifiable, Codable {
    case finish = "finish_plan"
    case sub4 = "sub4_plan"
    case sub3 = "sub3_plan"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .finish: return "完走プラン"
        case .sub4: return "サブ4プラン"
        case .sub3: return "サブ3プラン"
        }
    }

    var summary: String {
        switch self {
        case .finish: return "週3回ペースで無理なく継続"
        case .sub4: return "ペース走と距離走で土台を作る"
        case .sub3: return "高強度を含む競技志向の構成"
        }
    }
}

struct TrainingSessionItem: Identifiable, Hashable {
    let id: String
    let dayLabel: String
    let title: String
    let detail: String
    let targetKm: Double
}

@MainActor
final class TrainingPlanStore: ObservableObject {
    static let shared = TrainingPlanStore()

    @Published var selectedTemplate: TrainingPlanTemplate {
        didSet {
            UserDefaults.standard.set(selectedTemplate.rawValue, forKey: selectedTemplateKey)
            syncToRemoteIfPossible()
            RealityMiningManager.shared.trackEvent(
                name: "training_plan_selected",
                properties: ["template": selectedTemplate.rawValue]
            )
        }
    }
    @Published private(set) var completedSessionIDs: Set<String> = []

    private let selectedTemplateKey = "tasuki.training_template.v1"
    private let completedPrefix = "tasuki.training_completed."
    private lazy var db = Firestore.firestore()

    private init() {
        let raw = UserDefaults.standard.string(forKey: selectedTemplateKey)
        self.selectedTemplate = TrainingPlanTemplate(rawValue: raw ?? "") ?? .finish
        loadCompletion()
        syncFromRemoteIfNeeded()
    }

    var sessions: [TrainingSessionItem] {
        switch selectedTemplate {
        case .finish:
            return [
                TrainingSessionItem(id: "finish_mon_easy", dayLabel: "Mon", title: "EASY RUN", detail: "会話できるペースで30分", targetKm: 5),
                TrainingSessionItem(id: "finish_wed_jog", dayLabel: "Wed", title: "JOG + DRILL", detail: "ドリルを含めたフォーム意識", targetKm: 6),
                TrainingSessionItem(id: "finish_sat_long", dayLabel: "Sat", title: "LONG RUN", detail: "疲れを残さない距離走", targetKm: 10)
            ]
        case .sub4:
            return [
                TrainingSessionItem(id: "sub4_tue_interval", dayLabel: "Tue", title: "INTERVAL", detail: "1km x 4本（R=2分）", targetKm: 8),
                TrainingSessionItem(id: "sub4_thu_tempo", dayLabel: "Thu", title: "TEMPO", detail: "20分テンポ走", targetKm: 10),
                TrainingSessionItem(id: "sub4_sun_long", dayLabel: "Sun", title: "LONG RUN", detail: "後半ビルドアップ", targetKm: 18)
            ]
        case .sub3:
            return [
                TrainingSessionItem(id: "sub3_tue_vo2", dayLabel: "Tue", title: "VO2MAX", detail: "1km x 6本（R=90秒）", targetKm: 12),
                TrainingSessionItem(id: "sub3_fri_threshold", dayLabel: "Fri", title: "THRESHOLD", detail: "8km閾値走", targetKm: 14),
                TrainingSessionItem(id: "sub3_sun_long", dayLabel: "Sun", title: "LONG RUN", detail: "30km距離走", targetKm: 30)
            ]
        }
    }

    var completionRate: Double {
        guard !sessions.isEmpty else { return 0 }
        let done = sessions.filter { completedSessionIDs.contains($0.id) }.count
        return Double(done) / Double(sessions.count)
    }

    func isCompleted(_ session: TrainingSessionItem) -> Bool {
        completedSessionIDs.contains(session.id)
    }

    func toggleCompletion(for session: TrainingSessionItem) {
        if completedSessionIDs.contains(session.id) {
            completedSessionIDs.remove(session.id)
        } else {
            completedSessionIDs.insert(session.id)
        }
        saveCompletion()
    }

    private func completionKey() -> String {
        let calendar = Calendar.current
        let week = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        return completedPrefix + "\(year)-\(week)"
    }

    private func loadCompletion() {
        let key = completionKey()
        let values = UserDefaults.standard.stringArray(forKey: key) ?? []
        completedSessionIDs = Set(values)
    }

    private func saveCompletion() {
        let key = completionKey()
        UserDefaults.standard.set(Array(completedSessionIDs), forKey: key)
        syncToRemoteIfPossible()
    }

    private func syncToRemoteIfPossible() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("training").document("current").setData([
            "template": selectedTemplate.rawValue,
            "completedSessionIDs": Array(completedSessionIDs),
            "updatedAt": Timestamp(date: Date())
        ], merge: true)
    }

    private func syncFromRemoteIfNeeded() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("training").document("current").getDocument { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data() else { return }
            DispatchQueue.main.async {
                if
                    let templateRaw = data["template"] as? String,
                    let template = TrainingPlanTemplate(rawValue: templateRaw)
                {
                    self.selectedTemplate = template
                }
                if let ids = data["completedSessionIDs"] as? [String] {
                    self.completedSessionIDs = Set(ids)
                    self.saveCompletion()
                }
            }
        }
    }
}

struct MonthlyChallenge: Identifiable {
    let id: String
    let title: String
    let description: String
    let target: Double
    let current: Double
    let unit: String
    let rewardPoints: Int

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(current / target, 1.0)
    }

    var isCompleted: Bool {
        current >= target
    }
}

struct ChallengeLeaderboardEntry: Identifiable {
    let id: String
    let name: String
    let score: Int
}

final class ChallengeService {
    static let shared = ChallengeService()
    private lazy var db = Firestore.firestore()
    private init() {}

    func currentMonthChallenges(from activities: [RunActivity]) -> [MonthlyChallenge] {
        let monthlyDistance = activities.reduce(0.0) { $0 + $1.distanceKm }
        let runCount = Double(activities.count)
        let bestRun = activities.map(\.distanceKm).max() ?? 0

        return [
            MonthlyChallenge(
                id: "challenge_monthly_distance_80",
                title: "Monthly 80K",
                description: "今月合計80kmを達成する",
                target: 80,
                current: monthlyDistance,
                unit: "km",
                rewardPoints: 300
            ),
            MonthlyChallenge(
                id: "challenge_monthly_runs_12",
                title: "Consistency 12",
                description: "今月12回走って継続力アップ",
                target: 12,
                current: runCount,
                unit: "回",
                rewardPoints: 250
            ),
            MonthlyChallenge(
                id: "challenge_long_run_15",
                title: "Long Run 15K",
                description: "単発で15km以上の走行を1回達成",
                target: 15,
                current: bestRun,
                unit: "km",
                rewardPoints: 220
            )
        ]
    }

    func awardPointsIfNeeded(challenges: [MonthlyChallenge]) {
        let monthKey = monthKeyString()
        let defaults = UserDefaults.standard
        for challenge in challenges where challenge.isCompleted {
            let key = "tasuki.challenge.rewarded.\(challenge.id).\(monthKey)"
            guard !defaults.bool(forKey: key) else { continue }
            PointService.shared.addPointsToCurrentUser(amount: challenge.rewardPoints)
            defaults.set(true, forKey: key)
            syncChallengeCompletionIfPossible(challenge: challenge, monthKey: monthKey)
            RealityMiningManager.shared.trackEvent(
                name: "challenge_completed",
                properties: [
                    "challenge_id": challenge.id,
                    "reward_points": challenge.rewardPoints
                ]
            )
        }
    }

    func leaderboard(monthlyDistanceKm: Double) -> [ChallengeLeaderboardEntry] {
        var list = [
            ChallengeLeaderboardEntry(id: "u_sora", name: "Sora", score: 1450),
            ChallengeLeaderboardEntry(id: "u_kenji", name: "Kenji", score: 1310),
            ChallengeLeaderboardEntry(id: "u_yuki", name: "Yuki", score: 1190)
        ]
        let myScore = Int(monthlyDistanceKm * 10) + PointService.shared.currentMonthlyPoints()
        let myName = UserDefaults.standard.string(forKey: "myName") ?? "You"
        list.append(ChallengeLeaderboardEntry(id: "me", name: myName, score: myScore))
        return list.sorted { $0.score > $1.score }
    }

    func fetchLeaderboard(monthlyDistanceKm: Double, completion: @escaping ([ChallengeLeaderboardEntry]) -> Void) {
        let fallback = leaderboard(monthlyDistanceKm: monthlyDistanceKm)
        guard Auth.auth().currentUser != nil else {
            completion(fallback)
            return
        }
        db.collection("users")
            .order(by: "monthlyPoints", descending: true)
            .limit(to: 20)
            .getDocuments { snapshot, _ in
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    completion(fallback)
                    return
                }
                let remote = docs.map { doc -> ChallengeLeaderboardEntry in
                    let data = doc.data()
                    let name = data["name"] as? String ?? "Runner"
                    let points = data["monthlyPoints"] as? Int ?? 0
                    return ChallengeLeaderboardEntry(id: doc.documentID, name: name, score: points)
                }
                completion(remote)
            }
    }

    private func monthKeyString() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyyMM"
        return df.string(from: Date())
    }

    private func syncChallengeCompletionIfPossible(challenge: MonthlyChallenge, monthKey: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users")
            .document(uid)
            .collection("challengeCompletions")
            .document("\(challenge.id)_\(monthKey)")
            .setData([
                "challengeId": challenge.id,
                "monthKey": monthKey,
                "rewardPoints": challenge.rewardPoints,
                "completedAt": Timestamp(date: Date())
            ], merge: true)
    }
}
