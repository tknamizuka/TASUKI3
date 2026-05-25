import Foundation

/// Find のマッチ度（0〜100）。プロフィール登録値のみを使用（GPS 記録は使わない）。
enum FindMatchScore {
    /// "5:30/km" "6:00 /km" などから秒/km を推定
    static func paceSecondsPerKm(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let noUnit = trimmed
            .replacingOccurrences(of: "/km", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "/ km", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        let parts = noUnit.split(separator: ":")
        guard parts.count >= 2,
              let m = Double(parts[0].replacingOccurrences(of: " ", with: "")),
              let s = Double(parts[1].replacingOccurrences(of: " ", with: "")) else { return nil }
        return m * 60 + s
    }

    /// 候補の月間走行回数の目安（プロフィールの頻度・月間距離から推定）
    static func effectiveMonthlyRunCount(for user: User) -> Int {
        if let weekly = weeklyRunsFromFrequencyString(user.runningFrequency) {
            return max(0, min(40, weekly * 4))
        }
        let est = Int(user.monthlyDistance / 8.0)
        return max(0, min(40, est))
    }

    static func compute(
        myAvgPace: String,
        myRunningSpots: String,
        myArea: String,
        mySchedule: String,
        myMonthlyDistanceKm: Double,
        candidate: User
    ) -> Int {
        let myPace = paceSecondsPerKm(from: myAvgPace)

        let theirPace = paceSecondsPerKm(from: candidate.avgPace)
            ?? paceSecondsPerKm(from: candidate.pace)

        var paceScore = 50.0
        if let mp = myPace, let tp = theirPace {
            let diff = abs(mp - tp)
            paceScore = max(0, min(100, 100 - diff * 1.15))
        } else if let tp = theirPace, myPace == nil {
            paceScore = max(0, min(100, 100 - abs(tp - 360) * 0.08))
        }

        let locScore = locationScore(
            myRunningSpots: myRunningSpots,
            myArea: myArea,
            candidate: candidate
        )

        let myRuns = estimatedMonthlyRuns(
            runningFrequency: mySchedule,
            monthlyDistanceKm: myMonthlyDistanceKm
        )
        let theirRuns = effectiveMonthlyRunCount(for: candidate)
        let runDiff = Double(abs(myRuns - theirRuns))
        let freqScore = max(0, min(100, 100 - runDiff * 4.5))

        let combined = 0.42 * paceScore + 0.35 * locScore + 0.23 * freqScore
        return max(0, min(100, Int(combined.rounded())))
    }

    // MARK: - Profile-only helpers

    private static func locationScore(
        myRunningSpots: String,
        myArea: String,
        candidate: User
    ) -> Double {
        let myTokens = spotTokens(from: myRunningSpots) + spotTokens(from: myArea)
        let theirTokens = spotTokens(from: candidate.area)
            + spotTokens(from: candidate.spotName)
            + spotTokens(from: candidate.prefecture)

        guard !myTokens.isEmpty, !theirTokens.isEmpty else { return 52 }

        for mine in myTokens {
            for theirs in theirTokens {
                if tokensOverlap(mine, theirs) {
                    return 95
                }
            }
        }

        if let myPref = prefectureToken(from: myArea),
           let theirPref = prefectureToken(from: candidate.prefecture),
           myPref == theirPref {
            return 72
        }

        return 48
    }

    private static func spotTokens(from raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "、", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }

    private static func tokensOverlap(_ a: String, _ b: String) -> Bool {
        let left = a.lowercased()
        let right = b.lowercased()
        return left.contains(right) || right.contains(left)
    }

    private static func prefectureToken(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2 else { return nil }
        if t.hasSuffix("都") || t.hasSuffix("府") || t.hasSuffix("県") {
            return String(t.prefix(while: { $0 != " " && $0 != "," && $0 != "、" }))
        }
        return nil
    }

    private static func weeklyRunsFromFrequencyString(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let range = t.range(of: #"週\s*(\d+)\s*[-〜~～]\s*(\d+)"#, options: .regularExpression) {
            let slice = t[range]
            let nums = slice.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if nums.count >= 2 { return (nums[0] + nums[1]) / 2 }
        }
        if let match = t.range(of: #"週\s*(\d+)"#, options: .regularExpression) {
            let slice = String(t[match])
            if let n = slice.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first {
                return n
            }
        }
        return nil
    }

    private static func estimatedMonthlyRuns(runningFrequency: String, monthlyDistanceKm: Double) -> Int {
        if let weekly = weeklyRunsFromFrequencyString(runningFrequency) {
            return max(0, min(40, weekly * 4))
        }
        let est = Int(monthlyDistanceKm / 8.0)
        return max(0, min(40, est))
    }

    /// AppStorage `myMonthlyDist`（例: "150km"）から km を読む
    static func monthlyDistanceKm(from label: String) -> Double {
        let trimmed = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .lowercased()
            .replacingOccurrences(of: "km", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(trimmed) ?? 0
    }
}
