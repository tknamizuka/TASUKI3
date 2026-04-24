import SwiftUI

/// チーム参加ハブの直前に表示する EKIDEN モード選択（黄色の楕円ボタン・縦スクロール）
struct EkidenJoinModeSelectionView: View {
    var onSelect: (EkidenJoinMode) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Text("EKIDENモードを選ぶ")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                        .multilineTextAlignment(.center)
                    Text("参加するチームの前提がモードごとに異なります。あとから「モード」から変更できます。")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.tasukiMutedText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)

                VStack(spacing: 20) {
                    ForEach(EkidenJoinMode.allCases) { mode in
                        Button {
                            onSelect(mode)
                        } label: {
                            VStack(spacing: 10) {
                                Text(mode.displayTitle)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color.tasukiOnBrandYellow)
                                    .multilineTextAlignment(.center)
                                Text(mode.description)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color.tasukiOnBrandYellow.opacity(0.92))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 18)
                            .background(
                                Capsule()
                                    .fill(Color.tasukiPrimaryButtonFill)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)

                // スクロール領域を確保（小画面でも上下に余白）
                Color.clear.frame(height: 120)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
    }
}

#Preview {
    EkidenJoinModeSelectionView(onSelect: { _ in })
}
