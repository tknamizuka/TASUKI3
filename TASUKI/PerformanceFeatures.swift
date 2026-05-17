import Foundation
import CoreLocation
import Combine
import FirebaseAuth
import FirebaseFirestore

extension Calendar {
    /// 週次アクティビティ（今週距離・回数・チャート・振り返り）の週境界。locale に依らず月曜始まりで統一する。
    static var tasukiActivityWeekCalendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday (1 = Sunday)
        return c
    }
}

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
    /// ユーザーが付けたアクティビティ名（任意）
    var title: String?
    /// 走行の感想メモ（任意）
    var note: String?
    /// 1〜5（主観のきつさ）。記録直後のアンケート任意。
    var perceivedEffort: Int?
    /// 1〜5（走後の気分）。記録直後のアンケート任意。
    var postRunMood: Int?
    /// 記録完了時に算出した詳細メトリクス（記録中UIには表示しない）
    var metrics: RunActivityMetrics?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        durationSeconds: TimeInterval,
        distanceKm: Double,
        route: [CodableCoordinate],
        source: String,
        title: String? = nil,
        note: String? = nil,
        perceivedEffort: Int? = nil,
        postRunMood: Int? = nil,
        metrics: RunActivityMetrics? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.route = route
        self.source = source
        self.title = title
        self.note = note
        self.perceivedEffort = perceivedEffort
        self.postRunMood = postRunMood
        self.metrics = metrics
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

    /// 取得元フィルタ（HealthKit を使わない「直接」経路で `RunActivity.source` と照合）
    func matchesRunningDataSource(_ dataSource: RunningDataSource) -> Bool {
        if dataSource == .all { return true }
        let s = source.lowercased()
        if s == dataSource.rawValue { return true }
        for kw in dataSource.sourceKeywords where !kw.isEmpty {
            if s.contains(kw.lowercased()) { return true }
        }
        return false
    }

    /// アプリ内の Run 記録フロー（`PostRunFlowViews` が `run_recorder` で保存）。
    var isFromTasukiRunRecorder: Bool { source == "run_recorder" }
}

struct RunActivityMetrics: Codable, Hashable {
    var totalDistanceKm: Double?
    var elapsedTimeSeconds: Double?
    var movingTimeSeconds: Double?
    var totalTimeSeconds: Double?
    var averagePaceSecondsPerKm: Double?
    var averageMovingPaceSecondsPerKm: Double?
    var gradeAdjustedPaceSecondsPerKm: Double?
    var bestPaceSecondsPerKm: Double?
    var averageSpeedKmh: Double?
    var maxSpeedKmh: Double?
    var lapSplits: [RunActivityLapSplit]
    var runningTimeSeconds: Double?
    var walkingTimeSeconds: Double?
    var restTimeSeconds: Double?
    var caloriesKcal: Int?
    var averageCadenceSpm: Double?
    var maxCadenceSpm: Double?
    var averageStrideLengthMeters: Double?
    var averageVerticalOscillationCm: Double?
    var averageVerticalRatioPercent: Double?
    var averageGroundContactTimeMs: Double?
    var totalAscentMeters: Double?
    var totalDescentMeters: Double?
    var minAltitudeMeters: Double?
    var maxAltitudeMeters: Double?
    var altitudeTrendMeters: [Double]?
    var weatherSummary: String?
    var temperatureCelsius: Double?
    var windDirection: String?
    var windSpeedMetersPerSecond: Double?
    var targetDistanceKm: Double?
    var targetDurationSeconds: Double?
    var targetDistanceProgress: Double?
    var targetDurationProgress: Double?

