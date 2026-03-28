import SwiftUI

/// 個人の累計ポイントに応じたバッジティア
enum PointBadgeTier: String, CaseIterable {
    case bronze
    case silver
    case gold
    case platinum
    case diamond
    
    var displayName: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .diamond: return "Diamond"
        }
    }
    
    var iconName: String {
        switch self {
        case .bronze: return "circle.fill"
        case .silver: return "circle.fill"
        case .gold: return "star.fill"
        case .platinum: return "diamond.fill"
        case .diamond: return "sparkles"
        }
    }
    
    var color: Color {
        switch self {
        case .bronze: return Color(red: 176/255, green: 141/255, blue: 87/255)
        case .silver: return Color(red: 189/255, green: 195/255, blue: 199/255)
        case .gold: return Color(red: 255/255, green: 215/255, blue: 0/255)
        case .platinum: return Color(red: 229/255, green: 228/255, blue: 226/255)
        case .diamond: return Color(red: 185/255, green: 242/255, blue: 255/255)
        }
    }
}

/// ポイントからバッジティアを算出するヘルパー
struct PointBadgeHelper {
    /// 累計ポイントからバッジティアを返す（しきい値未満なら nil）
    static func tier(forTotalPoints points: Int) -> PointBadgeTier? {
        switch points {
        case 50_000...:
            return .diamond
        case 25_000...:
            return .platinum
        case 10_000...:
            return .gold
        case 5_000...:
            return .silver
        case 1_000...:
            return .bronze
        default:
            return nil
        }
    }
}

/// EKIDEN チーム用のランクティア
enum TeamRankTier: String, CaseIterable {
    case teamS = "Team S"
    case teamA = "Team A"
    case teamB = "Team B"
    case teamC = "Team C"
    case teamD = "Team D"
    
    var displayName: String {
        return rawValue
    }
    
    /// チームランク表示用のカラー
    var color: Color {
        switch self {
        case .teamS: return Color(red: 255/255, green: 215/255, blue: 0/255)
        case .teamA: return Color.tasukiAccent
        case .teamB: return Color(hex: "34C759")
        case .teamC: return Color(hex: "FF9500")
        case .teamD: return Color(hex: "8E8E93")
        }
    }
    
    /// チーム累計ポイントに応じたランク判定
    static func tier(forTeamPoints points: Int) -> TeamRankTier {
        switch points {
        case 10_000...:
            return .teamS
        case 5_000...:
            return .teamA
        case 2_000...:
            return .teamB
        case 500...:
            return .teamC
        default:
            return .teamD
        }
    }
}

