import Foundation
import CoreLocation
import MapKit

/// 箱根駅伝スタイルの 10 区・距離プリセット（ニューイヤー駅伝想定のコース表記用）
/// 仮想マップの進捗は「登録済み走行距離の累計」をこのコース上に割り当てて表示する。
///
/// **データ出典（WEB調査・2025年前後の公式表記）**
/// - 各区間のキロ数: 東京箱根間往復大学駅伝競走公式サイトのコース紹介・日刊スポーツ等の掲載
///   （往路 107.5 km + 復路 109.6 km = 合計 **217.1 km**）
/// - 中継所・スタート／ゴールの緯度経度: The Tokyo Files「Watching the Hakone Ekiden」内の Google Maps リンク
///   （読売東京本社北側スタート、鶴見・戸塚・平塚・小田原・芦ノ湖、復路各中継、大手町南側ゴール等）
///
/// マップ表示用は、中継点間を**密な折れ線**（1・2・9・10区は陸上寄り中間点、3〜8区は大圏を細分割）でつなぎ、
/// 公式累計 km に沿って補間する。大圏1本だけだと東京湾などを直線で渡るため、チームピンが海上に出るのを避ける。
enum HakoneEkidenCourse {

    /// UI 用の短い説明（棄権・繰り上げ・ランキングはバックエンド連携が必要）
    static let officialRulesFootnote =
        "棄権（リタイア宣言・区間制限時間超過など）が出たチームは公式合計タイムから除外され得ます。繰り上げで完走しても参考記録扱いになる場合があります。"

    struct Segment: Identifiable, Hashable {
        /// 0 始まり区 index（0 = 1区）
        let id: Int
        /// 1 始まり区番号
        let order: Int
        let targetKm: Double
        let fromPlace: String
        let toPlace: String
    }

    /// 各区の**公式距離**（km）と中継ラベル（第101回前後の公式・メディア掲載値に合わせる）
    static let segments: [Segment] = [
        Segment(id: 0, order: 1, targetKm: 21.3, fromPlace: "大手町", toPlace: "鶴見中継所"),
        Segment(id: 1, order: 2, targetKm: 23.1, fromPlace: "鶴見中継所", toPlace: "戸塚中継所"),
        Segment(id: 2, order: 3, targetKm: 21.4, fromPlace: "戸塚中継所", toPlace: "平塚中継所"),
        Segment(id: 3, order: 4, targetKm: 20.9, fromPlace: "平塚中継所", toPlace: "小田原中継所"),
        Segment(id: 4, order: 5, targetKm: 20.8, fromPlace: "小田原中継所", toPlace: "芦ノ湖"),
        Segment(id: 5, order: 6, targetKm: 20.8, fromPlace: "芦ノ湖", toPlace: "小田原中継所"),
        Segment(id: 6, order: 7, targetKm: 21.3, fromPlace: "小田原中継所", toPlace: "平塚中継所"),
        Segment(id: 7, order: 8, targetKm: 21.4, fromPlace: "平塚中継所", toPlace: "戸塚中継所"),
        Segment(id: 8, order: 9, targetKm: 23.1, fromPlace: "戸塚中継所", toPlace: "鶴見中継所"),
        Segment(id: 9, order: 10, targetKm: 23.0, fromPlace: "鶴見中継所", toPlace: "大手町ゴール")
    ]

    static var totalKm: Double {
        segments.reduce(0) { $0 + $1.targetKm }
    }

    static func segment(forLegIndex legIndex: Int) -> Segment? {
        segments.first { $0.id == legIndex }
    }

    /// 累計走行 km（0…`totalKm`）から、**その距離にいる区間**の index（0=1区）を返す。
    /// 各区間の走行距離は規定 km を超えない前提で、中継点ちょうどでは次区間側に入る。
    static func currentLegIndex(forCumulativeRunKm cumulative: Double) -> Int {
        let C = min(max(0, cumulative), totalKm)
        var acc = 0.0
        for seg in segments.sorted(by: { $0.id < $1.id }) {
            let end = acc + seg.targetKm
            if C < end - 1e-9 {
                return seg.id
            }
            acc = end
        }
        return segments.map(\.id).max() ?? 9
    }

    static func totalTargetKm(fromLegDefinitions defs: [EkidenLegDefinition]) -> Double {
        defs.reduce(0) { $0 + $1.targetKm }
    }

    /// Distance Challenge 等、`EkidenLegDefinition` の列から累計に対応する区間 index。
    static func currentLegIndex(forCumulativeRunKm cumulative: Double, legDefinitions: [EkidenLegDefinition]) -> Int {
        let defs = legDefinitions.sorted { $0.id < $1.id }
        let cap = totalTargetKm(fromLegDefinitions: defs)
        guard cap > 0 else { return 0 }
        let C = min(max(0, cumulative), cap)
        var acc = 0.0
        for d in defs {
            let end = acc + d.targetKm
            if C < end - 1e-9 {
                return d.id
            }
            acc = end
        }
        return defs.last?.id ?? 0
    }

