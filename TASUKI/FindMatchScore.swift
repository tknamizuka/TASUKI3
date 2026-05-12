import Foundation

/// Find のマッチ度（0〜100）。自分の月間 GPS 記録と候補ユーザーの `avgPace` / 位置 / 月間走行回数を使う。
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

    static func kmBetween(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// 候補の「今月の走行回数」推定（未設定なら月間距離からおおよそ）
    static func effectiveMonthlyRunCount(for user: User) -> Int {
        if let n = user.monthlyGpsActivityCount { return max(0, n) }
        let est = Int(user.monthlyDistance / 8.0)
        return max(0, min(40, est))
    }

    static func compute(
        myPaceSecPerKm: Double?,
        myMonthlyGpsRuns: Int,
        myRunLatitude: Double?,
        myRunLongitude: Double?,
        myAvgPaceFallback: String,
        candidate: User
    ) -> Int {
        let myPace = myPaceSecPerKm ?? paceSecondsPerKm(from: myAvgPaceFallback)

        let theirPace = paceSecondsPerKm(from: candidate.avgPace)
            ?? paceSecondsPerKm(from: candidate.pace)

        var paceScore = 50.0
        if let mp = myPace, let tp = theirPace {
            let diff = abs(mp - tp)
            paceScore = max(0, min(100, 100 - diff * 1.15))
        } else if let tp = theirPace, myPace == nil {
            paceScore = max(0, min(100, 100 - abs(tp - 360) * 0.08))
        }

        var locScore = 52.0
        if let la = myRunLatitude, let lo = myRunLongitude,
           abs(candidate.latitude) > 1e-4, abs(candidate.longitude) > 1e-4 {
            let km = kmBetween(lat1: la, lon1: lo, lat2: candidate.latitude, lon2: candidate.longitude)
            locScore = max(0, min(100, 100 - km * 6.5))
        }

        let theirRuns = effectiveMonthlyRunCount(for: candidate)
        let runDiff = Double(abs(myMonthlyGpsRuns - theirRuns))
        var freqScore = max(0, min(100, 100 - runDiff * 4.5))

        let combined = 0.42 * paceScore + 0.35 * locScore + 0.23 * freqScore
        return max(0, min(100, Int(combined.rounded())))
    }
}
