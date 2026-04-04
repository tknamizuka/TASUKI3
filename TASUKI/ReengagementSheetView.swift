import SwiftUI

/// しばらく開いていないときの、責めない再開導線。
struct ReengagementSheetView: View {
    let daysAway: Int
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("おかえりなさい")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)

                Text("\(daysAway)日ぶりのようです。戻ってこられたことがまず一歩目です。")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    suggestionRow(icon: "figure.walk", text: "まずは5〜10分のウォークや軽いジョグから")
                    suggestionRow(icon: "moon.zzz.fill", text: "今日は休んで整える日でも問題ありません")
                    suggestionRow(icon: "chart.line.uptrend.xyaxis", text: "目標距離は後からで大丈夫です")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.tasukiSurface)
                )

                Spacer()

                Button {
                    EngagementSignals.touchSignificantInteraction()
                    onDismiss()
                    RealityMiningManager.shared.trackEvent(
                        name: "reengagement_dismissed",
                        properties: ["days_away": daysAway]
                    )
                } label: {
                    Text("了解して続ける")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.tasukiOnBrandYellow)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.tasukiBase)
        }
    }

    private func suggestionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color.tasukiAccent)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.tasukiPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