    /// コース折れ線の頂点（累計 0 km … 217.1 km）。The Tokyo Files 掲載の Google Maps 座標を採用。
    /// 往路・復路で戸塚・平塚・小田原の位置がわずかに異なる公式ルートを反映。
    static let routeCoordinates: [CLLocationCoordinate2D] = [
        // 0 大手町スタート（読売東京本社・北側付近）
        CLLocationCoordinate2D(latitude: 35.6874751, longitude: 139.7644781),
        // 1 鶴見中継所（往路1区終点）
        CLLocationCoordinate2D(latitude: 35.5165242, longitude: 139.6879421),
        // 2 戸塚中継所（往路）
        CLLocationCoordinate2D(latitude: 35.38937, longitude: 139.52049),
        // 3 平塚中継所（往路）
        CLLocationCoordinate2D(latitude: 35.31357, longitude: 139.33107),
        // 4 小田原中継所（往路4区終点付近）
        CLLocationCoordinate2D(latitude: 35.24724, longitude: 139.15605),
        // 5 芦ノ湖ゴール／復路スタート
        CLLocationCoordinate2D(latitude: 35.18932, longitude: 139.02461),
        // 6 小田原中継所（復路6区終点）
        CLLocationCoordinate2D(latitude: 35.24533, longitude: 139.12935),
        // 7 平塚中継所（復路）
        CLLocationCoordinate2D(latitude: 35.31396, longitude: 139.33083),
        // 8 戸塚中継所（復路）
        CLLocationCoordinate2D(latitude: 35.38893, longitude: 139.52109),
        // 9 鶴見中継所（復路）
        CLLocationCoordinate2D(latitude: 35.51658, longitude: 139.68794),
        // 10 大手町ゴール（読売本社・南側／10区終点）
        CLLocationCoordinate2D(latitude: 35.6867551, longitude: 139.7649698)
    ]

    /// 累計走行距離（km）がコース上のどこに相当するか（走行完了ベースの一括位置づけ用）
    static func mapProgressLabel(cumulativeRunKm: Double) -> String {
        guard cumulativeRunKm > 0 else {
            return "スタート（大手町）"
        }
        var acc: Double = 0
        for seg in segments {
            let next = acc + seg.targetKm
            if cumulativeRunKm < next {
                let into = cumulativeRunKm - acc
                return "\(seg.fromPlace) → \(seg.toPlace)（\(seg.order)区・約\(String(format: "%.1f", into))/\(String(format: "%.1f", seg.targetKm)) km）"
            }
            acc = next
        }
        return "大手町ゴール付近（全区間相当の距離を登録済み）"
    }

    /// 区間一覧の1行キャプション（UI用）
    static func legRouteCaption(legIndex: Int) -> String? {
        guard let s = segment(forLegIndex: legIndex) else { return nil }
        return "\(s.fromPlace) → \(s.toPlace)（\(String(format: "%.1f", s.targetKm)) km）"
    }

    /// 各区間終点までの累計 km（`routeCoordinates[i]` に対応。`segments.count + 1 == routeCoordinates.count` を前提）
    private static var cumulativeKmAtWaypoints: [Double] {
        var out: [Double] = [0]
        var sum = 0.0
        for seg in segments {
            sum += seg.targetKm
            out.append(sum)
        }
        return out
    }

    /// マップ投影用の密な折れ線（累計**公式** km → 座標）。中継点同士の大圏だけだと湾を渡るため、
    /// 各区間に陸上寄り中間点を挟み、各区間の規定 km に沿って km を刻む。
    private static let coursePolylineVertices: [(km: Double, coord: CLLocationCoordinate2D)] = buildCoursePolylineVertices()

    private static func buildCoursePolylineVertices() -> [(km: Double, coord: CLLocationCoordinate2D)] {
        let relays = routeCoordinates
        let cum = cumulativeKmAtWaypoints
        guard relays.count == cum.count, relays.count >= 2 else { return [] }

        var out: [(km: Double, coord: CLLocationCoordinate2D)] = []

        for i in 0..<segments.count {
            let k0 = cum[i]
            let k1 = cum[i + 1]
            let a = relays[i]
            let b = relays[i + 1]
            let segId = segments[i].id
            let chunk: [(km: Double, coord: CLLocationCoordinate2D)]

            switch segId {
            case 0:
                chunk = landCorridorSegment0(fromKm: k0, toKm: k1, start: a, end: b)
            case 1:
                chunk = landCorridorSegment1(fromKm: k0, toKm: k1, start: a, end: b)
            case 8:
                chunk = landCorridorSegment8(fromKm: k0, toKm: k1, start: a, end: b)
            case 9:
                chunk = landCorridorSegment9(fromKm: k0, toKm: k1, start: a, end: b)
            default:
                chunk = geodesicKmChain(fromKm: k0, toKm: k1, start: a, end: b, edgeCount: 6)
            }

            for p in chunk {
                if let last = out.last, abs(last.km - p.km) < 1e-6 { continue }
                out.append(p)
            }
        }
        if let last = out.last, abs(last.km - totalKm) > 0.01, let r = relays.last {
            out.append((km: totalKm, coord: r))
        }
        return out
    }

