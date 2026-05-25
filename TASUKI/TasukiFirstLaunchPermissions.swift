import Foundation
import CoreLocation

/// 走行記録に必要な権限の案内（初回起動・プロフィール初回登録）。
enum TasukiFirstLaunchPermissions {
    private static let firstLaunchKey = "tasuki.firstLaunchRunPermissionsCompleted"
    private static let registrationKey = "tasuki.registrationRunPermissionsCompleted"

    static var hasCompletedFirstLaunch: Bool {
        UserDefaults.standard.bool(forKey: firstLaunchKey)
    }

    static var hasCompletedRegistration: Bool {
        UserDefaults.standard.bool(forKey: registrationKey)
    }

    /// 初回アプリ起動（スプラッシュ中）: 位置情報「常に許可」と Live Activity を一度だけ確認。
    @MainActor
    static func requestOnFirstAppLaunchIfNeeded() async {
        guard !hasCompletedFirstLaunch else { return }

        await requestAlwaysLocationAuthorizationIfNeeded()
        await RunLiveActivityManager.shared.requestAuthorizationProbeIfNeeded()

        UserDefaults.standard.set(true, forKey: firstLaunchKey)
    }

    /// プロフィール初回登録完了時に一度だけ: 位置情報「常に許可」と Live Activity を確認。
    @MainActor
    static func requestOnProfileRegistrationIfNeeded() async {
        guard !hasCompletedRegistration else { return }

        await requestAlwaysLocationAuthorizationIfNeeded()
        await RunLiveActivityManager.shared.requestAuthorizationProbeIfNeeded()

        UserDefaults.standard.set(true, forKey: registrationKey)
    }

    // MARK: - Location（常に許可のみ）

    @MainActor
    private static func requestAlwaysLocationAuthorizationIfNeeded() async {
        let tracker = RunTracker.shared

        switch tracker.authorizationStatus {
        case .notDetermined:
            tracker.requestAlwaysPermissionIfNeeded()
            await waitForLocationAuthorizationChange(from: .notDetermined, timeoutSeconds: 120)
            if tracker.authorizationStatus == .authorizedWhenInUse {
                tracker.requestAlwaysPermissionIfNeeded()
                await waitForLocationAuthorizationChange(from: .authorizedWhenInUse, timeoutSeconds: 120)
            }
        case .authorizedWhenInUse:
            tracker.requestAlwaysPermissionIfNeeded()
            await waitForLocationAuthorizationChange(from: .authorizedWhenInUse, timeoutSeconds: 120)
        default:
            break
        }
    }

    @MainActor
    private static func waitForLocationAuthorizationChange(
        from baseline: CLAuthorizationStatus,
        timeoutSeconds: TimeInterval
    ) async {
        let tracker = RunTracker.shared
        let pollIntervalNanoseconds: UInt64 = 300_000_000
        let maxPolls = Int(timeoutSeconds / 0.3)

        for _ in 0..<maxPolls {
            if tracker.authorizationStatus != baseline {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }
}
