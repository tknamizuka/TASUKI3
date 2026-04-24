import Foundation
import CoreLocation
import MapKit

/// 箱根駅伝スタイルの 10 区・距離プリセット（ニューイヤー駅伝想定のコース表記用）
/// 仮想マップの進捗は「登録済み走行距離の累計」をこのコース上に割り当てて表示する。
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

    /// 各区の参考距離（km）と主な中継所ラベル（簡易版）
    static let segments: [Segment] = [
        Segment(id: 0, order: 1, targetKm: 21.3, fromPlace: "大手町", toPlace: "鶴見中継所"),
        Segment(id: 1, order: 2, targetKm: 23.1, fromPlace: "鶴見中継所", toPlace: "戸塚中継所"),
        Segment(id: 2, order: 3, targetKm: 21.4, fromPlace: "戸塚中継所", toPlace: "平塚中継所"),
        Segment(id: 3, order: 4, targetKm: 20.9, fromPlace: "平塚中継所", toPlace: "小田原中継所"),
        Segment(id: 4, order: 5, targetKm: 20.8, fromPlace: "小田原中継所", toPlace: "箱根町"),
        Segment(id: 5, order: 6, targetKm: 20.8, fromPlace: "箱根町", toPlace: "小田原中継所"),
        Segment(id: 6, order: 7, targetKm: 21.3, fromPlace: "小田原中継所", toPlace: "平塚中継所"),
        Segment(id: 7, order: 8, targetKm: 21.4, fromPlace: "平塚中継所", toPlace: "戸塚中継所"),
        Segment(id: 8, order: 9, targetKm: 23.0, fromPlace: "戸塚中継所", toPlace: "鶴見中継所"),
        Segment(id: 9, order: 10, targetKm: 23.0, fromPlace: "鶴見中継所", toPlace: "大手町ゴール")
    ]

    static var totalKm: Double {
        segments.reduce(0) { $0 + $1.targetKm }
    }

    static func segment(forLegIndex legIndex: Int) -> Segment? {
        segments.first { $0.id == legIndex }
    }

    /// 描画用の簡易コース座標（大手町→箱根→大手町）
    static let routeCoordinates: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.6846, longitude: 139.7667), // 大手町
        CLLocationCoordinate2D(latitude: 35.4947, longitude: 139.6714), // 鶴見
        CLLocationCoordinate2D(latitude: 35.4005, longitude: 139.5334), // 戸塚
        CLLocationCoordinate2D(latitude: 35.3263, longitude: 139.3490), // 平塚
        CLLocationCoordinate2D(latitude: 35.2556, longitude: 139.1596), // 小田原
        CLLocationCoordinate2D(latitude: 35.2321, longitude: 139.1069), // 箱根
        CLLocationCoordinate2D(latitude: 35.2556, longitude: 139.1596), // 小田原
        CLLocationCoordinate2D(latitude: 35.3263, longitude: 139.3490), // 平塚
        CLLocationCoordinate2D(latitude: 35.4005, longitude: 139.5334), // 戸塚
        CLLocationCoordinate2D(latitude: 35.4947, longitude: 139.6714), // 鶴見
        CLLocationCoordinate2D(latitude: 35.6846, longitude: 139.7667)  // 大手町
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

    /// 累計距離からコース上の現在地座標を返す（区間完了時に一括更新する演出向け）。
    static func currentCoordinate(cumulativeRunKm: Double) -> CLLocationCoordinate2D {
        guard routeCoordinates.count >= 2, totalKm > 0 else {
            return CLLocationCoordinate2D(latitude: 35.6846, longitude: 139.7667)
        }
        let clamped = max(0, min(cumulativeRunKm, totalKm))
        let fraction = clamped / totalKm
        let segmentFloat = fraction * Double(routeCoordinates.count - 1)
        let lower = Int(floor(segmentFloat))
        let upper = min(routeCoordinates.count - 1, lower + 1)
        let t = segmentFloat - Double(lower)
        let a = routeCoordinates[lower]
        let b = routeCoordinates[upper]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    static func mapRegion(center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        )
    }
}
