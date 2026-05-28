//
//  RunTracker.swift
//  TASUKI
//
//  レース中の走行距離を GPS で計測
//

import Foundation
import Combine
import CoreLocation
import CoreMotion
import SwiftUI

/// 走行中の1kmラップ（完了分・進行中の表示用）。
struct LiveRunKilometerLap: Identifiable, Hashable {
    let index: Int
    let distanceKm: Double
    let durationSeconds: TimeInterval
    let paceSecondsPerKm: Double

    var id: Int { index }
}

struct RunTrackPoint: Codable, Hashable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let speedMetersPerSecond: Double?
    let horizontalAccuracy: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class RunTracker: NSObject, ObservableObject {
    static let shared = RunTracker()
    
    @Published var distanceKm: Double = 0
    @Published var isTracking: Bool = false
    @Published var isPaused: Bool = false
    @Published var locationError: String?
    @Published var elevationGainMeters: Double = 0
    @Published var currentAltitudeMeters: Double = 0
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    /// 描画専用: 生の座標列を移動平均で平滑化したポリライン（距離計算には使わない）
    @Published private(set) var smoothedRouteCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var trackPoints: [RunTrackPoint] = []
    /// 記録中の最新位置（地図の現在地表示用）
    @Published private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    /// 進行方向（度・北=0）。GPS course または直近2点の方位。
    @Published private(set) var lastKnownCourseDegrees: CLLocationDirection?
    @Published private(set) var trackingStartedAt: Date?
    @Published private(set) var averageCadenceSpm: Double?
    @Published private(set) var maxCadenceSpm: Double?
    /// 走行中に1秒ごとに更新。経過時間・ペースなどのUIが `Timer.publish` に依存せず確実に再描画されるようにする。
    @Published private(set) var trackingUIHeartbeatAt: Date = Date()
    /// 完了した1kmラップ（昇順: 1km目, 2km目…）
    @Published private(set) var completedKilometerLaps: [LiveRunKilometerLap] = []
    /// 進行中ラップの距離・時間（`completedKilometerLaps` の次のkm区間）
    @Published private(set) var currentLapDistanceKm: Double = 0
    @Published private(set) var currentLapDurationSeconds: TimeInterval = 0
    @Published private(set) var currentLapPaceSecondsPerKm: Double?
    
    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var lastLocation: CLLocation?
    private var lastAltitude: Double?
    private var lastDistanceBucket: Int = 0
    private var lapSegmentStartElapsedSeconds: TimeInterval = 0
    private var lapSegmentStartDistanceKm: Double = 0
    private var pausedAt: Date?
    private var accumulatedPausedSeconds: TimeInterval = 0
    // Accuracy tuning values calibrated for phone-based running.
    private let maxHorizontalAccuracy: CLLocationAccuracy = 25
    private let maxStaleSeconds: TimeInterval = 5
    /// 記録開始直後は GPS が安定しにくいため、一定時間だけ許容を緩める
    private let warmupMaxHorizontalAccuracy: CLLocationAccuracy = 65
    private let warmupMaxStaleSeconds: TimeInterval = 10
    private let minSegmentDistanceMeters: CLLocationDistance = 2
    private let minRoutePointDistanceMeters: CLLocationDistance = 3
    private let maxRunningSpeedMps: CLLocationSpeed = 8.5
    private let warmupDurationSeconds: TimeInterval = 10
    private let warmupMaxRunningSpeedMps: CLLocationSpeed = 7.0
    private let routeSmoothingWindowSize = 5
    /// 走行開始前の地図プレビュー用に位置更新のみ行う（距離・ルートには加えない）。Run 画面表示中かつフォアグラウンドのみ。
    private var isPreviewingMapLocation = false
    private var isRunScreenVisible = false
    private var cadenceSampleCount: Int = 0
    private var cadenceSampleSum: Double = 0
    private var trackingUIHeartbeatTimer: Timer?
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = false
    }
    
    /// 位置情報は「常に許可」のみ案内する（`requestWhenInUseAuthorization` は使わない）。
    func requestAlwaysPermissionIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// コールドスタート時: 前回セッションの位置更新が残っていても距離計測しないよう停止する。
    func prepareForApplicationLaunch() {
        isTracking = false
        isPaused = false
        isPreviewingMapLocation = false
        isRunScreenVisible = false
        haltLocationUpdatesCompletely()
    }

    /// Run タブ／走行画面の表示状態（タブ切替でプレビュー GPS を止める）
    func setRunScreenVisible(_ visible: Bool) {
        isRunScreenVisible = visible
        if visible {
            syncMapPreviewIfNeeded()
        } else {
            stopMapPreviewLocationUpdates()
        }
    }

    /// フォアグラウンド／バックグラウンド遷移
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if isTracking, !isPaused {
                applyBackgroundLocationPolicyForTracking()
                locationManager.startUpdatingLocation()
            } else {
                syncMapPreviewIfNeeded()
            }
        case .inactive, .background:
            if isTracking, !isPaused, canUseBackgroundLocationWhileTracking {
                applyBackgroundLocationPolicyForTracking()
            } else {
                haltLocationUpdatesCompletely()
            }
        @unknown default:
            haltLocationUpdatesCompletely()
        }
    }

    /// 走行開始前: 地図に現在地を出すためだけに GPS を更新する（記録はしない）
    func startMapPreviewLocationUpdates() {
        guard !isTracking else { return }
        isPreviewingMapLocation = true
        syncMapPreviewIfNeeded()
    }

    /// 走行開始前プレビューをやめる（バッテリー負荷軽減）。記録中は何もしない。
    func stopMapPreviewLocationUpdates() {
        guard !isTracking else { return }
        isPreviewingMapLocation = false
        if !isTracking {
            haltLocationUpdatesCompletely()
        }
    }

    private func syncMapPreviewIfNeeded() {
        guard isPreviewingMapLocation, !isTracking, isRunScreenVisible else {
            if !isTracking {
                haltLocationUpdatesCompletely()
            }
            return
        }
        requestAlwaysPermissionIfNeeded()
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.startUpdatingLocation()
    }

    private var canUseBackgroundLocationWhileTracking: Bool {
        locationManager.authorizationStatus == .authorizedAlways
    }

    /// 走行中以外は位置更新を完全停止（バックグラウンド取得も無効化）
    private func haltLocationUpdatesCompletely() {
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
    }

    /// UI 用: 位置情報が使えるか
    var isLocationAuthorizedForUse: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    /// 「使用中のみ」のため、ロック中のバックグラウンド計測ができない状態。
    var needsAlwaysLocationUpgrade: Bool {
        locationManager.authorizationStatus == .authorizedWhenInUse
    }

    var isLocationPermissionBlocked: Bool {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }
    
    private func applyBackgroundLocationPolicyForTracking() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            haltLocationUpdatesCompletely()
            return
        }
        locationManager.pausesLocationUpdatesAutomatically = false
        if status == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.showsBackgroundLocationIndicator = true
        } else {
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.showsBackgroundLocationIndicator = false
        }
    }

    func start() {
        isPreviewingMapLocation = false
        haltLocationUpdatesCompletely()
        requestAlwaysPermissionIfNeeded()
        let previewCoordinate = lastKnownCoordinate
        lastLocation = nil
        lastAltitude = nil
        distanceKm = 0
        lastDistanceBucket = 0
        resetKilometerLapState()
        elevationGainMeters = 0
        currentAltitudeMeters = 0
        if let previewCoordinate {
            routeCoordinates = [previewCoordinate]
            smoothedRouteCoordinates = [previewCoordinate]
            trackPoints = [
                RunTrackPoint(
                    timestamp: Date(),
                    latitude: previewCoordinate.latitude,
                    longitude: previewCoordinate.longitude,
                    altitudeMeters: 0,
                    speedMetersPerSecond: nil,
                    horizontalAccuracy: 999
                )
            ]
            lastKnownCoordinate = previewCoordinate
        } else {
            routeCoordinates = []
            smoothedRouteCoordinates = []
            trackPoints = []
            lastKnownCoordinate = nil
        }
        trackingStartedAt = Date()
        pausedAt = nil
        accumulatedPausedSeconds = 0
        isPaused = false
        locationError = nil
        cadenceSampleCount = 0
        cadenceSampleSum = 0
        averageCadenceSpm = nil
        maxCadenceSpm = nil
        applyBackgroundLocationPolicyForTracking()
        locationManager.startUpdatingLocation()
        startCadenceUpdates()
        isTracking = true
        RunLiveActivityManager.shared.beginIfPossible()
        RealityMiningManager.shared.trackEvent(name: "run_tracking_start")
        startTrackingUIHeartbeat()
    }
    
    func stop() {
        stopTrackingUIHeartbeat()
        RunLiveActivityManager.shared.endIfNeeded()
        if isPaused, let pausedAt {
            accumulatedPausedSeconds += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        haltLocationUpdatesCompletely()
        stopCadenceUpdates()
        RealityMiningManager.shared.trackEvent(
            name: "run_tracking_stop",
            properties: ["distance_km": distanceKm]
        )
        isPaused = false
        isTracking = false
    }

    private func startTrackingUIHeartbeat() {
        stopTrackingUIHeartbeat()
        trackingUIHeartbeatAt = Date()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.isTracking else { return }
            DispatchQueue.main.async {
                self.trackingUIHeartbeatAt = Date()
                self.refreshCurrentKilometerLapProgress(now: Date())
            }
        }
        trackingUIHeartbeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTrackingUIHeartbeat() {
        trackingUIHeartbeatTimer?.invalidate()
        trackingUIHeartbeatTimer = nil
    }

    func pause() {
        guard isTracking, !isPaused else { return }
        haltLocationUpdatesCompletely()
        stopCadenceUpdates()
        pausedAt = Date()
        isPaused = true
    }

    func resume() {
        guard isTracking, isPaused else { return }
        if let pausedAt {
            accumulatedPausedSeconds += Date().timeIntervalSince(pausedAt)
        }
        self.pausedAt = nil
        applyBackgroundLocationPolicyForTracking()
        locationManager.startUpdatingLocation()
        startCadenceUpdates()
        isPaused = false
    }
    
    func reset() {
        if !isTracking {
            haltLocationUpdatesCompletely()
        }
        lastLocation = nil
        lastAltitude = nil
        distanceKm = 0
        lastDistanceBucket = 0
        resetKilometerLapState()
        elevationGainMeters = 0
        currentAltitudeMeters = 0
        routeCoordinates = []
        smoothedRouteCoordinates = []
        trackPoints = []
        lastKnownCoordinate = nil
        lastKnownCourseDegrees = nil
        trackingStartedAt = nil
        pausedAt = nil
        accumulatedPausedSeconds = 0
        isPaused = false
        stopCadenceUpdates()
        cadenceSampleCount = 0
        cadenceSampleSum = 0
        averageCadenceSpm = nil
        maxCadenceSpm = nil
    }

    func elapsedSeconds(now: Date = Date()) -> TimeInterval {
        guard isTracking, let startedAt = trackingStartedAt else { return 0 }
        let raw = max(0, now.timeIntervalSince(startedAt))
        let pausedExtra: TimeInterval
        if isPaused, let pausedAt {
            pausedExtra = accumulatedPausedSeconds + max(0, now.timeIntervalSince(pausedAt))
        } else {
            pausedExtra = accumulatedPausedSeconds
        }
        return max(0, raw - pausedExtra)
    }

    private func startCadenceUpdates() {
        guard CMPedometer.isCadenceAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self else { return }
            guard self.isTracking, !self.isPaused else { return }
            guard let cadence = data?.currentCadence?.doubleValue, cadence > 0 else { return }
            let cadenceSpm = cadence * 60.0
            DispatchQueue.main.async {
                self.cadenceSampleCount += 1
                self.cadenceSampleSum += cadenceSpm
                self.averageCadenceSpm = self.cadenceSampleSum / Double(self.cadenceSampleCount)
                self.maxCadenceSpm = max(self.maxCadenceSpm ?? cadenceSpm, cadenceSpm)
            }
        }
    }

    private func stopCadenceUpdates() {
        pedometer.stopUpdates()
    }

    private func resetKilometerLapState() {
        completedKilometerLaps = []
        lapSegmentStartElapsedSeconds = 0
        lapSegmentStartDistanceKm = 0
        currentLapDistanceKm = 0
        currentLapDurationSeconds = 0
        currentLapPaceSecondsPerKm = nil
    }

    private func refreshCurrentKilometerLapProgress(now: Date = Date()) {
        guard isTracking else {
            currentLapDistanceKm = 0
            currentLapDurationSeconds = 0
            currentLapPaceSecondsPerKm = nil
            return
        }
        let elapsed = elapsedSeconds(now: now)
        let lapDistance = max(0, distanceKm - lapSegmentStartDistanceKm)
        currentLapDistanceKm = lapDistance
        currentLapDurationSeconds = max(0, elapsed - lapSegmentStartElapsedSeconds)
        if lapDistance > 0.001 {
            currentLapPaceSecondsPerKm = currentLapDurationSeconds / lapDistance
        } else {
            currentLapPaceSecondsPerKm = nil
        }
    }

    private func recordKilometerLaps(from previousBucket: Int, to newBucket: Int, now: Date) {
        guard newBucket > previousBucket else { return }
        let elapsed = elapsedSeconds(now: now)
        var segmentStartElapsed = lapSegmentStartElapsedSeconds
        var segmentStartDistance = lapSegmentStartDistanceKm

        for km in (previousBucket + 1)...newBucket {
            let lapDuration = max(0, elapsed - segmentStartElapsed)
            let pace = lapDuration > 0 ? lapDuration : 0
            let lap = LiveRunKilometerLap(
                index: km,
                distanceKm: 1.0,
                durationSeconds: lapDuration,
                paceSecondsPerKm: pace
            )
            completedKilometerLaps.append(lap)
            segmentStartElapsed = elapsed
            segmentStartDistance = Double(km)
        }

        lapSegmentStartElapsedSeconds = segmentStartElapsed
        lapSegmentStartDistanceKm = segmentStartDistance
        refreshCurrentKilometerLapProgress(now: now)
    }
}

