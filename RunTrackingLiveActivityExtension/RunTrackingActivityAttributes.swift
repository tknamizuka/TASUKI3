import Foundation
import ActivityKit

/// メインアプリの定義と同一である必要があります（Live Activity）
struct RunTrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timeText: String
        var distanceText: String
        var paceText: String
        /// 進行中ラップ（例: `Lap 2 · 0.65km · 5:30/km`）
        var lapText: String
        var isPaused: Bool
    }
}
