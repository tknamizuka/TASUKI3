import ActivityKit
import SwiftUI
import WidgetKit

struct RunTrackingLiveActivityWidget: Widget {
    /// Widget の安定した識別子（Xcode のウィジェットデバッグ／descriptor 解決用）
    var kind: String { "RunTrackingLiveActivity" }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunTrackingActivityAttributes.self) { context in
            RunTrackingLiveActivityLockView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    RunTrackingLiveActivityLockView(state: context.state)
                        .padding(.vertical, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            } compactTrailing: {
                Text(context.state.distanceText)
                    .font(.caption2)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }
}

private struct RunTrackingLiveActivityLockView: View {
    let state: RunTrackingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("時間")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(state.timeText)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("距離")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(state.distanceText)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("ペース")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(state.paceText)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .activityBackgroundTint(Color(red: 0.12, green: 0.08, blue: 0.2))
    }
}