    init(
        totalDistanceKm: Double? = nil,
        elapsedTimeSeconds: Double? = nil,
        movingTimeSeconds: Double? = nil,
        totalTimeSeconds: Double? = nil,
        averagePaceSecondsPerKm: Double? = nil,
        averageMovingPaceSecondsPerKm: Double? = nil,
        gradeAdjustedPaceSecondsPerKm: Double? = nil,
        bestPaceSecondsPerKm: Double? = nil,
        averageSpeedKmh: Double? = nil,
        maxSpeedKmh: Double? = nil,
        lapSplits: [RunActivityLapSplit] = [],
        runningTimeSeconds: Double? = nil,
        walkingTimeSeconds: Double? = nil,
        restTimeSeconds: Double? = nil,
        caloriesKcal: Int? = nil,
        averageCadenceSpm: Double? = nil,
        maxCadenceSpm: Double? = nil,
        averageStrideLengthMeters: Double? = nil,
        averageVerticalOscillationCm: Double? = nil,
        averageVerticalRatioPercent: Double? = nil,
        averageGroundContactTimeMs: Double? = nil,
        totalAscentMeters: Double? = nil,
        totalDescentMeters: Double? = nil,
        minAltitudeMeters: Double? = nil,
        maxAltitudeMeters: Double? = nil,
        altitudeTrendMeters: [Double]? = nil,
        weatherSummary: String? = nil,
        temperatureCelsius: Double? = nil,
        windDirection: String? = nil,
        windSpeedMetersPerSecond: Double? = nil,
        targetDistanceKm: Double? = nil,
        targetDurationSeconds: Double? = nil,
        targetDistanceProgress: Double? = nil,
        targetDurationProgress: Double? = nil
    ) {
        self.totalDistanceKm = totalDistanceKm
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.movingTimeSeconds = movingTimeSeconds
        self.totalTimeSeconds = totalTimeSeconds
        self.averagePaceSecondsPerKm = averagePaceSecondsPerKm
        self.averageMovingPaceSecondsPerKm = averageMovingPaceSecondsPerKm
        self.gradeAdjustedPaceSecondsPerKm = gradeAdjustedPaceSecondsPerKm
        self.bestPaceSecondsPerKm = bestPaceSecondsPerKm
        self.averageSpeedKmh = averageSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.lapSplits = lapSplits
        self.runningTimeSeconds = runningTimeSeconds
        self.walkingTimeSeconds = walkingTimeSeconds
        self.restTimeSeconds = restTimeSeconds
        self.caloriesKcal = caloriesKcal
        self.averageCadenceSpm = averageCadenceSpm
        self.maxCadenceSpm = maxCadenceSpm
        self.averageStrideLengthMeters = averageStrideLengthMeters
        self.averageVerticalOscillationCm = averageVerticalOscillationCm
        self.averageVerticalRatioPercent = averageVerticalRatioPercent
        self.averageGroundContactTimeMs = averageGroundContactTimeMs
        self.totalAscentMeters = totalAscentMeters
        self.totalDescentMeters = totalDescentMeters
        self.minAltitudeMeters = minAltitudeMeters
        self.maxAltitudeMeters = maxAltitudeMeters
        self.altitudeTrendMeters = altitudeTrendMeters
        self.weatherSummary = weatherSummary
        self.temperatureCelsius = temperatureCelsius
        self.windDirection = windDirection
        self.windSpeedMetersPerSecond = windSpeedMetersPerSecond
        self.targetDistanceKm = targetDistanceKm
        self.targetDurationSeconds = targetDurationSeconds
        self.targetDistanceProgress = targetDistanceProgress
        self.targetDurationProgress = targetDurationProgress
    }
}

struct RunActivityLapSplit: Codable, Hashable {
    var index: Int
    var distanceKm: Double
    var durationSeconds: Double
    var paceSecondsPerKm: Double
}

/// 週次距離チャート用（`RunActivityStore.weeklyActivityChartPoints` · Me の Activity と Run 記録で同一描画に使う）。
struct WeeklyActivityChartPoint: Identifiable, Equatable {
    let id: String
    let weekAnchor: Date
    let label: String
    let distanceKm: Double

