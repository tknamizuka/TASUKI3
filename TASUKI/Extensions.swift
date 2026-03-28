import SwiftUI
import UIKit

extension Color {
    /// 駅伝ブランド黄（全面背景ではなくアクセント専用・この1値のみ）
    static let tasukiBrandYellow = Color(hex: "E8FF00")

    /// 画面全面の下地（白に近い薄ラベンダー。黄は使わない）
    static let tasukiBase = Color(hex: "F7F5FB")
    static let tasukiDarkBackground = Color(hex: "F7F5FB")

    /// 本文・アイコン主色（ディープパープル）
    static let tasukiPrimary = Color(hex: "2A0F45")
    /// インタラクティブ・リンク・強調
    static let tasukiAccent = Color(hex: "5D2D91")
    static let tasukiDanger = Color(hex: "FF453A")

    /// カード・モーダル上面（白の島）
    static let tasukiSurface = Color(hex: "FFFFFF")
    static let tasukiDarkCard = Color(hex: "FFFFFF")
    /// 黄／白カード上の区切り・薄い沈み
    static let tasukiDarkCardSecondary = Color(hex: "EFEAF5")

    static let tasukiMutedText = Color(hex: "5C486E")

    static let tasukiAccentOrange = tasukiAccent

    static let royalBlue = tasukiAccent
    /// 最も暗い紫トーン（強調テキスト・極小要素）
    static let midnightNavy = Color(hex: "1A0A2E")
    static let pureWhite = Color(hex: "FFFFFF")
    /// 旧「deep navy」呼称の互換（現主色と同一）
    static let deepNavy = tasukiPrimary

    /// 浮いたタブバー上で選択ピルが白背景に溶けないようにする薄紫ハイライト
    static let tasukiTabSelectionFill = tasukiAccent.opacity(0.14)

    // 2. Hex変換用イニシャライザ
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension UIColor {
    static let tasukiBrandYellowUI = UIColor(red: 232 / 255, green: 255 / 255, blue: 0 / 255, alpha: 1)
    static let tasukiTabSelectedPurple = UIColor(red: 93 / 255, green: 45 / 255, blue: 145 / 255, alpha: 1)
}

enum TasukiUI {
    static let cardCorner: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let iconSize: CGFloat = 20
}

extension View {
    func tasukiCard(corner: CGFloat = TasukiUI.cardCorner) -> some View {
        self
            .padding(TasukiUI.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.tasukiSurface)
                    .shadow(color: Color.tasukiMutedText.opacity(0.12), radius: 8, x: 0, y: 3)
            )
    }
}

// MARK: - Flow Layout (for tags)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}
