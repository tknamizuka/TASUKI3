import SwiftUI

/// チーム参加ハブの直前に表示する EKIDEN モード選択（カード＋画像・説明、黄色の「参加する」ボタン）
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
                    Text("EKIDEN は襷リレー、Distance Challenge は指定期間のチーム合計距離です。あとから「モード」から変更できます。")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.tasukiMutedText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)

                VStack(spacing: 24) {
                    ForEach(EkidenJoinMode.allCases) { mode in
                        modeSelectionCard(mode)
                    }
                }
                .padding(.horizontal, 20)

                Color.clear.frame(height: 120)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func modeSelectionCard(_ mode: EkidenJoinMode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mode.displayTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            modeHeroImage(mode)
                .frame(maxWidth: .infinity)
                .frame(height: 172)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 14)

            Text(mode.description)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.tasukiMutedText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)

            Button {
                onSelect(mode)
            } label: {
                Text("参加する")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.tasukiPrimaryButtonFill))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.tasukiDarkCardSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.tasukiMutedText.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func modeHeroImage(_ mode: EkidenJoinMode) -> some View {
        if let asset = mode.selectionHeroAssetName {
            // アセットは透過 PNG を想定。背景色は敷かずカード上にそのまま合成する。
            Image(asset)
                .resizable()
                .scaledToFit()
                .padding(8)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.tasukiPrimary.opacity(0.35),
                        Color.tasukiPrimaryButtonFill.opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: mode.selectionHeroSystemImage)
                    .font(.system(size: 76, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.tasukiOnBrandYellow.opacity(0.95))
            }
        }
    }
}

#Preview {
    EkidenJoinModeSelectionView(onSelect: { _ in })
}