    init(weekAnchor: Date, label: String, distanceKm: Double, calendar: Calendar) {
        self.weekAnchor = weekAnchor
        self.label = label
        self.distanceKm = distanceKm
        let y = calendar.component(.yearForWeekOfYear, from: weekAnchor)
        let w = calendar.component(.weekOfYear, from: weekAnchor)
        self.id = "\(y)-w\(w)"
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
        endedAt: Date = Date(),
        title: String? = nil,
        note: String? = nil,
        perceivedEffort: Int? = nil,
        postRunMood: Int? = nil,
        metrics: RunActivityMetrics? = nil
    ) -> RunActivity {
        let sanitizedDistance = max(0, distanceKm)
        let sanitizedDuration = max(1, durationSeconds)
        let end = endedAt
        let startedAt = end.addingTimeInterval(-sanitizedDuration)
        let activity = RunActivity(
            startedAt: startedAt,
            endedAt: end,
            durationSeconds: sanitizedDuration,
            distanceKm: sanitizedDistance,
            route: routeCoordinates.map(CodableCoordinate.init),
            source: source,
            title: title,
            note: note,
            perceivedEffort: perceivedEffort,
            postRunMood: postRunMood,
            metrics: metrics
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

    func updateActivityTitleNote(id: UUID, title: String?, note: String?) {
        guard let idx = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[idx].title = title
        activities[idx].note = note
        save()
        uploadActivityIfPossible(activities[idx])
        RealityMiningManager.shared.trackEvent(
            name: "run_activity_metadata_updated",
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

    /// 外部デバイス取得元に紐づく今月距離（`source` がキーワードに一致する記録のみ）
    func monthlyDistanceKm(matching dataSource: RunningDataSource, now: Date = Date()) -> Double {
        activitiesInCurrentMonth(now: now)
            .filter { $0.matchesRunningDataSource(dataSource) }
            .reduce(0) { $0 + $1.distanceKm }
    }

    /// タイムトライアル等用。HealthKit 経由せず TASUKI 保存済みの `RunActivity` から `RunningWorkoutInfo` を組み立てる。
    func runningWorkoutInfos(
        from start: Date,
        to end: Date,
        minDistanceKm: Double,
        targetDistanceKm: Double,
        dataSource: RunningDataSource
    ) -> [RunningWorkoutInfo] {
        let minMeters = minDistanceKm * 1000
        let filtered = activities.filter { act in
            act.startedAt >= start && act.startedAt <= end
                && act.matchesRunningDataSource(dataSource)
                && act.distanceKm * 1000 >= minMeters - 0.5
        }
        .sorted { $0.startedAt > $1.startedAt }

        return filtered.map { act in
            let timeAtTarget: Double?
            if targetDistanceKm > 0, act.distanceKm + 1e-6 >= targetDistanceKm {
                let ratio = targetDistanceKm / max(act.distanceKm, 1e-6)
                timeAtTarget = act.durationSeconds * min(1.0, ratio)
            } else {
                timeAtTarget = nil
            }
            return RunningWorkoutInfo(
                id: act.id,
                startDate: act.startedAt,
                durationSeconds: act.durationSeconds,
                totalDistanceKm: act.distanceKm,
                timeAtTargetSeconds: timeAtTarget
            )
        }
    }

    func monthlyRunCount(now: Date = Date()) -> Int {
        activitiesInCurrentMonth(now: now).count
    }

    func activitiesInCurrentMonth(matching dataSource: RunningDataSource, now: Date = Date()) -> [RunActivity] {
        activitiesInCurrentMonth(now: now).filter { $0.matchesRunningDataSource(dataSource) }
    }

    func monthlyRunCount(matching dataSource: RunningDataSource, now: Date = Date()) -> Int {
        activitiesInCurrentMonth(matching: dataSource, now: now).count
    }

    /// 今月の記録から加重平均ペース（秒/km）。取得元で絞り込み。
    func monthlyAveragePaceSecondsPerKm(matching dataSource: RunningDataSource, now: Date = Date()) -> Double? {
        let acts = activitiesInCurrentMonth(matching: dataSource, now: now)
        var totalDist = 0.0
        var totalDur = 0.0
        for a in acts {
            totalDist += max(0, a.distanceKm)
            totalDur += max(0, a.durationSeconds)
        }
        guard totalDist > 0.01 else { return nil }
        return totalDur / totalDist
    }

    /// 今月のルート座標の重心（マッチング用）。取得元で絞り込み。
    func monthlyRouteCentroid(matching dataSource: RunningDataSource, now: Date = Date()) -> (latitude: Double, longitude: Double)? {
        let acts = activitiesInCurrentMonth(matching: dataSource, now: now)
        var sumLat = 0.0
        var sumLon = 0.0
        var n = 0
        for a in acts {
            for c in a.route {
                sumLat += c.latitude
                sumLon += c.longitude
                n += 1
            }
        }
        guard n > 0 else { return nil }
        return (sumLat / Double(n), sumLon / Double(n))
    }

    /// 今月の記録から加重平均ペース（秒/km）。有効な記録がない場合は nil（暦月で区切られ、毎月リセットされる）。
    func monthlyAveragePaceSecondsPerKm(now: Date = Date()) -> Double? {
        let acts = activitiesInCurrentMonth(now: now)
        var totalDist = 0.0
        var totalDur = 0.0
        for a in acts {
            totalDist += max(0, a.distanceKm)
            totalDur += max(0, a.durationSeconds)
        }
        guard totalDist > 0.01 else { return nil }
        return totalDur / totalDist
    }

    /// 今月の平均ペース表示用（`--:--/km` は記録なし）。
    func monthlyAveragePaceDisplayLabel(now: Date = Date()) -> String {
        guard let sec = monthlyAveragePaceSecondsPerKm(now: now) else { return "--:--/km" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d/km", m, s)
    }

    /// 今月のルート座標の重心（マッチング用）。ルート点がない場合は nil。
    func monthlyRouteCentroid(now: Date = Date()) -> (latitude: Double, longitude: Double)? {
        let acts = activitiesInCurrentMonth(now: now)
        var sumLat = 0.0
        var sumLon = 0.0
        var n = 0
        for a in acts {
            for c in a.route {
                sumLat += c.latitude
                sumLon += c.longitude
                n += 1
            }
        }
        guard n > 0 else { return nil }
        return (sumLat / Double(n), sumLon / Double(n))
    }

    /// 今週（`calendar` の `weekOfYear`）に含まれる走行。Me / Run の Activity と「今週の振り返り」で同一データを参照する。
    func activitiesInCurrentWeek(now: Date = Date(), calendar: Calendar = .tasukiActivityWeekCalendar) -> [RunActivity] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return activities.filter { weekInterval.contains($0.startedAt) }
    }

    func weeklyDistanceKm(now: Date = Date(), calendar: Calendar = .tasukiActivityWeekCalendar) -> Double {
        activitiesInCurrentWeek(now: now, calendar: calendar).reduce(0) { $0 + $1.distanceKm }
    }

    func weeklyRunCount(now: Date = Date(), calendar: Calendar = .tasukiActivityWeekCalendar) -> Int {
        activitiesInCurrentWeek(now: now, calendar: calendar).count
    }

    // MARK: - TASUKI Run 記録（`run_recorder`）集計 · My Profile など

    func tasukiRecorderActivities() -> [RunActivity] {
        activities.filter(\.isFromTasukiRunRecorder)
    }

    func tasukiRecorderActivitiesInCurrentMonth(now: Date = Date()) -> [RunActivity] {
        activitiesInCurrentMonth(now: now).filter(\.isFromTasukiRunRecorder)
    }

    func tasukiRecorderMonthlyRunCount(now: Date = Date()) -> Int {
        tasukiRecorderActivitiesInCurrentMonth(now: now).count
    }

    func tasukiRecorderMonthlyDistanceKm(now: Date = Date()) -> Double {
        tasukiRecorderActivitiesInCurrentMonth(now: now).reduce(0) { $0 + $1.distanceKm }
    }

    func tasukiRecorderAllTimeRunCount() -> Int {
        tasukiRecorderActivities().count
    }

    func tasukiRecorderAllTimeDistanceKm() -> Double {
        tasukiRecorderActivities().reduce(0) { $0 + $1.distanceKm }
    }

    func tasukiRecorderMonthlyAveragePaceDisplayLabel(now: Date = Date()) -> String {
        let acts = tasukiRecorderActivitiesInCurrentMonth(now: now)
        var totalDist = 0.0
        var totalDur = 0.0
        for a in acts {
            totalDist += max(0, a.distanceKm)
            totalDur += max(0, a.durationSeconds)
        }
        guard totalDist > 0.01 else { return "--:--/km" }
        let sec = totalDur / totalDist
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d/km", m, s)
    }

    func tasukiRecorderMonthlyAverageMovingPaceDisplayLabel(now: Date = Date()) -> String {
        tasukiRecorderPaceDisplay(
            weightedSecondsPerKm: distanceWeightedRecorderMetric(now: now) { $0.averageMovingPaceSecondsPerKm }
        )
    }

    func tasukiRecorderMonthlyGapPaceDisplayLabel(now: Date = Date()) -> String {
        tasukiRecorderPaceDisplay(
            weightedSecondsPerKm: distanceWeightedRecorderMetric(now: now) { $0.gradeAdjustedPaceSecondsPerKm }
        )
    }

    func tasukiRecorderMonthlyAverageCadenceDisplayLabel(now: Date = Date()) -> String {
        guard let v = distanceWeightedRecorderMetric(now: now) { $0.averageCadenceSpm }, v > 0 else { return "-- spm" }
        return String(format: "%.0f spm", v)
    }

    func tasukiRecorderMonthlyMaxCadenceDisplayLabel(now: Date = Date()) -> String {
        let acts = tasukiRecorderActivitiesInCurrentMonth(now: now)
        guard let maxV = acts.compactMap(\.metrics?.maxCadenceSpm).filter({ $0 > 0 }).max() else { return "-- spm" }
        return String(format: "%.0f spm", maxV)
    }

    func tasukiRecorderMonthlyTotalAscentDisplayLabel(now: Date = Date()) -> String {
        let sum = tasukiRecorderActivitiesInCurrentMonth(now: now)
            .compactMap(\.metrics?.totalAscentMeters)
            .filter { $0 > 0 }
            .reduce(0.0, +)
        guard sum > 0.5 else { return "-- m" }
        return String(format: "%.0f m", sum)
    }

    func tasukiRecorderMonthlyTotalCaloriesDisplayLabel(now: Date = Date()) -> String {
        let sum = tasukiRecorderActivitiesInCurrentMonth(now: now)
            .compactMap(\.metrics?.caloriesKcal)
            .filter { $0 > 0 }
            .reduce(0, +)
        guard sum > 0 else { return "-- kcal" }
        return "\(sum) kcal"
    }

    func tasukiRecorderMonthlyAverageStrideDisplayLabel(now: Date = Date()) -> String {
        guard let v = distanceWeightedRecorderMetric(now: now) { $0.averageStrideLengthMeters }, v > 0 else { return "-- m" }
        return String(format: "%.2f m", v)
    }

    func tasukiRecorderMonthlyAverageSpeedDisplayLabel(now: Date = Date()) -> String {
        guard let v = distanceWeightedRecorderMetric(now: now) { $0.averageSpeedKmh }, v > 0 else { return "-- km/h" }
        return String(format: "%.1f km/h", v)
    }

    private func distanceWeightedRecorderMetric(
        now: Date,
        pick: (RunActivityMetrics) -> Double?
    ) -> Double? {
        let acts = tasukiRecorderActivitiesInCurrentMonth(now: now)
        var sumW = 0.0
        var sumV = 0.0
        for a in acts {
            guard let m = a.metrics else { continue }
            guard let raw = pick(m), raw.isFinite, raw > 0 else { continue }
            let w = max(0.01, a.distanceKm)
            sumW += w
            sumV += raw * w
        }
        guard sumW > 0.01 else { return nil }
        return sumV / sumW
    }

    private func tasukiRecorderPaceDisplay(weightedSecondsPerKm: Double?) -> String {
        guard let sec = weightedSecondsPerKm, sec.isFinite, sec > 0 else { return "--:--/km" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return String(format: "%d:%02d/km", m, s)
    }

    /// 直近 `weeks` 週の週次走行距離（右端が今週）。実データがすべて 0 のときのみデモ用フォールバック。
    func weeklyActivityChartPoints(
        weeks: Int = 8,
        now: Date = Date(),
        calendar: Calendar = .tasukiActivityWeekCalendar
    ) -> [WeeklyActivityChartPoint] {
        let real = weeklyChartRows(weeks: weeks, now: now, calendar: calendar)
        if real.contains(where: { $0.distanceKm > 0 }) {
            return real
        }
        let fallbackValues: [Double] = [12.0, 18.5, 10.2, 21.3, 16.4, 22.1, 19.8, 24.0]
        return (0..<weeks).map { idx in
            let offset = idx - (weeks - 1)
            let weekAnchor = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            let normalizedAnchor = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)?.start ?? weekAnchor
            let value = idx < fallbackValues.count ? fallbackValues[idx] : (fallbackValues.last ?? 0)
            let label = Self.shortWeekChartLabel(for: normalizedAnchor, calendar: calendar)
            return WeeklyActivityChartPoint(weekAnchor: normalizedAnchor, label: label, distanceKm: value, calendar: calendar)
        }
    }

    private func weeklyChartRows(weeks: Int, now: Date, calendar: Calendar) -> [WeeklyActivityChartPoint] {
        (0..<weeks).map { idx in
            let offset = idx - (weeks - 1)
            let targetDate = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: targetDate) else {
                return WeeklyActivityChartPoint(
                    weekAnchor: targetDate,
                    label: Self.shortWeekChartLabel(for: targetDate, calendar: calendar),
                    distanceKm: 0,
                    calendar: calendar
                )
            }
            let distance = activities
                .filter { interval.contains($0.startedAt) }
                .reduce(0) { $0 + $1.distanceKm }
            return WeeklyActivityChartPoint(
                weekAnchor: interval.start,
                label: Self.shortWeekChartLabel(for: interval.start, calendar: calendar),
                distanceKm: distance,
                calendar: calendar
            )
        }
    }

    private static func shortWeekChartLabel(for date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            activities = []
            return
        }
        do {
            activities = try JSONDecoder().decode([RunActivity].self, from: data)
                .map { withBackfilledMetricsIfNeeded($0) }
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
        if let t = activity.title, !t.isEmpty { payload["title"] = t }
        if let n = activity.note, !n.isEmpty { payload["note"] = n }
        if let e = activity.perceivedEffort { payload["perceivedEffort"] = e }
        if let m = activity.postRunMood { payload["postRunMood"] = m }
        if let metrics = activity.metrics {
            payload["metrics"] = firestorePayload(from: metrics)
        }
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
                    let title = data["title"] as? String
                    let note = data["note"] as? String
                    let perceivedEffort = data["perceivedEffort"] as? Int
                    let postRunMood = data["postRunMood"] as? Int
                    let metrics = self.parseMetrics(from: data["metrics"])
                    return RunActivity(
                        id: id,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        durationSeconds: durationSeconds,
                        distanceKm: distanceKm,
                        route: route,
                        source: source,
                        title: title,
                        note: note,
                        perceivedEffort: perceivedEffort,
                        postRunMood: postRunMood,
                        metrics: metrics
                    )
                }
                if remote.isEmpty { return }
                DispatchQueue.main.async {
                    var mergedById: [UUID: RunActivity] = Dictionary(uniqueKeysWithValues: self.activities.map { ($0.id, $0) })
                    for item in remote {
                        if let local = mergedById[item.id], item.metrics == nil {
                            var merged = item
                            merged.metrics = local.metrics
                            mergedById[item.id] = self.withBackfilledMetricsIfNeeded(merged)
                        } else {
                            mergedById[item.id] = self.withBackfilledMetricsIfNeeded(item)
                        }
                    }
                    self.activities = mergedById.values
                        .map { self.withBackfilledMetricsIfNeeded($0) }
                        .sorted { $0.startedAt > $1.startedAt }
                    if self.activities.count > self.maxStoredCount {
                        self.activities = Array(self.activities.prefix(self.maxStoredCount))
                    }
                    self.save()
                }
            }
    }

    private func firestorePayload(from metrics: RunActivityMetrics) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let v = metrics.totalDistanceKm { payload["totalDistanceKm"] = v }
        if let v = metrics.elapsedTimeSeconds { payload["elapsedTimeSeconds"] = v }
        if let v = metrics.movingTimeSeconds { payload["movingTimeSeconds"] = v }
        if let v = metrics.totalTimeSeconds { payload["totalTimeSeconds"] = v }
        if let v = metrics.averagePaceSecondsPerKm { payload["averagePaceSecondsPerKm"] = v }
        if let v = metrics.averageMovingPaceSecondsPerKm { payload["averageMovingPaceSecondsPerKm"] = v }
        if let v = metrics.gradeAdjustedPaceSecondsPerKm { payload["gradeAdjustedPaceSecondsPerKm"] = v }
        if let v = metrics.bestPaceSecondsPerKm { payload["bestPaceSecondsPerKm"] = v }
        if let v = metrics.averageSpeedKmh { payload["averageSpeedKmh"] = v }
        if let v = metrics.maxSpeedKmh { payload["maxSpeedKmh"] = v }
        if !metrics.lapSplits.isEmpty {
            payload["lapSplits"] = metrics.lapSplits.map {
                [
                    "index": $0.index,
                    "distanceKm": $0.distanceKm,
                    "durationSeconds": $0.durationSeconds,
                    "paceSecondsPerKm": $0.paceSecondsPerKm
                ]
            }
        }
        if let v = metrics.runningTimeSeconds { payload["runningTimeSeconds"] = v }
        if let v = metrics.walkingTimeSeconds { payload["walkingTimeSeconds"] = v }
        if let v = metrics.restTimeSeconds { payload["restTimeSeconds"] = v }
        if let v = metrics.caloriesKcal { payload["caloriesKcal"] = v }
        if let v = metrics.averageCadenceSpm { payload["averageCadenceSpm"] = v }
        if let v = metrics.maxCadenceSpm { payload["maxCadenceSpm"] = v }
        if let v = metrics.averageStrideLengthMeters { payload["averageStrideLengthMeters"] = v }
        if let v = metrics.averageVerticalOscillationCm { payload["averageVerticalOscillationCm"] = v }
        if let v = metrics.averageVerticalRatioPercent { payload["averageVerticalRatioPercent"] = v }
        if let v = metrics.averageGroundContactTimeMs { payload["averageGroundContactTimeMs"] = v }
        if let v = metrics.totalAscentMeters { payload["totalAscentMeters"] = v }
        if let v = metrics.totalDescentMeters { payload["totalDescentMeters"] = v }
        if let v = metrics.minAltitudeMeters { payload["minAltitudeMeters"] = v }
        if let v = metrics.maxAltitudeMeters { payload["maxAltitudeMeters"] = v }
        if let v = metrics.altitudeTrendMeters { payload["altitudeTrendMeters"] = v }
        if let v = metrics.weatherSummary, !v.isEmpty { payload["weatherSummary"] = v }
        if let v = metrics.temperatureCelsius { payload["temperatureCelsius"] = v }
        if let v = metrics.windDirection, !v.isEmpty { payload["windDirection"] = v }
        if let v = metrics.windSpeedMetersPerSecond { payload["windSpeedMetersPerSecond"] = v }
        if let v = metrics.targetDistanceKm { payload["targetDistanceKm"] = v }
        if let v = metrics.targetDurationSeconds { payload["targetDurationSeconds"] = v }
        if let v = metrics.targetDistanceProgress { payload["targetDistanceProgress"] = v }
        if let v = metrics.targetDurationProgress { payload["targetDurationProgress"] = v }
        return payload
    }

