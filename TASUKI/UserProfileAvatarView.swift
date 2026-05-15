import SwiftUI
import UIKit

extension User {
    /// `profileImage` に設定するとバンドル画像の代わりにイニシャルアバターを表示（Find モック用）。
    static let findMockInitialsProfileImageToken = "__find_mock_initials__"

    /// アバター・週次チャートなどで使う色相 0...1（同一ユーザーでは不変の擬似ランダム）。
    var tasukiStableVisualHue: Double {
        var h = Hasher()
        h.combine(id)
        h.combine(name)
        return Double(abs(h.finalize()) % 360) / 360.0
    }

    /// 週次グラフの線・塗り用アクセント色。
    var tasukiStableChartAccentColor: Color {
        Color(hue: tasukiStableVisualHue, saturation: 0.8, brightness: 0.74)
    }
}

/// Find の他ユーザー向けモック週次距離（`WeeklyActivityChartPoint`、右端が今週）。
enum FindMockWeeklyActivity {
    private static func shortWeekLabel(for date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }

    private static func stableSeed(for user: User) -> UInt64 {
        var h = Hasher()
        h.combine(user.name)
        h.combine(user.age)
        h.combine(user.monthlyDistance)
        return UInt64(bitPattern: Int64(h.finalize()))
    }

    /// ユーザーごとにばらつくサンプル週次距離（左が過去、右が今週）。
    static func chartPoints(for user: User, weeks: Int = 8, now: Date = Date(), calendar: Calendar = .current) -> [WeeklyActivityChartPoint] {
        let template: [Double] = [12.0, 18.5, 10.2, 21.3, 16.4, 22.1, 19.8, 24.0]
        let seed = stableSeed(for: user)
        let shift = Int(seed % UInt64(max(template.count, 1)))
        let scale = 0.82 + Double(seed % 35) / 100.0

        return (0..<weeks).map { idx in
            let offset = idx - (weeks - 1)
            let weekAnchor = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            let normalizedAnchor = calendar.dateInterval(of: .weekOfYear, for: weekAnchor)?.start ?? weekAnchor
            let t = template[(idx + shift) % template.count] * scale
            let wobble = Double((seed &+ UInt64(idx) &* 17) % 50) / 10.0 - 2.5
            let km = max(2.0, min(48.0, t + wobble))
            let label = shortWeekLabel(for: normalizedAnchor, calendar: calendar)
            return WeeklyActivityChartPoint(weekAnchor: normalizedAnchor, label: label, distanceKm: km, calendar: calendar)
        }
    }
}

/// 一覧・他ユーザープロフィール用。バンドル画像・モックイニシャル・フォールバックをまとめる。
struct UserProfileAvatarView: View {
    let user: User
    var size: CGFloat

    var body: some View {
        if user.profileImage == User.findMockInitialsProfileImageToken {
            initialsAvatar
        } else if UIImage(named: user.profileImage) != nil {
            Image(user.profileImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: size))
                .foregroundColor(Color.tasukiMutedText)
                .frame(width: size, height: size)
        }
    }

    private var initialsAvatar: some View {
        let letter = Self.displayInitial(from: user.name)
        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: Self.avatarGradientColors(for: user),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(letter)
                .font(.system(size: max(size * 0.38, 14), weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }

    private static func displayInitial(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = trimmed.first else { return "?" }
        if ch.isASCII, ch.isLetter {
            return String(ch).uppercased()
        }
        return String(ch)
    }

    private static func avatarGradientColors(for user: User) -> [Color] {
        let hue = user.tasukiStableVisualHue
        let hue2 = (hue + 0.07).truncatingRemainder(dividingBy: 1.0)
        return [
            Color(hue: hue, saturation: 0.52, brightness: 0.88),
            Color(hue: hue2, saturation: 0.62, brightness: 0.72)
        ]
    }
}
