import Foundation

// MARK: - Onboarding / preferences

enum ContinuityBarrier: String, CaseIterable, Identifiable, Codable {
    case fatigue
    case time
    case alone
    case weather
    case motivation
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fatigue: return "疲れ・睡眠"
        case .time: return "時間がない"
        case .alone: return "一人だと続かない"
        case .weather: return "天気・季節"
        case .motivation: return "やる気が続かない"
        case .other: return "その他"
        }
    }
}

enum LeaderboardComfort: String, CaseIterable, Identifiable, Codable {
    case enjoys
    case prefersSoft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .enjoys: return "順位やランキングが励みになる"
        case .prefersSoft: return "あまり比較したくない"
        }
    }
}

// MARK: - Significant interaction (re-engagement gap)

enum EngagementSignals {
    static let lastSignificantInteractionKey = "tasuki.lastSignificantInteraction"

    static func touchSignificantInteraction() {
        UserDefaults.standard.set(Date(), forKey: lastSignificantInteractionKey)
        RealityMiningManager.shared.trackEvent(name: "engagement_significant_touch", properties: [:])
    }

    static func daysSinceSignificantInteraction() -> Int {
        if UserDefaults.standard.object(forKey: lastSignificantInteractionKey) == nil {
            let now = Date()
            UserDefaults.standard.set(now, forKey: lastSignificantInteractionKey)
            return 0
        }
        guard let last = UserDefaults.standard.object(forKey: lastSignificantInteractionKey) as? Date else { return 0 }
        let cal = Calendar.current
        let startLast = cal.startOfDay(for: last)
        let startNow = cal.startOfDay(for: Date())
        return cal.dateComponents([.day], from: startLast, to: startNow).day ?? 0
    }
}

// MARK: - Daily check-in

enum DailyCheckInStore {
    private static let dayKey = "tasuki.dailyCheckin.day"
    private static let conditionKey = "tasuki.dailyCheckin.condition"

    static func todayDayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func savedCheckInConditionForToday() -> Condition? {
        guard UserDefaults.standard.string(forKey: dayKey) == todayDayString() else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: conditionKey) else { return nil }
        return Condition(rawValue: raw)
    }

    static func saveCheckIn(_ condition: Condition) {
        UserDefaults.standard.set(todayDayString(), forKey: dayKey)
        UserDefaults.standard.set(condition.rawValue, forKey: conditionKey)
        EngagementSignals.touchSignificantInteraction()
        RealityMiningManager.shared.trackEvent(
            name: "checkin_submitted",
            properties: ["condition": condition.rawValue]
        )
    }

    static func hasCheckedInToday() -> Bool {
        savedCheckInConditionForToday() != nil
    }
}

// MARK: - Suggestion engine

enum TodayPlan: String, Codable {
    case runEasy
    case runPlanned
    case rest
    case microWalk
    case checkInNeeded
}

struct CompanionSuggestion: Equatable {
    let plan: TodayPlan
    let title: String
    let reason: String
    let primaryCTALabel: String
    let secondaryCTALabel: String?
}

enum CompanionSuggestionEngine {

    static func loadBarrier() -> ContinuityBarrier? {
        guard let raw = UserDefaults.standard.string(forKey: "tasuki.continuityBarrier") else { return nil }
        return ContinuityBarrier(rawValue: raw)
    }

    static func loadLeaderboardComfort() -> LeaderboardComfort {
        guard let raw = UserDefaults.standard.string(forKey: "tasuki.leaderboardComfort"),
              let v = LeaderboardComfort(rawValue: raw) else {
            return .enjoys
        }
        return v
    }