    private func parseMetrics(from raw: Any?) -> RunActivityMetrics? {
        guard let map = raw as? [String: Any] else { return nil }
        let lapsRaw = map["lapSplits"] as? [[String: Any]] ?? []
        let lapSplits = lapsRaw.compactMap { item -> RunActivityLapSplit? in
            let idx = self.intFromAny(item["index"])
            let distance = self.doubleFromAny(item["distanceKm"])
            let duration = self.doubleFromAny(item["durationSeconds"])
            let pace = self.doubleFromAny(item["paceSecondsPerKm"])
            guard idx > 0, distance > 0, duration > 0, pace > 0 else { return nil }
            return RunActivityLapSplit(index: idx, distanceKm: distance, durationSeconds: duration, paceSecondsPerKm: pace)
        }
        return RunActivityMetrics(
            totalDistanceKm: optionalDoubleFromAny(map["totalDistanceKm"]),
            elapsedTimeSeconds: optionalDoubleFromAny(map["elapsedTimeSeconds"]),
            movingTimeSeconds: optionalDoubleFromAny(map["movingTimeSeconds"]),
            totalTimeSeconds: optionalDoubleFromAny(map["totalTimeSeconds"]),
            averagePaceSecondsPerKm: optionalDoubleFromAny(map["averagePaceSecondsPerKm"]),
            averageMovingPaceSecondsPerKm: optionalDoubleFromAny(map["averageMovingPaceSecondsPerKm"]),
            gradeAdjustedPaceSecondsPerKm: optionalDoubleFromAny(map["gradeAdjustedPaceSecondsPerKm"]),
            bestPaceSecondsPerKm: optionalDoubleFromAny(map["bestPaceSecondsPerKm"]),
            averageSpeedKmh: optionalDoubleFromAny(map["averageSpeedKmh"]),
            maxSpeedKmh: optionalDoubleFromAny(map["maxSpeedKmh"]),
            lapSplits: lapSplits,
            runningTimeSeconds: optionalDoubleFromAny(map["runningTimeSeconds"]),
            walkingTimeSeconds: optionalDoubleFromAny(map["walkingTimeSeconds"]),
            restTimeSeconds: optionalDoubleFromAny(map["restTimeSeconds"]),
            caloriesKcal: optionalIntFromAny(map["caloriesKcal"]),
            averageCadenceSpm: optionalDoubleFromAny(map["averageCadenceSpm"]),
            maxCadenceSpm: optionalDoubleFromAny(map["maxCadenceSpm"]),
            averageStrideLengthMeters: optionalDoubleFromAny(map["averageStrideLengthMeters"]),
            averageVerticalOscillationCm: optionalDoubleFromAny(map["averageVerticalOscillationCm"]),
            averageVerticalRatioPercent: optionalDoubleFromAny(map["averageVerticalRatioPercent"]),
            averageGroundContactTimeMs: optionalDoubleFromAny(map["averageGroundContactTimeMs"]),
            totalAscentMeters: optionalDoubleFromAny(map["totalAscentMeters"]),
            totalDescentMeters: optionalDoubleFromAny(map["totalDescentMeters"]),
            minAltitudeMeters: optionalDoubleFromAny(map["minAltitudeMeters"]),
            maxAltitudeMeters: optionalDoubleFromAny(map["maxAltitudeMeters"]),
            altitudeTrendMeters: map["altitudeTrendMeters"] as? [Double],
            weatherSummary: map["weatherSummary"] as? String,
            temperatureCelsius: optionalDoubleFromAny(map["temperatureCelsius"]),
            windDirection: map["windDirection"] as? String,
            windSpeedMetersPerSecond: optionalDoubleFromAny(map["windSpeedMetersPerSecond"]),
            targetDistanceKm: optionalDoubleFromAny(map["targetDistanceKm"]),
            targetDurationSeconds: optionalDoubleFromAny(map["targetDurationSeconds"]),
            targetDistanceProgress: optionalDoubleFromAny(map["targetDistanceProgress"]),
            targetDurationProgress: optionalDoubleFromAny(map["targetDurationProgress"])
        )
    }

