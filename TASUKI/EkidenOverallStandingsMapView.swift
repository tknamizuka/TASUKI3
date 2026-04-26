//
//  EkidenOverallStandingsMapView.swift
//  TASUKI
//
//  「総合 n位」から開く。全チームの累計距離を 1 本のトラック上に載せ、総合順位一覧を表示する。
//

import SwiftUI

struct EkidenOverallStandingsMapView: View {
    let eventId: String
    let isSampleTeam: Bool
    let usesHakoneCourse: Bool
    /// 自チーム（ハイライト用）
    let highlightTeamId: String
    let myOutboundRank: Int?
    /// 全区間の規定距離（km）。累計 ÷ この値で 0〜100% の位置に載せる。
    let referenceTotalKm: Double
    /// 総合シートから区間賞シートへ（親がシートを差し替える）
    let onOpenLegRanking: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [EkidenTeamRankingMapRow] = []
    @State private var isLoading = true
    @State private var focusedRowId: String?

    private var highlightRow: EkidenTeamRankingMapRow? {
        rows.first { $0.teamId == highlightTeamId }
    }

    private var emphasizedIds: Set<String> {
        Set(rows.filter { $0.teamId == highlightTeamId }.map(\.id))
    }

    private var ownTeamMarkerIds: Set<String> {
        Set(rows.filter { $0.teamId == highlightTeamId }.map(\.id))
    }

    private var progressMarkers: [EkidenTeamsCourseProgressBar.Marker] {
        rows.map {
            EkidenTeamsCourseProgressBar.Marker(id: $0.id, title: $0.teamDisplayName, cumulativeKm: $0.cumulativeDistanceKm)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                } else if rows.isEmpty {
                    Text("表示できるチームデータがありません")
                        .font(.subheadline)
                        .foregroundColor(Color.tasukiMutedText)
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else {
                    VStack(spacing: 0) {
                        progressSection
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        contentList
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("総合順位")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onOpenLegRanking()
                    } label: {
                        Label("区間賞", systemImage: "trophy.fill")
                    }
                    .foregroundColor(Color.tasukiAccent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.tasukiAccent)
                }
            }
            .task { await loadRows() }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("横軸は全区間を 100% としたときの累計距離の進捗率（順位とは独立）")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.tasukiMutedText)
                .fixedSize(horizontal: false, vertical: true)

            EkidenTeamsCourseProgressBar(
                markers: progressMarkers,
                referenceTotalKm: max(referenceTotalKm, 0.001),
                emphasizedMarkerIds: emphasizedIds,
                ownTeamMarkerIds: ownTeamMarkerIds,
                focusedMarkerId: $focusedRowId
            )

            Button {
                onOpenLegRanking()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("区間賞ランキングを見る")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color.tasukiAccent)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.tasukiAccent.opacity(0.14))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var contentList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("※ 順位とバーは本日分のスナップショットです（日に1回更新）。")
                    .font(.caption2)
                    .foregroundColor(Color.tasukiMutedText)

                if let hi = highlightRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("あなたのチーム: \(hi.teamDisplayName)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                        Text("総合 \(hi.overallRank)位 / \(rows.count)チーム")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)
                        if let ob = myOutboundRank {
                            Text("往路 \(ob)位（参考）")
                                .font(.caption)
                                .foregroundColor(Color.tasukiMutedText)
                        }
                        Text("累計 \(String(format: "%.1f", hi.cumulativeDistanceKm)) km · 現在 \(hi.currentLegIndex + 1)区 · 合計タイム \(EkidenViewState.formatElapsed(hi.totalElapsedSeconds))")
                            .font(.caption)
                            .foregroundColor(.black.opacity(0.85))
                        if usesHakoneCourse {
                            Text(HakoneEkidenCourse.mapProgressLabel(cumulativeRunKm: hi.cumulativeDistanceKm))
                                .font(.caption2)
                                .foregroundColor(Color.tasukiMutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.95)))
                }

                if !usesHakoneCourse {
                    Text("このイベントは箱根10区プリセット外のため、100% はイベントの区間合計（またはチーム目標距離）に合わせています。")
                        .font(.footnote)
                        .foregroundColor(Color.tasukiMutedText)
                }

                Text("全チーム（未完走は進捗順・10区完走は合計タイム順）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.tasukiMutedText)

                Text("一覧タップでバー上のドットを強調")
                    .font(.caption2)
                    .foregroundColor(Color.tasukiMutedText)

                ForEach(rows) { row in
                    let isHi = row.teamId == highlightTeamId
                    let isFocused = focusedRowId == row.id
                    Button {
                        focusedRowId = row.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(row.overallRank)位")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black)
                                .frame(minWidth: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.teamDisplayName)
                                    .font(.system(size: 15, weight: (isHi || isFocused) ? .bold : .semibold))
                                    .foregroundColor(.black)
                                Text("\(row.currentLegIndex + 1)区 · 累計 \(String(format: "%.1f", row.cumulativeDistanceKm)) km")
                                    .font(.caption)
                                    .foregroundColor(Color.tasukiMutedText)
                                Text("合計 \(EkidenViewState.formatElapsed(row.totalElapsedSeconds))")
                                    .font(.caption2)
                                    .foregroundColor(Color.tasukiMutedText)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.tasukiAccent.opacity(isFocused ? 1 : 0.35))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isFocused ? Color.tasukiAccent.opacity(0.12) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if row.id != rows.last?.id {
                        Divider()
                            .background(Color.tasukiMutedText.opacity(0.2))
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    private func loadRows() async {
        isLoading = true
        let list = await EkidenDataService.shared.loadEventTeamRankingMapRowsDailyCached(
            eventId: eventId,
            isSampleTeam: isSampleTeam
        )
        await MainActor.run {
            rows = list
            isLoading = false
        }
    }
}
