import ActivityKit
import SwiftUI
import WidgetKit

struct RunTrackingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunTrackingActivityAttributes.self) { context in
            RunTrackingLiveActivityLockView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    liveActivityMetricBlock(title: "時間", value: context.state.timeText)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    liveActivityMetricBlock(title: "距離", value: context.state.distanceText)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        liveActivityMetricBlock(title: "ペース", value: context.state.paceText)
                        liveActivityMetricBlock(title: "ラップ", value: context.state.lapText)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            } compactTrailing: {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(context.state.paceText)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(context.state.lapText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            } minimal: {
                Text(context.state.paceText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

private func liveActivityMetricBlock(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private struct RunTrackingLiveActivityLockView: View {
    let state: RunTrackingActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                liveActivityMetricBlock(title: "時間", value: state.timeText)
                liveActivityMetricBlock(title: "距離", value: state.distanceText)
            }
            HStack(alignment: .center, spacing: 12) {
                liveActivityMetricBlock(title: "ペース", value: state.paceText)
                liveActivityMetricBlock(title: "ラップ", value: state.lapText)
            }
        }
        .padding(.horizontal, 4)
        .activityBackgroundTint(Color(red: 0.12, green: 0.08, blue: 0.2))
    }
}