    /// `edgeCount` 本の辺 → `edgeCount + 1` 頂点。km は等間隔。
    private static func geodesicKmChain(
        fromKm: Double,
        toKm: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        edgeCount: Int
    ) -> [(km: Double, coord: CLLocationCoordinate2D)] {
        let n = max(1, edgeCount)
        var pts: [(km: Double, coord: CLLocationCoordinate2D)] = []
        for k in 0...n {
            let t = Double(k) / Double(n)
            let km = fromKm + (toKm - fromKm) * t
            let c = k == 0 ? start : (k == n ? end : interpolateGeodesic(start, end, t: t))
            pts.append((km: km, coord: c))
        }
        return pts
    }

    private static func landCorridorFractionCoords(
        fromKm: Double,
        toKm: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        mids: [(Double, Double)]
    ) -> [(km: Double, coord: CLLocationCoordinate2D)] {
        let fracs = (0...(mids.count + 1)).map { Double($0) / Double(mids.count + 1) }
        let coords = [start] + mids.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) } + [end]
        return zip(fracs, coords).map { f, c in
            (km: fromKm + (toKm - fromKm) * f, coord: c)
        }
    }

    /// 1区: 大手町→鶴見（陸上コリドー想定）
    private static func landCorridorSegment0(
        fromKm: Double,
        toKm: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> [(km: Double, coord: CLLocationCoordinate2D)] {
        let mids: [(Double, Double)] = [
            (35.6798, 139.7720),
            (35.6698, 139.7772),
            (35.6555, 139.7745),
            (35.6395, 139.7615),
            (35.6115, 139.7415),
            (35.5620, 139.7120)
        ]
        return landCorridorFractionCoords(fromKm: fromKm, toKm: toKm, start: start, end: end, mids: mids)
    }

    /// 2区: 鶴見→戸塚
    private static func landCorridorSegment1(
        fromKm: Double,
        toKm: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> [(km: Double, coord: CLLocationCoordinate2D)] {
        let mids: [(Double, Double)] = [
            (35.4780, 139.6230),
            (35.4480, 139.5680),
            (35.4220, 139.5380),
            (35.4040, 139.5260),
            (35.3925, 139.5210),
            (35.3905, 139.5205)
        ]
        return landCorridorFractionCoords(fromKm: fromKm, toKm: toKm, start: start, end: end, mids: mids)
    }

    /// 9区: 戸塚→鶴見（復路）
    private static func landCorridorSegment8(
        fromKm: Double,
        toKm: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> [(km: Double, coord: CLLocationCoordinate2D)] {
        let mids: [(Double, Double)] = [
            (35.3925, 139.5215),
            (35.4045, 139.5265),
            (35.4230, 139.5390),
            (35.4490, 139.5700),
            (35.4790, 139.6250),
            (35.5050, 139.6680)
        ]
        return landCorridorFractionCoords(fromKm: fromKm, toKm: toKm, start: start, end: end, mids: mids)
    }

    /// 10区: 鶴見→大手町ゴール
    private static func landCorridorSegment9(
        fromKm: Double,
        toKm: Double,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> [(km: Double, coord: CLLocationCoordinate2D)] {
        let mids: [(Double, Double)] = [
            (35.5620, 139.7120),
            (35.6115, 139.7415),
            (35.6395, 139.7615),
            (35.6555, 139.7745),
            (35.6698, 139.7772),
            (35.6798, 139.7720)
        ]
        return landCorridorFractionCoords(fromKm: fromKm, toKm: toKm, start: start, end: end, mids: mids)
    }

    /// コース上を 100m 刻み（0.1km）でサンプリングした座標列。マップ位置はこの列上で補間する。
    static let routeSampleStepKm: Double = 0.1
    private static let coordinatesEvery100m: [CLLocationCoordinate2D] = {
        let poly = coursePolylineVertices
        guard totalKm > 0, poly.count >= 2 else {
            return [
                CLLocationCoordinate2D(latitude: 35.6846, longitude: 139.7667),
                CLLocationCoordinate2D(latitude: 35.6846, longitude: 139.7667)
            ]
        }
        var out: [CLLocationCoordinate2D] = []
        var km = 0.0
        while km <= totalKm + 1e-9 {
            let k = min(km, totalKm)
            out.append(coordinateAlongOfficialCourseKmUnsampled(k))
            km += routeSampleStepKm
        }
        return out
    }()

    /// 緯度経度をラジアンに
    private static func toRad(_ deg: Double) -> Double { deg * .pi / 180 }

    /// 単位球面上の 3D 単位ベクトル（ECEF 風、正規化済み）
    private static func unitVector(from coord: CLLocationCoordinate2D) -> (x: Double, y: Double, z: Double) {
        let φ = toRad(coord.latitude)
        let λ = toRad(coord.longitude)
        let cosφ = cos(φ)
        return (cosφ * cos(λ), cosφ * sin(λ), sin(φ))
    }

    /// 大圏航路上の点（`t` は端点間の球面角の割合 0…1）。公式中継点間の地理的に自然な補間。
    private static func interpolateGeodesic(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let u = max(0, min(1, t))
        if u <= 1e-14 { return a }
        if u >= 1 - 1e-14 { return b }

        let p = unitVector(from: a)
        let q = unitVector(from: b)
        let dot = max(-1, min(1, p.x * q.x + p.y * q.y + p.z * q.z))
        let ω = acos(dot)
        if ω < 1e-10 { return a }

        let sinω = sin(ω)
        let s0 = sin((1 - u) * ω) / sinω
        let s1 = sin(u * ω) / sinω
        let x = s0 * p.x + s1 * q.x
        let y = s0 * p.y + s1 * q.y
        let z = s0 * p.z + s1 * q.z
        let hyp = hypot(x, y)
        let lat = atan2(z, hyp) * 180 / .pi
        let lon = atan2(y, x) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// 100m サンプル列の隣接点間のみ、細かい球面補間用の直線（緯度経度）補間
    private static func interpolateCoordinate(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let u = max(0, min(1, t))
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * u,
            longitude: a.longitude + (b.longitude - a.longitude) * u
        )
    }

    /// 公式区間キロに沿った折れ線上の座標（0…`totalKm` にクランプ済み想定）。100m サンプルの元。
    private static func coordinateAlongOfficialCourseKmUnsampled(_ cumulativeRunKm: Double) -> CLLocationCoordinate2D {
        let poly = coursePolylineVertices
        guard poly.count >= 2, totalKm > 0 else {
            return CLLocationCoordinate2D(latitude: 35.6846, longitude: 139.7667)
        }
        let clamped = max(0, min(cumulativeRunKm, totalKm))
        if clamped >= poly[poly.count - 1].km - 1e-6 {
            return poly[poly.count - 1].coord
        }
        var i = 0
        while i < poly.count - 1 && clamped >= poly[i + 1].km - 1e-9 {
            i += 1
        }
        let a = poly[i]
        let b = poly[i + 1]
        let span = b.km - a.km
        let t = span > 1e-12 ? (clamped - a.km) / span : 0
        return interpolateGeodesic(a.coord, b.coord, t: t)
    }

    /// 累計距離からコース上の現在地座標。100m 間隔のサンプル点列上で線形補間する。
    static func currentCoordinate(cumulativeRunKm: Double) -> CLLocationCoordinate2D {
        let clamped = max(0, min(cumulativeRunKm, totalKm))
        let samples = coordinatesEvery100m
        guard samples.count >= 2, routeSampleStepKm > 0 else {
            return coordinateAlongOfficialCourseKmUnsampled(clamped)
        }
        let f = clamped / routeSampleStepKm
        let i0 = min(max(0, Int(floor(f))), samples.count - 2)
        let t = f - Double(i0)
        return interpolateCoordinate(samples[i0], samples[i0 + 1], t: t)
    }

    /// 一覧でチームを選んだときの寄り表示
    static func mapRegionZoomed(center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.024, longitudeDelta: 0.027)
        )
    }

    static func mapRegion(center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    }

    /// 複数座標を含む範囲（マーカー＋ルート全体を一度に見る用）
    static func mapRegionFitting(coordinates: [CLLocationCoordinate2D], paddingRatio: Double = 0.12) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return mapRegion(center: routeCoordinates.first ?? CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76))
        }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return mapRegion(center: coordinates[0])
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        var latDelta = max(maxLat - minLat, 0.006) * (1 + paddingRatio * 2)
        var lonDelta = max(maxLon - minLon, 0.006) * (1 + paddingRatio * 2)
        latDelta = min(latDelta, 1.2)
        lonDelta = min(lonDelta, 1.2)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
}