    static func suggestion(
        checkIn: Condition?,
        daysSinceLastRun: Int,
        healthKitDaysSinceLastRun: Int? = nil,
        monthlyGoalKm: Double,
        monthToDateKm: Double
    ) -> CompanionSuggestion {
        let mergedDaysSinceLastRun: Int = {
            guard let hk = healthKitDaysSinceLastRun else { return daysSinceLastRun }
            return max(daysSinceLastRun, hk)
        }()

        // ホームではチェックインUIを出さないため、未記録は「普通」相当で提案する
        let condition = checkIn ?? .good
        let barrier = loadBarrier()
        let prefersSoft = loadLeaderboardComfort() == .prefersSoft

        if condition == .sos {
            return CompanionSuggestion(
                plan: .rest,
                title: "今日は休むのも立派なトレーニングです",
                reason: "体が悲鳴を上げている日は、回復が次の走りを楽にします。",
                primaryCTALabel: "今日は休む",
                secondaryCTALabel: "5分だけ歩く"
            )
        }

        if condition == .tired {
            let micro = CompanionSuggestion(
                plan: .microWalk,
                title: "軽く体を動かすだけでも十分です",
                reason: "疲れ気味の日は短くてOK。責めずに形だけ残しましょう。",
                primaryCTALabel: "短いジョグ・ウォークを記録",
                secondaryCTALabel: "今日は休む"
            )
            if barrier == .some(.alone) {
                return CompanionSuggestion(
                    plan: .microWalk,
                    title: "無理な距離は不要。仲間に「今日は軽め」と送れるくらいでOK",
                    reason: "一人だと続きにくい日ほど、小さな達成で十分です。",
                    primaryCTALabel: "短い記録をつける",
                    secondaryCTALabel: "今日は休む"
                )
            }
            return micro
        }

        if mergedDaysSinceLastRun >= 7 {
            return CompanionSuggestion(
                plan: .runEasy,
                title: "久しぶりでも、まずは「戻ってこれた」が成功です",
                reason: "ペースや距離はいったん忘れて、10〜15分のゆるい動きからで大丈夫。",
                primaryCTALabel: "ゆるく記録を始める",
                secondaryCTALabel: "今日は休む"
            )
        }

        if condition == .excellent {
            if monthToDateKm < monthlyGoalKm * 0.5, Calendar.current.component(.day, from: Date()) >= 15 {
                let reason = prefersSoft
                    ? "無理に追わなくても、今日の元気を少しだけ形にできます。"
                    : "目標に向けて、今日のコンディションなら前に進めそうです。"
                return CompanionSuggestion(
                    plan: .runPlanned,
                    title: "コンディション良好。少しだけ前へ進めそうです",
                    reason: reason,
                    primaryCTALabel: "走行を記録する",
                    secondaryCTALabel: "今日は休む"
                )
            }
            return barrierAdjustedExcellent(preferSoft: prefersSoft, barrier: barrier)
        }

        return barrierAdjustedGood(preferSoft: prefersSoft, barrier: barrier, monthToDateKm: monthToDateKm, monthlyGoalKm: monthlyGoalKm)
    }

    private static func barrierAdjustedExcellent(preferSoft: Bool, barrier: ContinuityBarrier?) -> CompanionSuggestion {
        let reason: String
        switch barrier {
        case .some(.alone):
            reason = "調子がいい日は、あとでパートナーやチームに一言共有するのも続きやすさにつながります。"
        case .some(.time):
            reason = "時間がない日でも、短い記録で十分。今日の良さを小さく残しましょう。"
        case .some(.fatigue), .some(.weather), .some(.motivation), .some(.other), .none:
            reason = preferSoft
                ? "今日の良さを短い記録に残すくらいで十分です。"
                : "良い日に少し進めると、先週の自分との比較が気持ちよくなります。"
        }
        return CompanionSuggestion(
            plan: .runPlanned,
            title: "今日は少し伸ばしても良さそうです",
            reason: reason,
            primaryCTALabel: "走行を記録する",
            secondaryCTALabel: "今日は休む"
        )
    }

    private static func barrierAdjustedGood(
        preferSoft: Bool,
        barrier: ContinuityBarrier?,
        monthToDateKm: Double,
        monthlyGoalKm: Double
    ) -> CompanionSuggestion {
        let reason: String
        switch barrier {
        case .some(.alone):
            reason = "無理なペースは不要。小さく記録して、つながりに触れるだけでも十分です。"
        case .some(.time):
            reason = "忙しい日は短時間でOK。記録する時間すら浮かばないなら休みも選択肢です。"
        case .some(.fatigue), .some(.weather), .some(.motivation), .some(.other), .none:
            if monthToDateKm >= monthlyGoalKm {
                reason = preferSoft
                    ? "目標を超えているなら、今日は休んでも全く問題ありません。"
                    : "目標達成ペースです。メンテナンス走行か休息、どちらでも正解です。"
            } else {
                reason = preferSoft
                    ? "継続は“毎回そこそこ”より“長く続くこと”。今日は軽めで十分なことも多いです。"
                    : "安定して積み上げるなら、今日は普段どおりがおすすめです。"
            }
        }
        return CompanionSuggestion(
            plan: .runEasy,
            title: "今日はいつもどおり、少し動くくらいで十分かもしれません",
            reason: reason,
            primaryCTALabel: "走行を記録する",
            secondaryCTALabel: "今日は休む"
        )
    }
}

/// 1対1チャット・チームチャット共通の伴走用短文
enum CompanionChatQuickPhrases {
    static let all: [String] = [
        "今日はオフにします！また走るときよろしく",
        "ようやく再開できました、ゆるく行きます",
        "今日は軽めだけ行きます",
        "お疲れさまです、無理せず続けましょう"
    ]
}
