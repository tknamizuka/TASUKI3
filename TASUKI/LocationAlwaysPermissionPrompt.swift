import SwiftUI
import UIKit

/// 位置情報が「使用中のみ」または拒否されているとき、設定アプリで「常に許可」へ誘導する。
enum LocationAlwaysSettingsPrompt {
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct LocationAlwaysPermissionPromptCard: View {
    @Environment(\.openURL) private var openURL

    enum Reason {
        case whenInUseOnly
        case deniedOrRestricted

        var title: String {
            switch self {
            case .whenInUseOnly:
                return "バックグラウンド記録には「常に許可」が必要です"
            case .deniedOrRestricted:
                return "位置情報がオフになっています"
            }
        }

        var message: String {
            switch self {
            case .whenInUseOnly:
                return "スリープ中やロック画面でも距離を計るには、設定で位置情報を「常に許可」に変更してください。"
            case .deniedOrRestricted:
                return "走行記録を行うには、設定で TASUKI の位置情報をオンにし、「常に許可」を選んでください。"
            }
        }
    }

    let reason: Reason
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: compact ? 16 : 18, weight: .semibold))
                    .foregroundColor(Color.tasukiAccentOrange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason.title)
                        .font(.system(size: compact ? 12 : 13, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text(reason.message)
                        .font(.system(size: compact ? 11 : 12, weight: .regular))
                        .foregroundColor(Color.tasukiMutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                } else {
                    LocationAlwaysSettingsPrompt.openSystemSettings()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                    Text("設定を開く")
                }
                .font(.system(size: compact ? 12 : 13, weight: .bold))
                .foregroundColor(Color.tasukiOnBrandYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 10 : 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiPrimaryButtonFill))
            }
            .buttonStyle(.plain)
        }
        .padding(compact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiAccentOrange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.tasukiAccentOrange.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