extension RunTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }

        // 走行セッション外の更新は無視（バックグラウンド取得の取りこぼし防止）
        guard isTracking || (isPreviewingMapLocation && isRunScreenVisible) else { return }

        // 走行前: 地図の現在地ピンのみ更新（ルート・距離は触らない）
        if isPreviewingMapLocation && !isTracking {
            let maxPreviewAccuracy = maxHorizontalAccuracy * 3
            let previewCandidate = locations.reversed().first { location in
                guard location.horizontalAccuracy >= 0 else { return false }
                guard location.horizontalAccuracy <= maxPreviewAccuracy else { return false }
                let ageSeconds = abs(location.timestamp.timeIntervalSinceNow)
                return ageSeconds <= maxStaleSeconds * 3
            }
            guard let previewCandidate else { return }
            DispatchQueue.main.async {
                self.lastKnownCoordinate = previewCandidate.coordinate
                self.updateLastKnownCourse(from: previewCandidate, previous: nil)
            }
            return
        }

        guard isTracking, !isPaused else { return }
        for location in locations where location.horizontalAccuracy >= 0 {
            guard shouldUseLocation(location) else { continue }
            ingestTrackingLocation(location)
        }
    }

    private func ingestTrackingLocation(_ newLocation: CLLocation) {
        let previousLocation = lastLocation
        DispatchQueue.main.async {
            self.lastKnownCoordinate = newLocation.coordinate
            self.updateLastKnownCourse(from: newLocation, previous: previousLocation)
            self.currentAltitudeMeters = max(0, newLocation.altitude)
            self.trackPoints.append(
                RunTrackPoint(
                    timestamp: newLocation.timestamp,
                    latitude: newLocation.coordinate.latitude,
                    longitude: newLocation.coordinate.longitude,
                    altitudeMeters: newLocation.altitude,
                    speedMetersPerSecond: newLocation.speed >= 0 ? newLocation.speed : nil,
                    horizontalAccuracy: newLocation.horizontalAccuracy
                )
            )
            if let lastCoord = self.routeCoordinates.last {
                let last = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                if last.distance(from: newLocation) >= self.minRoutePointDistanceMeters {
                    self.routeCoordinates.append(newLocation.coordinate)
                    self.smoothedRouteCoordinates = self.smoothedCoordinates(from: self.routeCoordinates)
                }
            } else {
                self.routeCoordinates.append(newLocation.coordinate)
                self.smoothedRouteCoordinates = self.routeCoordinates
            }
        }
        if let last = lastLocation {
            let dt = newLocation.timestamp.timeIntervalSince(last.timestamp)
            guard dt > 0 else {
                lastLocation = newLocation
                return
            }
            let meters = last.distance(from: newLocation)
            if meters >= minSegmentDistanceMeters && isPlausibleRunSegment(distanceMeters: meters, dt: dt, locationSpeed: newLocation.speed) {
                DispatchQueue.main.async {
                    let now = Date()
                    self.distanceKm += meters / 1000.0
                    let previousBucket = self.lastDistanceBucket
                    let currentBucket = Int(self.distanceKm)
                    if currentBucket > previousBucket {
                        self.recordKilometerLaps(from: previousBucket, to: currentBucket, now: now)
                        self.lastDistanceBucket = currentBucket
                        RealityMiningManager.shared.trackEvent(
                            name: "distance_bucket_reached",
                            properties: ["distance_bucket_km": currentBucket]
                        )
                    } else {
                        self.refreshCurrentKilometerLapProgress(now: now)
                    }
                }
            }
            if let prevAltitude = self.lastAltitude {
                let delta = newLocation.altitude - prevAltitude
                if delta > 0 {
                    self.elevationGainMeters += delta
                }
            }
            self.lastAltitude = newLocation.altitude
        }
        lastLocation = newLocation
    }

    private func updateLastKnownCourse(from location: CLLocation, previous: CLLocation?) {
        if location.course >= 0 {
            lastKnownCourseDegrees = location.course
            return
        }
        if let previous {
            let speed = location.speed >= 0 ? location.speed : 0
            let dist = previous.distance(from: location)
            if speed >= 0.5 || dist >= 3 {
                lastKnownCourseDegrees = Self.bearingDegrees(
                    from: previous.coordinate,
                    to: location.coordinate
                )
            }
        }
    }

    private static func bearingDegrees(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearing = atan2(y, x) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return bearing
    }

    private func smoothedCoordinates(from raw: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard raw.count >= 3 else { return raw }
        let radius = max(1, routeSmoothingWindowSize / 2)
        var smoothed: [CLLocationCoordinate2D] = raw
        for i in 1..<(raw.count - 1) {
            let start = max(0, i - radius)
            let end = min(raw.count - 1, i + radius)
            let segment = raw[start...end]
            let sumLat = segment.reduce(0.0) { $0 + $1.latitude }
            let sumLon = segment.reduce(0.0) { $0 + $1.longitude }
            let count = Double(segment.count)
            smoothed[i] = CLLocationCoordinate2D(latitude: sumLat / count, longitude: sumLon / count)
        }
        smoothed[0] = raw[0]
        smoothed[raw.count - 1] = raw[raw.count - 1]
        return smoothed
    }

    private func shouldUseLocation(_ location: CLLocation) -> Bool {
        let elapsedSinceStart = trackingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let isWarmup = elapsedSinceStart <= warmupDurationSeconds
        let allowedAccuracy = isWarmup ? warmupMaxHorizontalAccuracy : maxHorizontalAccuracy
        let allowedStaleSeconds = isWarmup ? warmupMaxStaleSeconds : maxStaleSeconds

        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > allowedAccuracy {
            return false
        }
        let ageSeconds = abs(location.timestamp.timeIntervalSinceNow)
        if ageSeconds > allowedStaleSeconds {
            return false
        }
        return true
    }

    private func isPlausibleRunSegment(distanceMeters: CLLocationDistance, dt: TimeInterval, locationSpeed: CLLocationSpeed) -> Bool {
        guard dt > 0 else { return false }
        let derivedSpeed = distanceMeters / dt
        let measuredSpeed = locationSpeed >= 0 ? locationSpeed : derivedSpeed
        let segmentSpeed = max(derivedSpeed, measuredSpeed)
        let elapsedSinceStart = trackingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let speedLimit = elapsedSinceStart <= warmupDurationSeconds ? warmupMaxRunningSpeedMps : maxRunningSpeedMps
        return segmentSpeed <= speedLimit
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.locationError = error.localizedDescription
            RealityMiningManager.shared.trackEvent(
                name: "location_tracking_error",
                properties: ["error_message": error.localizedDescription]
            )
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.locationError = "位置情報が許可されていません"
                RealityMiningManager.shared.trackEvent(
                    name: "location_permission_state",
                    properties: ["state": "denied_or_restricted"]
                )
            case .authorizedAlways, .authorizedWhenInUse:
                if self.isTracking, !self.isPaused {
                    self.applyBackgroundLocationPolicyForTracking()
                    self.locationManager.startUpdatingLocation()
                } else {
                    self.syncMapPreviewIfNeeded()
                }
                RealityMiningManager.shared.trackEvent(
                    name: "location_permission_state",
                    properties: ["state": "authorized"]
                )
            case .notDetermined:
                RealityMiningManager.shared.trackEvent(
                    name: "location_permission_state",
                    properties: ["state": "not_determined"]
                )
            default:
                break
            }
        }
    }
}
