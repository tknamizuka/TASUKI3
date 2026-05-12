import Foundation
import ActivityKit

/// メインアプリの定義と同一である必要があります（Live Activity）
struct RunTrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timeText: String
        var distanceText: String
        var paceText: String
        var isPaused: Bool
    }
}