    private func withBackfilledMetricsIfNeeded(_ activity: RunActivity) -> RunActivity {
        var updated = activity
        updated.metrics = mergedMetricsWithBackfill(existing: activity.metrics, activity: activity)
        return updated
    }

    private func mergedMetricsWithBackfill(existing: RunActivityMetrics?, activity: RunActivity) -> RunActivityMetrics? {
        let distanceKm = max(0, activity.distanceKm)
        let duration = max(1, activity.durationSeconds)
        let pace = distanceKm > 0 ? duration / distanceKm : nil
        let speed = duration > 0 ? distanceKm / (duration / 3600.0) : nil
        let estimatedCalories = Int((distanceKm * 65.0 * 1.036).rounded())

        var merged = existing ?? RunActivityMetrics()
        if merged.totalDistanceKm == nil { merged.totalDistanceKm = distanceKm }
        if merged.elapsedTimeSeconds == nil { merged.elapsedTimeSeconds = duration }
        if merged.movingTimeSeconds == nil { merged.movingTimeSeconds = duration }
        if merged.totalTimeSeconds == nil { merged.totalTimeSeconds = duration }
        if merged.averagePaceSecondsPerKm == nil { merged.averagePaceSecondsPerKm = pace }
        if merged.averageMovingPaceSecondsPerKm == nil { merged.averageMovingPaceSecondsPerKm = pace }
        if merged.averageSpeedKmh == nil { merged.averageSpeedKmh = speed }
        if merged.caloriesKcal == nil, estimatedCalories > 0 { merged.caloriesKcal = estimatedCalories }

        if merged.targetDistanceProgress == nil, let target = merged.targetDistanceKm, target > 0 {
            merged.targetDistanceProgress = min(max(distanceKm / target, 0), 1)
        }
        if merged.targetDurationProgress == nil, let target = merged.targetDurationSeconds, target > 0 {
            merged.targetDurationProgress = min(max(duration / target, 0), 1)
        }

        return merged
    }

    private func intFromAny(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return 0
    }

    private func doubleFromAny(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return 0
    }

    private func optionalDoubleFromAny(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private func optionalIntFromAny(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
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
        let calendar = Calendar.tasukiActivityWeekCalendar
        let now = Date()
        let week = calendar.component(.weekOfYear, from: now)
        let year = calendar.component(.yearForWeekOfYear, from: now)
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
            PointService.shared.addPointsToCurrentUser(
                amount: challenge.rewardPoints,
                actionId: "challenge:\(challenge.id):\(monthKey)"
            )
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
        db.collection("public_profiles")
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
