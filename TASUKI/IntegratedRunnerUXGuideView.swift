//
//  IntegratedRunnerUXGuideView.swift
//  TASUKI
//
//  アプリのみでの「仮想ハードウェア層」＋衛生要因＋関係性UXの原則をユーザー向けに提示する。
//

import SwiftUI

// MARK: - Product copy & policy (reference for engineers; surfaced in-app)

enum TasukiUXPolicy {

    /// 懲罰的UXを避ける原則（設計レビュー時の参照用）
    static let nonPunitivePrinciples: [String] = [
        "ストリーク途絶・目標未達を責める通知や画面を使わない",
        "休養・目標変更を「失敗」ではなく正当な選択として提示する",
        "エラー・権限拒否は恥ではなく、次の手順が分かる説明にする",
    ]

    static let dataHygieneBullets: [String] = [
        "走行距離などの計測は Apple ヘルス（HealthKit）連携を正とし、二重入力を減らす",
        "機器やアプリの取り込み差は「ソース」を表示し、可能な範囲で一貫した参照に寄せる",
        "同期に失敗した場合は原因と再試行導線を明示する（当面のロードマップ）",
    ]

    static let notificationPolicyBullets: [String] = [
        "プッシュは量より文脈：意味のない定期催促を増やさない",
        "アプリ内の「今日の伴走」やチェックインを主な習慣ループとし、通知は補助に留める",
        "オフの日・体調不良を尊重する文言のみを用いる",
    ]

    static let socialLoopIntro: String =
        "二人三脚の継続には「関係性」が効きます。順位ばかりの比較より、小さなチーム・駅伝・練習募集で現実のつながりから始めるのがTASUKIの設計思想です。"

    static let virtualHardwareIntro: String =
        "専用デバイスを持たない分、お手持ちの環境をひとつの体験として組み立てます。"

    static let virtualHardwareRows: [(icon: String, title: String, detail: String)] = [
        ("heart.text.square.fill", "Apple ヘルス（HealthKit）", "ワークアウトや距離のハブ。アプリ内記録とあわせ、伴走の提案に活用します。"),
        ("applewatch", "Apple Watch（任意）", "計測は腕元に任せ、ラン中は画面に縛られない使い方を推奨します。"),
        ("headphones", "オーディオ", "骨伝導など Eyes-free で、ペース確認の手間を減らすのに向きます。"),
    ]

    static let hygieneRoadmapPhases: [(phase: String, items: [String])] = [
        (
            "いま",
            [
                "HealthKit 連携とソース表示",
                "伴走カード／再開シートの非懲罰的コピー",
                "エラー文言の品格（責めない説明）",
            ]
        ),
        (
            "次",
            [
                "通知の種類・頻度のユーザー設定と計測",
                "HealthKit からの「最終ラン」参照を伴走に統合",
            ]
        ),
        (
            "先",
            [
                "より広い相互運用（標準規格・他サービス連携の拡張）",
                "睡眠・回復系シグナルの慎重な取り込みとプライバシー最小化",
            ]
        ),
    ]
}

// MARK: - Guide UI

struct IntegratedRunnerUXGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                sectionHeader("体験のしくみ", subtitle: TasukiUXPolicy.virtualHardwareIntro)
                VStack(spacing: 12) {
                    ForEach(Array(TasukiUXPolicy.virtualHardwareRows.enumerated()), id: \.offset) { _, row in
                        iconRow(icon: row.icon, title: row.title, detail: row.detail)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.tasukiDarkCard))

                sectionHeader("大切にしていること", subtitle: "衛生要因ファースト／懲罰的UXは採用しません")
                bulletBlock(TasukiUXPolicy.nonPunitivePrinciples)

                sectionHeader("データと信頼")
                bulletBlock(TasukiUXPolicy.dataHygieneBullets)

                sectionHeader("通知の考え方")
                bulletBlock(TasukiUXPolicy.notificationPolicyBullets)

                sectionHeader("続け方ロードマップ（開発の約束）")
                ForEach(Array(TasukiUXPolicy.hygieneRoadmapPhases.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.phase)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.tasukiAccentOrange)
                        ForEach(row.items, id: \.self) { item in
                            bulletLine(item)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiSurface))
                }

                sectionHeader("仲間・コミュニティ", subtitle: TasukiUXPolicy.socialLoopIntro)
                Text("Find タブの練習募集や、EKIDEN のチームで「社会的ジョブ（関係性）」を満たしやすくします。ランキングが苦手な方は Me タブでショートカットを隠せます。")
                    .font(.system(size: 14))
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiDarkCard))
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("統合ランニング体験")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func iconRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color.tasukiAccentOrange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bulletBlock(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { bulletLine($0) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiDarkCard))
    }

    private func bulletLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("・")
                .foregroundColor(Color.tasukiMutedText)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Color.tasukiMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        IntegratedRunnerUXGuideView()
    }
}
