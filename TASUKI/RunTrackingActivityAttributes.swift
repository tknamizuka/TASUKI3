import Foundation
import ActivityKit

/// 走行記録の Live Activity（メインアプリと拡張で同一定義が必要）
struct RunTrackingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var timeText: String
        var distanceText: String
        var paceText: String
        var isPaused: Bool
    }
}
