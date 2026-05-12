import Foundation
import HealthKit
import CoreLocation
import FirebaseFirestore

/// ランニングデータ取得元
enum RunningDataSource: String, CaseIterable, Identifiable {
    case all = "all"
    case appleHealth = "apple_health"
    case garmin = "garmin"
    case suunto = "suunto"
    case fitbit = "fitbit"
    case polar = "polar"
    case coros = "coros"
    case amazfit = "amazfit"
    case runkeeper = "runkeeper"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "すべて"
        case .appleHealth: return "Apple Health"
        case .garmin: return "Garmin"
        case .suunto: return "Suunto"
        case .fitbit: return "Fitbit"
        case .polar: return "Polar"
        case .coros: return "COROS"
        case .amazfit: return "Amazfit"
        case .runkeeper: return "Runkeeper"
        }
    }

    var sourceKeywords: [String] {
        switch self {
        case .all:
            return []
        case .appleHealth:
            return ["apple", "health", "workout"]
        case .garmin:
            return ["garmin", "connect"]
        case .suunto:
            return ["suunto"]
        case .fitbit:
            return ["fitbit"]
        case .polar:
            return ["polar", "flow"]
        case .coros:
            return ["coros"]
        case .amazfit:
            return ["amazfit", "zepp"]
        case .runkeeper:
            return ["runkeeper", "asics"]
        }
    }

    var deepLinks: [URL] {
        switch self {
        case .all:
            return []
        case .appleHealth:
            return [URL(string: "x-apple-health://")].compactMap { $0 }
        case .garmin:
            return [URL(string: "garminconnect://")].compactMap { $0 }
        case .suunto:
            return [URL(string: "suuntoapp://")].compactMap { $0 }
        case .fitbit:
            return [URL(string: "fitbit://")].compactMap { $0 }
        case .polar:
            return [URL(string: "polarflow://"), URL(string: "polar://")].compactMap { $0 }
        case .coros:
            return [URL(string: "coros://")].compactMap { $0 }
        case .amazfit:
            return [URL(string: "zepp://"), URL(string: "amazfit://")].compactMap { $0 }
        case .runkeeper:
            return [URL(string: "runkeeper://")].compactMap { $0 }
        }
    }

    var appStoreURL: URL? {
        switch self {
        case .all:
            return nil
        case .appleHealth:
            return nil
        case .garmin:
            return URL(string: "https://apps.apple.com/jp/app/garmin-connect-mobile/id583446403")
        case .suunto:
            return URL(string: "https://apps.apple.com/jp/app/suunto/id1187259981")
        case .fitbit:
            return URL(string: "https://apps.apple.com/jp/app/fitbit/id462638897")
        case .polar:
            return URL(string: "https://apps.apple.com/jp/app/polar-flow/id717172678")
        case .coros:
            return URL(string: "https://apps.apple.com/jp/app/coros/id1329207236")
        case .amazfit:
            return URL(string: "https://apps.apple.com/jp/app/zepp/id1278618190")
        case .runkeeper:
            return URL(string: "https://apps.apple.com/jp/app/asics-runkeeper-run-tracker/id300235330")
        }
    }
}

/// 期間内のランニングワークアウト1件（HealthKit `HKWorkout` 由来。メーカーが書き込んだメタデータを可能な範囲で保持）
struct RunningWorkoutInfo: Identifiable {
    let id: UUID
    let startDate: Date
    /// HealthKit のワークアウト終了日時（壁時計）。`durationSeconds` と一致しない場合はポーズ等で差が出ている可能性あり。
    let endDate: Date
    /// `HKWorkout.duration`（メーカー定義の活動時間）
    let durationSeconds: Double
    /// `endDate - startDate`（セッションの壁時計の長さ）
    let wallClockDurationSeconds: Double
    let totalDistanceKm: Double
    /// ルートから算出した「目標距離通過時点のタイム」（秒）。nil の場合はルートなし
    let timeAtTargetSeconds: Double?
    /// `HKWorkout.totalDistance` があればメートル
    let totalDistanceFromWorkoutMeters: Double?
    let totalEnergyBurnedKcal: Double?
    let averageHeartRateBpm: Double?
    let minHeartRateBpm: Double?
    let maxHeartRateBpm: Double?
    /// ワークアウト統計の平均ランニング速度 (m/s)
    let averageRunningSpeedMps: Double?
    /// ワークアウト統計の上昇量 (m)
    let elevationAscendedMeters: Double?
    let sourceName: String
    let sourceBundleIdentifier: String?
    let deviceManufacturer: String?
    let deviceModel: String?
    let deviceHardwareVersion: String?
    let deviceSoftwareVersion: String?
    let udiDeviceIdentifier: String?
    let workoutActivityTypeRaw: Int
    /// `HKWorkout.metadata` を文字列化したもの（メーカー拡張用）
    let metadata: [String: String]

