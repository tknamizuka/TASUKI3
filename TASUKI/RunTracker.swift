//
//  RunTracker.swift
//  TASUKI
//
//  レース中の走行距離を GPS で計測
//

import Foundation
import Combine
import CoreLocation

final class RunTracker: NSObject, ObservableObject {
    static let shared = RunTracker()
    
    @Published var distanceKm: Double = 0
    @Published var isTracking: Bool = false
    @Published var isPaused: Bool = false
    @Published var locationError: String?
    @Published var elevationGainMeters: Double = 0
    @Published var currentAltitudeMeters: Double = 0
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    /// 記録中の最新位置（地図の現在地表示用）
    @Published private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    @Published private(set) var trackingStartedAt: Date?
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastAltitude: Double?
    private var lastDistanceBucket: Int = 0
    private var pausedAt: Date?
    private var accumulatedPausedSeconds: TimeInterval = 0
    // Accuracy tuning values calibrated for phone-based running.
    private let maxHorizontalAccuracy: CLLocationAccuracy = 25
    private let maxStaleSeconds: TimeInterval = 5
    private let minSegmentDistanceMeters: CLLocationDistance = 2
    private let maxRunningSpeedMps: CLLocationSpeed = 8.5
    private let warmupDurationSeconds: TimeInterval = 40
    private let warmupMaxRunningSpeedMps: CLLocationSpeed = 7.0
    /// バックグラウンド記録のため「常に」を一度案内したか
    private var didPromptAlwaysAuthorizationWhileTracking = false
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 10
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = false
    }
    
    func requestPermissionIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    /// スリープ中も記録するため「常に許可」を案内（走行セッション中・1回まで）
    private func promptAlwaysAuthorizationIfNeeded() {
        guard isTracking else { return }
        guard locationManager.authorizationStatus == .authorizedWhenInUse else { return }
        guard !didPromptAlwaysAuthorizationWhileTracking else { return }
        didPromptAlwaysAuthorizationWhileTracking = true
        locationManager.requestAlwaysAuthorization()
    }
    
    private func applyBackgroundLocationPolicyForTracking() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            locationManager.allowsBackgroundLocationUpdates = false
            return
        }
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
    }
    
    func start() {
        requestPermissionIfNeeded()
        lastLocation = nil
        lastAltitude = nil
        distanceKm = 0
        lastDistanceBucket = 0
        elevationGainMeters = 0
        currentAltitudeMeters = 0
        routeCoordinates = []
        lastKnownCoordinate = nil
        trackingStartedAt = Date()
        pausedAt = nil
        accumulatedPausedSeconds = 0
        isPaused = false
        locationError = nil
        didPromptAlwaysAuthorizationWhileTracking = false
        applyBackgroundLocationPolicyForTracking()
        locationManager.startUpdatingLocation()
        isTracking = true
        promptAlwaysAuthorizationIfNeeded()
        RunLiveActivityManager.shared.beginIfPossible()
        RealityMiningManager.shared.trackEvent(name: "run_tracking_start")
    }
    
    func stop() {
        RunLiveActivityManager.shared.endIfNeeded()
        if isPaused, let pausedAt {
            accumulatedPausedSeconds += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.stopUpdatingLocation()
        RealityMiningManager.shared.trackEvent(
            name: "run_tracking_stop",
            properties: ["distance_km": distanceKm]
        )
        isPaused = false
        isTracking = false
    }

    func pause() {
        guard isTracking, !isPaused else { return }
        locationManager.stopUpdatingLocation()
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
        isPaused = false
    }
    
    func reset() {
        lastLocation = nil
        lastAltitude = nil
        distanceKm = 0
        elevationGainMeters = 0
        currentAltitudeMeters = 0
        routeCoordinates = []
        lastKnownCoordinate = nil
        trackingStartedAt = nil
        pausedAt = nil
        accumulatedPausedSeconds = 0
        isPaused = false
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
}

extension RunTracker: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last, newLocation.horizontalAccuracy >= 0 else { return }
        guard isTracking, !isPaused else { return }
        guard shouldUseLocation(newLocation) else { return }

        DispatchQueue.main.async {
            self.lastKnownCoordinate = newLocation.coordinate
            self.currentAltitudeMeters = max(0, newLocation.altitude)
            if let lastCoord = self.routeCoordinates.last {
                let last = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                if last.distance(from: newLocation) >= 5 {
                    self.routeCoordinates.append(newLocation.coordinate)
                }
            } else {
                self.routeCoordinates.append(newLocation.coordinate)
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
                    self.distanceKm += meters / 1000.0
                    let currentBucket = Int(self.distanceKm)
                    if currentBucket > self.lastDistanceBucket {
                        self.lastDistanceBucket = currentBucket
                        RealityMiningManager.shared.trackEvent(
                            name: "distance_bucket_reached",
                            properties: ["distance_bucket_km": currentBucket]
                        )
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

    private func shouldUseLocation(_ location: CLLocation) -> Bool {
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > maxHorizontalAccuracy {
            return false
        }
        let ageSeconds = abs(location.timestamp.timeIntervalSinceNow)
        if ageSeconds > maxStaleSeconds {
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
        switch manager.authorizationStatus {
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.locationError = "位置情報が許可されていません"
                RealityMiningManager.shared.trackEvent(
                    name: "location_permission_state",
                    properties: ["state": "denied_or_restricted"]
                )
            }
        case .authorizedAlways, .authorizedWhenInUse:
            if isTracking {
                applyBackgroundLocationPolicyForTracking()
                promptAlwaysAuthorizationIfNeeded()
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
