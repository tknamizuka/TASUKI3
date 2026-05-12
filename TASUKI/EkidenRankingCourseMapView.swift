//
//  EkidenRankingCourseMapView.swift
//  TASUKI
//
//  区間賞ランキングなどから遷移し、各チームの累計距離を 1 本の距離バー上に表示する。
//

import SwiftUI

struct EkidenRankingCourseMapView: View {
    let eventId: String
    let isSampleTeam: Bool
    let usesHakoneCourse: Bool
    /// 全区間の規定距離（km）。累計 ÷ この値で 0〜100% の位置に載せる。
    let referenceTotalKm: Double
    /// 自チームのエントリー ID（バー上の自チームマーカーを黄色にする）
    let ownEntryId: String
    let selectedLegIndex: Int
    let legRankForHighlight: Int?
    let legTotalFinishers: Int
    let highlightEntryId: String
    let tappedRowDisplayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [EkidenTeamRankingMapRow] = []
    @State private var isLoading = true
    @State private var focusedRowId: String?

    private var highlightRow: EkidenTeamRankingMapRow? {
        rows.first { $0.entryId == highlightEntryId }
            ?? rows.first { $0.teamDisplayName == tappedRowDisplayName }
    }

    private var emphasizedIds: Set<String> {
        Set(rows.filter { $0.entryId == highlightEntryId || $0.teamDisplayName == tappedRowDisplayName }.map(\.id))
    }

    private var ownTeamMarkerIds: Set<String> {
        Set(rows.filter { $0.entryId == ownEntryId }.map(\.id))
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

                        detailPanel
                            .padding(16)
                    }
                }
            }
            .navigationTitle("コース進捗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var detailPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                if let hi = highlightRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hi.teamDisplayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                        Text("総合 \(hi.overallRank)位（全 \(rows.count) チーム）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)
                        Text("累計距離 \(String(format: "%.1f", hi.cumulativeDistanceKm)) km")
                            .font(.subheadline)
                            .foregroundColor(.black.opacity(0.85))
                        Text("現在の区間: \(hi.currentLegIndex + 1)区")
                            .font(.subheadline)
                            .foregroundColor(.black.opacity(0.85))
                        Text("総合タイム \(EkidenViewState.formatElapsed(hi.totalElapsedSeconds))")
                            .font(.caption)
                            .foregroundColor(Color.tasukiMutedText)
                        if let legRank = legRankForHighlight, legTotalFinishers > 0 {
                            Text("このシートの区間（\(selectedLegIndex + 1)区）: \(legRank)位 / \(legTotalFinishers)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color.tasukiPrimary)
                        }
                        if usesHakoneCourse {
                            Text(HakoneEkidenCourse.mapProgressLabel(cumulativeRunKm: hi.cumulativeDistanceKm))
                                .font(.caption)
                                .foregroundColor(Color.tasukiMutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.95))
                    )
                } else {
                    Text("「\(tappedRowDisplayName)」に対応するチームを一覧から特定できませんでした（デモ用ランキングの仮IDなど）。下の一覧で確認できます。")
                        .font(.footnote)
                        .foregroundColor(Color.tasukiMutedText)
                }

                if !usesHakoneCourse {
                    Text("このイベントは箱根10区プリセット外のため、100% はイベントの区間合計（またはチーム目標距離）に合わせています。")
                        .font(.footnote)
                        .foregroundColor(Color.tasukiMutedText)
                }

                Text("全チーム（一覧タップでバー上のドットを強調）")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.tasukiMutedText)
                    .padding(.top, 4)

                ForEach(rows) { row in
                    let isHi = row.entryId == highlightEntryId || row.teamDisplayName == tappedRowDisplayName
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
                                Text("\(row.currentLegIndex + 1)区 · 累計 \(String(format: "%.1f", row.cumulativeDistanceKm)) km · \(EkidenViewState.formatElapsed(row.totalElapsedSeconds))")
                                    .font(.caption)
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