    var timeAtTargetFormatted: String? {
        guard let sec = timeAtTargetSeconds else { return nil }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return String(format: "%d:%02d:%02d", h, mm, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    var durationFormatted: String { Self.formatHMS(durationSeconds) }

    var wallClockDurationFormatted: String { Self.formatHMS(wallClockDurationSeconds) }

    private static func formatHMS(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return String(format: "%d:%02d:%02d", h, mm, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// 提出に使うタイム（秒）。ルートから算出があればそれ、なければ全体タイムは呼び出し側で距離範囲チェック後に使用
    var submitTimeSeconds: Double? { timeAtTargetSeconds ?? (durationSeconds > 0 ? durationSeconds : nil) }

    /// 駅伝 `submissions` 等にマージする HealthKit 詳細（Firestore 互換）
    func firestoreHealthKitPayload() -> [String: Any] {
        var d: [String: Any] = [
            "hkWorkoutUuid": id.uuidString,
            "hkStartAt": Timestamp(date: startDate),
            "hkEndAt": Timestamp(date: endDate),
            "hkActiveDurationSec": durationSeconds,
            "hkWallClockDurationSec": wallClockDurationSeconds,
            "hkTotalDistanceKm": totalDistanceKm,
            "hkSourceName": sourceName,
            "hkActivityType": workoutActivityTypeRaw
        ]
        if let b = sourceBundleIdentifier { d["hkSourceBundleId"] = b }
        if let v = totalDistanceFromWorkoutMeters { d["hkTotalDistanceWorkoutM"] = v }
        if let v = totalEnergyBurnedKcal { d["hkEnergyKcal"] = v }
        if let v = averageHeartRateBpm { d["hkHeartAvgBpm"] = v }
        if let v = minHeartRateBpm { d["hkHeartMinBpm"] = v }
        if let v = maxHeartRateBpm { d["hkHeartMaxBpm"] = v }
        if let v = averageRunningSpeedMps { d["hkAvgRunningSpeedMps"] = v }
        if let v = elevationAscendedMeters { d["hkElevationAscendedM"] = v }
        if let v = deviceManufacturer { d["hkDeviceManufacturer"] = v }
        if let v = deviceModel { d["hkDeviceModel"] = v }
        if let v = deviceHardwareVersion { d["hkDeviceHardwareVersion"] = v }
        if let v = deviceSoftwareVersion { d["hkDeviceSoftwareVersion"] = v }
        if let v = udiDeviceIdentifier { d["hkUdiDeviceIdentifier"] = v }
        if !metadata.isEmpty { d["hkMetadata"] = metadata }
        if let t = timeAtTargetSeconds { d["hkTimeAtTargetSec"] = t }
        return d
    }
}

/// HealthKit との連携を担当するマネージャ
final class HealthKitManager {
    
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    
    private init() {}
    
    /// HealthKit からウォーキング＋ランニング距離・ワークアウト・ルートを読み取るための権限をリクエストする
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "HealthKit", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "HealthKit is not available on this device."
            ]))
            return
        }
        
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            completion(false, NSError(domain: "HealthKit", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "distanceWalkingRunning type is not available."
            ]))
            return
        }
        
        var readTypes: Set<HKObjectType> = [distanceType]
        readTypes.insert(HKObjectType.workoutType())
        readTypes.insert(HKSeriesType.workoutRoute())
        if let hr = HKObjectType.quantityType(forIdentifier: .heartRate) { readTypes.insert(hr) }
        if let sp = HKObjectType.quantityType(forIdentifier: .runningSpeed) { readTypes.insert(sp) }
        if let ae = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { readTypes.insert(ae) }
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    RealityMiningManager.shared.trackEvent(
                        name: "healthkit_auth_result",
                        properties: [
                            "success": success,
                            "error_message": error.localizedDescription
                        ]
                    )
                } else {
                    RealityMiningManager.shared.trackEvent(
                        name: "healthkit_auth_result",
                        properties: ["success": success]
                    )
                }
                completion(success, error)
            }
        }
    }
    
    /// 当月のウォーキング＋ランニング距離 (km) を取得する
    func fetchRunningDistanceThisMonth(dataSource: RunningDataSource = .all, completion: @escaping (Result<Double, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            let error = NSError(domain: "HealthKit", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "HealthKit is not available on this device."
            ])
            completion(.failure(error))
            return
        }
        
        guard let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            let error = NSError(domain: "HealthKit", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "distanceWalkingRunning type is not available."
            ])
            completion(.failure(error))
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            let error = NSError(domain: "HealthKit", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to calculate start of month."
            ])
            completion(.failure(error))
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfMonth, end: now, options: .strictStartDate)

        predicateForDataSource(sampleType: distanceType, basePredicate: predicate, dataSource: dataSource) { [weak self] sourcePredicate in
            guard let self = self else { return }
            let finalPredicate: NSPredicate
            if let sourcePredicate = sourcePredicate {
                finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, sourcePredicate])
            } else {
                finalPredicate = predicate
            }

            let query = HKStatisticsQuery(quantityType: distanceType,
                                          quantitySamplePredicate: finalPredicate,
                                          options: .cumulativeSum) { _, result, error in
                if let error = error {
                    DispatchQueue.main.async {
                        RealityMiningManager.shared.trackEvent(
                            name: "healthkit_fetch_failure",
                            properties: [
                                "fetch_type": "monthly_distance",
                                "data_source": dataSource.rawValue,
                                "error_message": error.localizedDescription
                            ]
                        )
                        completion(.failure(error))
                    }
                    return
                }

                guard let sumQuantity = result?.sumQuantity() else {
                    // データがない場合は 0km とする
                    DispatchQueue.main.async {
                        completion(.success(0.0))
                    }
                    return
                }

                let meters = sumQuantity.doubleValue(for: HKUnit.meter())
                let kilometers = meters / 1000.0

                DispatchQueue.main.async {
                    RealityMiningManager.shared.trackEvent(
                        name: "healthkit_fetch_success",
                        properties: [
                            "fetch_type": "monthly_distance",
                            "data_source": dataSource.rawValue,
                            "distance_km": kilometers
                        ]
                    )
                    completion(.success(kilometers))
                }
            }

            self.healthStore.execute(query)
        }
    }
    
    // MARK: - ワークアウト・ルート（タイムトライアル用）
    
    /// 指定ワークアウトのルートから「目標距離（m）通過時点のタイム」を算出。ルートが無い or 距離未達なら failure
    func timeAtDistance(workout: HKWorkout, targetMeters: Double, completion: @escaping (Result<TimeInterval, Error>) -> Void) {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routeQuery = HKSampleQuery(sampleType: routeType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { [weak self] _, samples, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let route = samples?.first as? HKWorkoutRoute else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HealthKit", code: 10, userInfo: [NSLocalizedDescriptionKey: "ルートデータがありません"])))
                }
                return
            }
            self.fetchLocationsAndComputeTimeAtDistance(route: route, workoutStart: workout.startDate, targetMeters: targetMeters, completion: completion)
        }
        healthStore.execute(routeQuery)
    }
    
    private func fetchLocationsAndComputeTimeAtDistance(route: HKWorkoutRoute, workoutStart: Date, targetMeters: Double, completion: @escaping (Result<TimeInterval, Error>) -> Void) {
        var allLocations: [CLLocation] = []
        let routeQuery = HKWorkoutRouteQuery(route: route) { [weak self] _, locations, done, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            if let locs = locations { allLocations.append(contentsOf: locs) }
            guard done else { return }
            let result = self?.computeTimeAtDistance(locations: allLocations, workoutStart: workoutStart, targetMeters: targetMeters)
            DispatchQueue.main.async {
                if let sec = result {
                    completion(.success(sec))
                } else {
                    completion(.failure(NSError(domain: "HealthKit", code: 11, userInfo: [NSLocalizedDescriptionKey: "目標距離に達していません"])))
                }
            }
        }
        healthStore.execute(routeQuery)
    }
    
    private func computeTimeAtDistance(locations: [CLLocation], workoutStart: Date, targetMeters: Double) -> TimeInterval? {
        let sorted = locations.sorted { ($0.timestamp).timeIntervalSince1970 < ($1.timestamp).timeIntervalSince1970 }
        guard !sorted.isEmpty else { return nil }
        var cumulative: Double = 0
        var prev: CLLocation? = nil
        for loc in sorted {
            if let p = prev {
                let d = p.distance(from: loc)
                if d > 0 && d < 500 { cumulative += d }
            }
            prev = loc
            if cumulative >= targetMeters {
                let t = loc.timestamp.timeIntervalSince(workoutStart)
                return max(0, t)
            }
        }
        if cumulative > 0 && targetMeters > 0, let last = sorted.last {
            let ratio = targetMeters / cumulative
            let interp = last.timestamp.timeIntervalSince(workoutStart) * ratio
            return max(0, interp)
        }
        return nil
    }
    
    /// ワークアウトに紐づく歩行＋ランニング距離（m）を取得
    private func getTotalDistanceMeters(workout: HKWorkout, completion: @escaping (Double) -> Void) {
        guard let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            completion(0)
            return
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let q = HKSampleQuery(sampleType: distanceType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let total = (samples as? [HKQuantitySample])?.reduce(0.0) { $0 + $1.quantity.doubleValue(for: HKUnit.meter()) } ?? 0
            DispatchQueue.main.async { completion(total) }
        }
        healthStore.execute(q)
    }

    private func predicateForDataSource(sampleType: HKSampleType, basePredicate: NSPredicate, dataSource: RunningDataSource, completion: @escaping (NSPredicate?) -> Void) {
        guard dataSource != .all else {
            completion(nil)
            return
        }

        let sourceQuery = HKSourceQuery(sampleType: sampleType, samplePredicate: basePredicate) { _, sources, _ in
            let filtered = (sources ?? []).filter { source in
                let sourceName = source.name.lowercased()
                return dataSource.sourceKeywords.contains { sourceName.contains($0) }
            }
            guard !filtered.isEmpty else {
                completion(NSPredicate(value: false))
                return
            }
            completion(HKQuery.predicateForObjects(from: Set(filtered)))
        }
        healthStore.execute(sourceQuery)
    }

    private static func flattenWorkoutMetadata(_ meta: [String: Any]?) -> [String: String] {
        guard let meta else { return [:] }
        var out: [String: String] = [:]
        for key in meta.keys.sorted().prefix(48) {
            guard let raw = meta[key] else { continue }
            let str: String
            switch raw {
            case let s as String:
                str = s
            case let n as NSNumber:
                str = n.stringValue
            case let d as Date:
                str = ISO8601DateFormatter().string(from: d)
            case is HKQuantity:
                str = String(describing: raw)
            default:
                str = String(describing: raw)
            }
            out[String(key.prefix(100))] = String(str.prefix(500))
        }
        return out
    }

    private static func averageQuantityFromWorkoutStats(_ workout: HKWorkout, identifier: HKQuantityTypeIdentifier, unit: HKUnit) -> Double? {
        guard let qtype = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        guard let stats = workout.statistics(for: qtype), let avg = stats.averageQuantity() else { return nil }
        return avg.doubleValue(for: unit)
    }

    /// `HKWorkout.totalEnergyBurned` の代替（iOS 18+ ではワークアウト統計の活動カロリーを参照）
    private static func totalEnergyKcalFromWorkout(_ workout: HKWorkout) -> Double? {
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let stats = workout.statistics(for: t),
           let sum = stats.sumQuantity() {
            return sum.doubleValue(for: HKUnit.kilocalorie())
        }
        return nil
    }

    /// メタデータに含まれる上昇量（メーカー依存のキーを走査）
    private static func elevationAscendedMetersFromMetadata(_ meta: [String: Any]?) -> Double? {
        guard let meta else { return nil }
        let keys = ["HKElevationAscended", "ElevationAscended", "Ascent", "totalAscent", "elevationGain", "ElevationGain"]
        for key in keys {
            guard let raw = meta[key] else { continue }
            if let n = raw as? NSNumber { return n.doubleValue }
            if let s = raw as? String, let v = Double(s.replacingOccurrences(of: ",", with: "")) { return v }
        }
        return nil
    }

    private static func buildRunningWorkoutInfo(
        workout: HKWorkout,
        totalDistanceKm: Double,
        timeAtTargetSeconds: Double?,
        heartAvg: Double?,
        heartMin: Double?,
        heartMax: Double?
    ) -> RunningWorkoutInfo {
        let start = workout.startDate
        let end = workout.endDate
        let wall = max(0, end.timeIntervalSince(start))
        let rev = workout.sourceRevision
        let src = rev.source
        let dev = workout.device
        let speedMps = averageQuantityFromWorkoutStats(workout, identifier: .runningSpeed, unit: HKUnit.meter().unitDivided(by: HKUnit.second()))
        let distWO = workout.totalDistance?.doubleValue(for: HKUnit.meter())
        let energy = totalEnergyKcalFromWorkout(workout)
        let elevM = elevationAscendedMetersFromMetadata(workout.metadata)
        let meta = flattenWorkoutMetadata(workout.metadata)

        return RunningWorkoutInfo(
            id: workout.uuid,
            startDate: start,
            endDate: end,
            durationSeconds: workout.duration,
            wallClockDurationSeconds: wall,
            totalDistanceKm: totalDistanceKm,
            timeAtTargetSeconds: timeAtTargetSeconds,
            totalDistanceFromWorkoutMeters: distWO,
            totalEnergyBurnedKcal: energy,
            averageHeartRateBpm: heartAvg,
            minHeartRateBpm: heartMin,
            maxHeartRateBpm: heartMax,
            averageRunningSpeedMps: speedMps,
            elevationAscendedMeters: elevM,
            sourceName: src.name,
            sourceBundleIdentifier: src.bundleIdentifier,
            deviceManufacturer: dev?.manufacturer,
            deviceModel: dev?.model,
            deviceHardwareVersion: dev?.hardwareVersion,
            deviceSoftwareVersion: dev?.softwareVersion,
            udiDeviceIdentifier: dev?.udiDeviceIdentifier,
            workoutActivityTypeRaw: Int(workout.workoutActivityType.rawValue),
            metadata: meta
        )
    }

    private func fetchHeartRateAggregate(workout: HKWorkout, completion: @escaping (Double?, Double?, Double?) -> Void) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async { completion(nil, nil, nil) }
            return
        }
        let pred = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: [.strictStartDate])
        let opts: HKStatisticsOptions = [.discreteAverage, .discreteMin, .discreteMax]
        let hrUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let q = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: pred, options: opts) { _, statistics, _ in
            let avg = statistics?.averageQuantity()?.doubleValue(for: hrUnit)
            let minV = statistics?.minimumQuantity()?.doubleValue(for: hrUnit)
            let maxV = statistics?.maximumQuantity()?.doubleValue(for: hrUnit)
            DispatchQueue.main.async { completion(avg, minV, maxV) }
        }
        healthStore.execute(q)
    }

    /// 期間内のランニングワークアウトを取得。minDistanceKm 以上で、targetDistanceKm 時点のタイムをルートから算出（可能な場合）
    func fetchRunningWorkouts(from start: Date, to end: Date, minDistanceKm: Double, targetDistanceKm: Double, dataSource: RunningDataSource = .all, completion: @escaping (Result<[RunningWorkoutInfo], Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(NSError(domain: "HealthKit", code: 0, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available."])))
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let workoutType = HKObjectType.workoutType()
        predicateForDataSource(sampleType: workoutType, basePredicate: predicate, dataSource: dataSource) { [weak self] sourcePredicate in
            guard let self = self else { return }
            let finalPredicate: NSPredicate
            if let sourcePredicate = sourcePredicate {
                finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, sourcePredicate])
            } else {
                finalPredicate = predicate
            }

            let workoutQuery = HKSampleQuery(sampleType: workoutType, predicate: finalPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { [weak self] _, samples, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                let workouts = (samples as? [HKWorkout])?.filter { $0.workoutActivityType == .running } ?? []
                let targetMeters = targetDistanceKm * 1000
                let minMeters = minDistanceKm * 1000
                var infos: [RunningWorkoutInfo] = []
                let group = DispatchGroup()
                let lock = NSLock()
                for w in workouts {
                    group.enter()
                    self.getTotalDistanceMeters(workout: w) { meters in
                        guard meters >= minMeters else { group.leave(); return }
                        let totalKm = meters / 1000.0
                        self.timeAtDistance(workout: w, targetMeters: targetMeters) { result in
                            let timeAt: Double?
                            switch result {
                            case .success(let sec): timeAt = sec
                            case .failure: timeAt = nil
                            }
                            self.fetchHeartRateAggregate(workout: w) { avg, minHR, maxHR in
                                let info = HealthKitManager.buildRunningWorkoutInfo(
                                    workout: w,
                                    totalDistanceKm: totalKm,
                                    timeAtTargetSeconds: timeAt,
                                    heartAvg: avg,
                                    heartMin: minHR,
                                    heartMax: maxHR
                                )
                                lock.lock()
                                infos.append(info)
                                lock.unlock()
                                group.leave()
                            }
                        }
                    }
                }
                group.notify(queue: .main) {
                    infos.sort { $0.startDate > $1.startDate }
                    completion(.success(infos))
                }
            }
            self.healthStore.execute(workoutQuery)
        }
    }

    /// 直近のランニングワークアウト日からの経過日数（同日なら0）。記録が無い場合は nil。
    func fetchDaysSinceLastRunningWorkout(completion: @escaping (Int?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: workoutType,
            predicate: runningPredicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let workout = samples?.first as? HKWorkout else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let cal = Calendar.current
            let lastDay = cal.startOfDay(for: workout.endDate)
            let today = cal.startOfDay(for: Date())
            let days = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
            DispatchQueue.main.async { completion(days) }
        }
        healthStore.execute(query)
    }
}

