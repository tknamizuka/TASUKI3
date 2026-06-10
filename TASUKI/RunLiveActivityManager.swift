import Foundation
import ActivityKit

/// ロック画面 / Dynamic Island の Live Activity を更新
@MainActor
final class RunLiveActivityManager {
    static let shared = RunLiveActivityManager()

    private static let authorizationProbeSucceededKey = "tasuki.liveActivityAuthorizationProbeSucceeded"

    private var activity: Activity<RunTrackingActivityAttributes>?
    private var tickTimer: Timer?

    private init() {}

    /// プローブが一度成功したら、走行開始前の再リクエストを省略する。
    var hasCompletedAuthorizationProbe: Bool {
        UserDefaults.standard.bool(forKey: Self.authorizationProbeSucceededKey)
    }

    /// Live Activity の利用可否をシステムに確認（短いプレースホルダを即終了）。成功時のみフラグを立てる。
    func requestAuthorizationProbeIfNeeded() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard !hasCompletedAuthorizationProbe else { return }

        let state = RunTrackingActivityAttributes.ContentState(
            timeText: "00:00",
            distanceText: "0.00 km",
            paceText: "--:--/km",
            lapText: "Lap 1 · 0.00km",
            isPaused: false
        )
        do {
            let probe = try await Activity.request(
                attributes: RunTrackingActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            await probe.end(nil, dismissalPolicy: .immediate)
            UserDefaults.standard.set(true, forKey: Self.authorizationProbeSucceededKey)
        } catch {
            // 拡張未埋め込み・ユーザー拒否など（フラグは立てず、RUN 画面等で再試行）
        }
    }

    func beginIfPossible() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            syncFromTracker()
            return
        }
        let state = RunTrackingActivityAttributes.ContentState(
            timeText: "00:00",
            distanceText: "0.00 km",
            paceText: "--:--/km",
            lapText: "Lap 1 · 0.00km",
            isPaused: false
        )
        Task {
            do {
                let act = try await Activity.request(
                    attributes: RunTrackingActivityAttributes(),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                await MainActor.run {
                    self.activity = act
                    self.startTickTimer()
                    self.syncFromTracker()
                }
            } catch {
                // Widget 拡張が未埋め込みの場合など
            }
        }
    }

    func endIfNeeded() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard let activity else { return }
        let a = activity
        self.activity = nil
        Task {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func startTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromTracker()
            }
        }
        if let t = tickTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func syncFromTracker() {
        let t = RunTracker.shared
        guard t.isTracking, let activity else { return }
        let elapsed = t.elapsedSeconds(now: Date())
        let timeText = formatDuration(elapsed)
        let dist = String(format: "%.2f km", t.distanceKm)
        let paceText: String
        if t.distanceKm > 0 {
            let secPerKm = elapsed / t.distanceKm
            let m = Int(secPerKm) / 60
            let s = Int(secPerKm) % 60
            paceText = String(format: "%d:%02d/km", m, s)
        } else {
            paceText = "--:--/km"
        }
        let state = RunTrackingActivityAttributes.ContentState(
            timeText: timeText,
            distanceText: dist,
            paceText: paceText,
            lapText: lapDisplayText(from: t),
            isPaused: t.isPaused
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func lapDisplayText(from tracker: RunTracker) -> String {
        let lapNumber = tracker.completedKilometerLaps.count + 1
        let dist = String(format: "%.2f", tracker.currentLapDistanceKm)
        guard let paceSec = tracker.currentLapPaceSecondsPerKm, paceSec > 0, tracker.currentLapDistanceKm > 0.001 else {
            return "Lap \(lapNumber) · \(dist)km"
        }
        let m = Int(paceSec) / 60
        let s = Int(paceSec) % 60
        return "Lap \(lapNumber) · \(dist)km · \(String(format: "%d:%02d", m, s))/km"
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
