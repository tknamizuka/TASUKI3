//
//  EkidenRankingProgressBar.swift
//  TASUKI
//
//  ランキング・観戦で「マップの代わり」に使う、累計距離を全区間規定距離に対する進捗率で 1 本トラック上に載せる。
//

import SwiftUI

/// 各チームの累計走行 km を、`referenceTotalKm` を 100% とした進捗率でトラック上に配置する。
struct EkidenTeamsCourseProgressBar: View {
    struct Marker: Identifiable, Hashable {
        let id: String
        let title: String
        let cumulativeKm: Double
    }

    let markers: [Marker]
    /// 全区間の規定距離（km）。これを分母に `累計 / 参照 = 0…100%` でマッピングする。
    let referenceTotalKm: Double
    let emphasizedMarkerIds: Set<String>
    /// `Marker.id` のうち自チーム（黄色・背景透過で強調）
    let ownTeamMarkerIds: Set<String>
    @Binding var focusedMarkerId: String?

    private var denom: Double { max(referenceTotalKm, 0.001) }

    private var sortedMarkers: [Marker] {
        markers.sorted {
            if $0.cumulativeKm != $1.cumulativeKm { return $0.cumulativeKm < $1.cumulativeKm }
            return $0.id < $1.id
        }
    }

    private func progressFraction(km: Double) -> CGFloat {
        CGFloat(min(1, max(0, km / denom)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if markers.isEmpty {
                Text("表示できるチームがありません")
                    .font(.footnote)
                    .foregroundColor(Color.tasukiMutedText)
            } else {
                GeometryReader { geo in
                    let w = max(1, geo.size.width)
                    let barTop: CGFloat = 22
                    let barH: CGFloat = 12
                    let barMidY = barTop + barH / 2
                    let maxKm = markers.map(\.cumulativeKm).max() ?? 0
                    let leaderFrac = progressFraction(km: maxKm)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.22))
                            .frame(width: w, height: barH)
                            .position(x: w / 2, y: barMidY)

                        if maxKm > 0 {
                            let fillW = w * leaderFrac
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.tasukiAccent.opacity(0.24))
                                .frame(width: fillW, height: barH)
                                .position(x: fillW / 2, y: barMidY)
                        }

                        ForEach(sortedMarkers) { m in
                            let frac = progressFraction(km: m.cumulativeKm)
                            let isOwn = ownTeamMarkerIds.contains(m.id)
                            let isEm = emphasizedMarkerIds.contains(m.id)
                            let isFocus = focusedMarkerId == m.id
                            let iconFont: CGFloat = isFocus ? 20 : (isEm ? 17 : 14)
                            let pad: CGFloat = isFocus ? 5 : 4
                            let box = iconFont + pad * 2
                            let cx = max(box / 2, min(w - box / 2, w * frac))
                            let stagger = CGFloat(clusterIndex(for: m))
                            runnerMarker(
                                fontSize: iconFont,
                                padding: pad,
                                isOwnTeam: isOwn,
                                isEm: isEm,
                                isFocus: isFocus
                            )
                                .frame(width: box, height: box)
                                .position(x: cx, y: barMidY - 14 - stagger * 7)
                                .accessibilityLabel(accessibilityLine(for: m, isOwnTeam: isOwn))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minWidth: 1)
                .frame(height: 48)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("0%")
                    Spacer()
                    Text("100%（\(String(format: "%.1f", denom)) km）")
                }
                .font(.caption2.weight(.medium))
                .foregroundColor(Color.tasukiMutedText)
            }
        }
    }

    private func accessibilityLine(for m: Marker, isOwnTeam: Bool) -> String {
        let pct = 100.0 * min(1, max(0, m.cumulativeKm / denom))
        let tag = isOwnTeam ? "自チーム、" : ""
        return "\(tag)\(m.title)、累計 \(String(format: "%.1f", m.cumulativeKm)) km、進捗 \(String(format: "%.1f", pct))パーセント"
    }

    @ViewBuilder
    private func runnerMarker(
        fontSize: CGFloat,
        padding: CGFloat,
        isOwnTeam: Bool,
        isEm: Bool,
        isFocus: Bool
    ) -> some View {
        let symbolColor: Color = {
            if isOwnTeam { return Color.tasukiBrandYellow }
            if isFocus || isEm { return Color.tasukiAccent }
            return Color.black.opacity(0.82)
        }()
        Image(systemName: "figure.run")
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(symbolColor)
            .padding(padding)
            .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 0)
            .shadow(color: .black.opacity(0.25), radius: 1.2, x: 0, y: 0.5)
    }

    private func clusterIndex(for m: Marker) -> Int {
        let tolKm = denom * 0.008
        let cluster = sortedMarkers.filter { abs($0.cumulativeKm - m.cumulativeKm) <= tolKm }
        return cluster.firstIndex(where: { $0.id == m.id }) ?? 0
    }
}
