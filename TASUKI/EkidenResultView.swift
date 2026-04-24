//
//  EkidenResultView.swift
//  TASUKI
//
//  駅伝リザルト表示: 区間ラップ・区間賞・チーム順位
//

import SwiftUI

struct EkidenResultView: View {
    let state: EkidenViewState
    let teamId: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        summarySection
                        legResultsSection
                        if state.provisionalRank != nil {
                            rankSection
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("リザルト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        onDismiss()
                    }
                    .foregroundColor(Color.tasukiAccentOrange)
                }
            }
        }
    }

    private var summarySection: some View {
        VStack(spacing: 12) {
            Text("チーム総合タイム")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.tasukiMutedText)
            Text(EkidenViewState.formatElapsed(state.totalElapsedSeconds))
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(Color.tasukiPrimary)
                .monospacedDigit()
            if state.entry.officialResultDisqualified {
                Text("公式記録: 失格（参考記録・OP参加扱い）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiAccentOrange)
            }
            Text("\(state.submittedLegCount)/\(state.event.legCount) 区間完了")
                .font(.system(size: 13))
                .foregroundColor(Color.tasukiMutedText)
            if state.usesOfficialHakoneRelayRules {
                Text(HakoneEkidenCourse.mapProgressLabel(cumulativeRunKm: state.cumulativeDistanceKm))
                    .font(.system(size: 12))
                    .foregroundColor(Color.tasukiMutedText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tasukiDarkCard)
        )
    }

    private var legResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("区間タイム")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
            ForEach(state.legs, id: \.id) { leg in
                legResultRow(leg)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiDarkCard)
        )
    }

    private func legResultRow(_ leg: EkidenLeg) -> some View {
        let name = leg.assignedUid.flatMap { state.memberNames[$0] } ?? "未割当"
        let timeStr: String
        let badge: String?
        if let sec = leg.elapsedSeconds {
            timeStr = EkidenViewState.formatElapsed(leg.status == .submitted ?
                (leg.splitAtTargetSeconds ?? sec) : sec)
            badge = nil
        } else {
            timeStr = "—"
            badge = leg.status == .ready ? "提出可能" : (leg.status == .awaitingTasuki ? "TASUKI待ち" : nil)
        }
        return HStack(spacing: 12) {
            Text("\(leg.id + 1)区")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .frame(width: 32, alignment: .leading)
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.tasukiPrimary)
            Spacer()
            Text(timeStr)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
                .monospacedDigit()
            if let b = badge {
                Text(b)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.tasukiMutedText.opacity(0.3)))
                    .foregroundColor(Color.tasukiMutedText)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.tasukiDarkCardSecondary)
        )
    }

    private var rankSection: some View {
        VStack(spacing: 8) {
            if let rank = state.provisionalRank {
                HStack {
                    Text("暫定順位")
                        .font(.system(size: 14))
                        .foregroundColor(Color.tasukiMutedText)
                    Spacer()
                    Text("\(rank)位")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.tasukiAccentOrange)
                }
                if state.totalTeams > 0 {
                    Text("/ \(state.totalTeams)チーム中")
                        .font(.system(size: 12))
                        .foregroundColor(Color.tasukiMutedText)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiDarkCard)
        )
    }
}
