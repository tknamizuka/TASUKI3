//
//  LegalTextAttributed.swift
//  TASUKI
//
//  利用規約・プライバシーポリシー：全文をベース紺（`tasukiPrimary`）。利用規約は冒頭＋「第◯条」、プライバシーは冒頭＋「1.」「(1)」見出しを太字。
//

import SwiftUI
import UIKit

enum LegalTextAttributed {

    private static var baseTextUIColor: UIColor {
        UIColor(Color.tasukiPrimary)
    }

    /// 利用規約：全文紺、導入ブロックと第◯条見出しは太字
    static func termsOfService(bodySize: CGFloat = 13) -> AttributedString {
        let raw = LegalTexts.termsOfServiceText
        let regular = UIFont.systemFont(ofSize: bodySize, weight: .regular)
        let bold = UIFont.systemFont(ofSize: bodySize, weight: .semibold)
        let mas = NSMutableAttributedString(
            string: raw,
            attributes: [
                .foregroundColor: baseTextUIColor,
                .font: regular
            ]
        )

        if let r = raw.range(of: Self.termsLeadingBoldExact) {
            mas.addAttribute(.font, value: bold, range: NSRange(r, in: raw))
        }
        applyRegexBold(mas, in: raw, pattern: "第[0-9]+条（[^）]+）", options: [], boldFont: bold)

        return AttributedString(mas)
    }

    /// プライバシーポリシー：全文紺。タイトル＋導入段落、各「1. …」見出し、「(1) …」小見出しを太字（利用規約の冒頭＋第◯条に相当）
    static func privacyPolicy(bodySize: CGFloat = 13) -> AttributedString {
        let raw = LegalTexts.privacyPolicyText
        let regular = UIFont.systemFont(ofSize: bodySize, weight: .regular)
        let bold = UIFont.systemFont(ofSize: bodySize, weight: .semibold)
        let mas = NSMutableAttributedString(
            string: raw,
            attributes: [
                .foregroundColor: baseTextUIColor,
                .font: regular
            ]
        )

        if let r = raw.range(of: Self.privacyTitleAndIntroBoldExact) {
            mas.addAttribute(.font, value: bold, range: NSRange(r, in: raw))
        }
        applyRegexBold(mas, in: raw, pattern: "(?m)^\\s*[0-9]+\\.\\s+.+$", options: [.anchorsMatchLines], boldFont: bold)
        applyRegexBold(mas, in: raw, pattern: "(?m)^\\s*\\(\\d+\\)\\s+.+$", options: [.anchorsMatchLines], boldFont: bold)

        return AttributedString(mas)
    }

    // MARK: - `LegalTexts` と同一文言（インデントストリップ後の本文）

    private static let termsLeadingBoldExact = """
TASUKI（タスキ）利用規約

この規約（以下「本規約」といいます）は、TASUKIプロジェクト（以下「当社」といいます）が提供するランニングアプリ「TASUKI」（以下「本サービス」といいます）の利用条件を定めるものです。利用者の皆様（以下「ユーザー」といいます）には、本規約に従って本サービスをご利用いただきます。
"""

    /// タイトル行＋導入段落（`LegalTexts.privacyPolicyText` 先頭と一致）
    private static let privacyTitleAndIntroBoldExact = """
プライバシーポリシー

TASUKIプロジェクト（以下「当社」）は、本アプリ「TASUKI」（以下「本サービス」）におけるユーザーの個人情報の取扱いについて、以下のとおりプライバシーポリシー（以下「本ポリシー」）を定めます。
"""

    private static func applyRegexBold(
        _ mas: NSMutableAttributedString,
        in raw: String,
        pattern: String,
        options: NSRegularExpression.Options,
        boldFont: UIFont
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let fullLen = (raw as NSString).length
        for match in regex.matches(in: raw, range: NSRange(location: 0, length: fullLen)) {
            mas.addAttribute(.font, value: boldFont, range: match.range)
        }
    }
}
