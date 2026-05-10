import Foundation
import SwiftUI
import UIKit

extension Color {
    /// 駅伝ブランド黄（全面背景ではなくアクセント専用・この1値のみ）
    static let tasukiBrandYellow = Color(hex: "E8FF00")
    /// 黄塗りボタン上のラベル（白字は使わない）
    static let tasukiOnBrandYellow = Color(hex: "0D0D0D")
    /// 主 CTA の塗り（`tasukiBrandYellow` と同一・意味で検索しやすくする）
    static let tasukiPrimaryButtonFill = tasukiBrandYellow

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

extension UIImage {
    /// 白〜オフ白の背景を透過（JPG 等でアルファがないロゴ用）。黄・紺など彩度のある色は残す。
    func tasukiKnockingOutNearWhiteBackground(
        brightnessMin: CGFloat = 0.93,
        maxSaturationForKnockout: CGFloat = 0.14
    ) -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return self }
        let bytesPerRow = w * 4
        var rawData = [UInt8](repeating: 0, count: h * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: &rawData,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return self }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let rf = CGFloat(rawData[i]) / 255
                let gf = CGFloat(rawData[i + 1]) / 255
                let bf = CGFloat(rawData[i + 2]) / 255
                let maxC = max(rf, gf, bf)
                let minC = min(rf, gf, bf)
                let sat = maxC > 0.001 ? (maxC - minC) / maxC : 0
                let lum = 0.299 * rf + 0.587 * gf + 0.114 * bf
                if lum >= brightnessMin && sat <= maxSaturationForKnockout {
                    rawData[i] = 0
                    rawData[i + 1] = 0
                    rawData[i + 2] = 0
                    rawData[i + 3] = 0
                }
            }
        }

        guard let outCtx = CGContext(
            data: &rawData,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ),
        let outCG = outCtx.makeImage() else { return self }
        return UIImage(cgImage: outCG, scale: scale, orientation: imageOrientation)
    }
}

enum TasukiUI {
    static let cardCorner: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let iconSize: CGFloat = 20
}

/// SF Symbol をブランド黄の塗り + `tasukiOnBrandYellow` の縁取り（8 方向オフセット）で表示する。
struct TasukiBrandOutlinedSymbol: View {
    let systemName: String
    var size: CGFloat = 18
    var weight: Font.Weight = .semibold
    var outlineStep: CGFloat = 1

    private static let outlineOffsets: [(CGFloat, CGFloat)] = [
        (-1, 0), (1, 0), (0, -1), (0, 1),
        (-1, -1), (1, -1), (-1, 1), (1, 1)
    ]

    var body: some View {
        let font = Font.system(size: size, weight: weight)
        ZStack {
            ForEach(Array(Self.outlineOffsets.enumerated()), id: \.offset) { _, o in
                Image(systemName: systemName)
                    .font(font)
                    .foregroundStyle(Color.tasukiOnBrandYellow)
                    .offset(x: o.0 * outlineStep, y: o.1 * outlineStep)
            }
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(Color.tasukiBrandYellow)
        }
    }
}

/// Home / SoloRunHub と同じフラットハブ行（白カード・影なし）。
struct TasukiFlatHubRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var iconFontSize: CGFloat = 22
    var hStackSpacing: CGFloat = 14
    var titleSubtitleSpacing: CGFloat = 3
    var showChevron: Bool = true
    /// 先頭 SF Symbol の色（デフォルトは黒）。
    var iconForegroundColor: Color = .black
    /// コーチ回答などの短いプレビュー（例: Run の COACH 行サムネイル）。
    var replySnippet: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: hStackSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: iconFontSize, weight: .semibold))
                .foregroundColor(iconForegroundColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: titleSubtitleSpacing) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let snippet = replySnippet?.trimmingCharacters(in: .whitespacesAndNewlines), !snippet.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("A")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.tasukiMutedText)
                    Text(snippet)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.92))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .frame(width: 76, alignment: .topLeading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.tasukiDarkCardSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.tasukiMutedText.opacity(0.22), lineWidth: 1)
                )
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText.opacity(0.7))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
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

    /// Home 相当のフラット区画（影なし・薄い沈み色）
    func tasukiFlatCard(corner: CGFloat = TasukiUI.cardCorner) -> some View {
        self
            .padding(TasukiUI.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.tasukiDarkCardSecondary)
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

// MARK: - Agent debug ingest (session f3091f) — DEBUG のみ（Release でローカル HTTP を送出しない）
enum AgentDebugLog {
    static let sessionId = "f3091f"

    static func log(location: String, message: String, hypothesisId: String, data: [String: String] = [:]) {
        #if DEBUG
        let ingestURL = URL(string: "http://127.0.0.1:7824/ingest/d7f1622c-ff7c-497a-bb9c-bba8292b28cf")!
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "timestamp": ts,
            "location": location,
            "message": message,
            "hypothesisId": hypothesisId,
            "data": data
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }
        print("[AgentDebug f3091f] \(line)")
        var req = URLRequest(url: ingestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionId, forHTTPHeaderField: "X-Debug-Session-Id")
        req.httpBody = json
        URLSession.shared.dataTask(with: req).resume()
        #endif
    }
}

// MARK: - Debug session 65844b (NDJSON ingest — simulator-friendly)
enum DebugSession658Log {
    static let sessionId = "65844b"

    static func log(location: String, message: String, hypothesisId: String, data: [String: String] = [:], runId: String = "pre-fix") {
        #if DEBUG
        let ingestURL = URL(string: "http://127.0.0.1:7824/ingest/d7f1622c-ff7c-497a-bb9c-bba8292b28cf")!
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "timestamp": ts,
            "location": location,
            "message": message,
            "hypothesisId": hypothesisId,
            "data": data
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }
        print("[Debug65844b] \(line)")
        var req = URLRequest(url: ingestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionId, forHTTPHeaderField: "X-Debug-Session-Id")
        req.httpBody = json
        URLSession.shared.dataTask(with: req).resume()
        #endif
    }
}
