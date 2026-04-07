import MapKit
import CoreLocation

/// プロフィール登録のエリア検索で `MKLocalSearchCompleter.region` を都道府県に寄せるためのおおよその中心とスパン。
enum PrefectureMapRegions {
    /// `allPrefectures` の名称（「海外」含む）に対応。未登録時は `nil`。
    static func region(for prefectureName: String) -> MKCoordinateRegion? {
        guard let p = parameters[prefectureName] else { return nil }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
            span: MKCoordinateSpan(latitudeDelta: p.latDelta, longitudeDelta: p.lonDelta)
        )
    }

    /// 日本全体のフォールバック
    static var japanWide: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 36.2, longitude: 138.25),
            span: MKCoordinateSpan(latitudeDelta: 25, longitudeDelta: 25)
        )
    }

    private struct P {
        let lat: Double
        let lon: Double
        let latDelta: Double
        let lonDelta: Double
    }

    /// 都道府県庁所在地付近を中心に、県域をおおむね覆うスパン（検索バイアス用の近似値）
    private static let parameters: [String: P] = [
        "北海道": P(lat: 43.06, lon: 141.35, latDelta: 4.5, lonDelta: 5.5),
        "青森県": P(lat: 40.82, lon: 140.74, latDelta: 2.2, lonDelta: 2.8),
        "岩手県": P(lat: 39.70, lon: 141.15, latDelta: 2.2, lonDelta: 2.6),
        "宮城県": P(lat: 38.27, lon: 140.87, latDelta: 2.0, lonDelta: 2.2),
        "秋田県": P(lat: 39.72, lon: 140.10, latDelta: 2.0, lonDelta: 2.4),
        "山形県": P(lat: 38.24, lon: 140.34, latDelta: 2.0, lonDelta: 2.2),
        "福島県": P(lat: 37.75, lon: 140.47, latDelta: 2.4, lonDelta: 3.0),
        "茨城県": P(lat: 36.34, lon: 140.45, latDelta: 2.0, lonDelta: 2.4),
        "栃木県": P(lat: 36.57, lon: 139.88, latDelta: 1.8, lonDelta: 2.0),
        "群馬県": P(lat: 36.39, lon: 139.06, latDelta: 2.0, lonDelta: 2.2),
        "埼玉県": P(lat: 35.86, lon: 139.65, latDelta: 1.4, lonDelta: 1.6),
        "千葉県": P(lat: 35.61, lon: 140.12, latDelta: 1.6, lonDelta: 2.0),
        "東京都": P(lat: 35.68, lon: 139.76, latDelta: 1.2, lonDelta: 1.3),
        "神奈川県": P(lat: 35.45, lon: 139.64, latDelta: 1.2, lonDelta: 1.4),
        "新潟県": P(lat: 37.90, lon: 139.02, latDelta: 2.4, lonDelta: 2.8),
        "富山県": P(lat: 36.70, lon: 137.21, latDelta: 1.6, lonDelta: 1.8),
        "石川県": P(lat: 36.59, lon: 136.63, latDelta: 1.4, lonDelta: 1.6),
        "福井県": P(lat: 36.07, lon: 136.22, latDelta: 1.6, lonDelta: 1.8),
        "山梨県": P(lat: 35.66, lon: 138.57, latDelta: 1.6, lonDelta: 1.8),
        "長野県": P(lat: 36.65, lon: 138.18, latDelta: 2.2, lonDelta: 2.6),
        "岐阜県": P(lat: 35.39, lon: 136.72, latDelta: 1.8, lonDelta: 2.0),
        "静岡県": P(lat: 34.98, lon: 138.38, latDelta: 2.0, lonDelta: 2.4),
        "愛知県": P(lat: 35.18, lon: 136.91, latDelta: 1.6, lonDelta: 1.8),
        "三重県": P(lat: 34.73, lon: 136.51, latDelta: 1.8, lonDelta: 2.0),
        "滋賀県": P(lat: 35.00, lon: 135.87, latDelta: 1.4, lonDelta: 1.6),
        "京都府": P(lat: 35.02, lon: 135.76, latDelta: 1.4, lonDelta: 1.6),
        "大阪府": P(lat: 34.69, lon: 135.50, latDelta: 1.2, lonDelta: 1.3),
        "兵庫県": P(lat: 34.69, lon: 135.18, latDelta: 1.6, lonDelta: 1.8),
        "奈良県": P(lat: 34.69, lon: 135.83, latDelta: 1.4, lonDelta: 1.4),
        "和歌山県": P(lat: 34.23, lon: 135.17, latDelta: 1.6, lonDelta: 1.6),
        "鳥取県": P(lat: 35.50, lon: 134.24, latDelta: 1.6, lonDelta: 1.8),
        "島根県": P(lat: 35.47, lon: 133.05, latDelta: 1.8, lonDelta: 2.0),
        "岡山県": P(lat: 34.66, lon: 133.93, latDelta: 1.6, lonDelta: 1.8),
        "広島県": P(lat: 34.40, lon: 132.46, latDelta: 1.8, lonDelta: 2.0),
        "山口県": P(lat: 34.19, lon: 131.47, latDelta: 1.8, lonDelta: 2.2),
        "徳島県": P(lat: 34.07, lon: 134.56, latDelta: 1.6, lonDelta: 1.8),
        "香川県": P(lat: 34.34, lon: 134.05, latDelta: 1.2, lonDelta: 1.4),
        "愛媛県": P(lat: 33.84, lon: 132.77, latDelta: 1.8, lonDelta: 2.0),
        "高知県": P(lat: 33.56, lon: 133.53, latDelta: 2.0, lonDelta: 2.4),
        "福岡県": P(lat: 33.59, lon: 130.40, latDelta: 1.6, lonDelta: 1.8),
        "佐賀県": P(lat: 33.25, lon: 130.30, latDelta: 1.4, lonDelta: 1.6),
        "長崎県": P(lat: 32.74, lon: 129.87, latDelta: 2.0, lonDelta: 2.4),
        "熊本県": P(lat: 32.79, lon: 130.74, latDelta: 1.8, lonDelta: 2.0),
        "大分県": P(lat: 33.24, lon: 131.61, latDelta: 1.8, lonDelta: 2.0),
        "宮崎県": P(lat: 31.91, lon: 131.42, latDelta: 2.0, lonDelta: 2.2),
        "鹿児島県": P(lat: 31.56, lon: 130.56, latDelta: 2.4, lonDelta: 2.8),
        "沖縄県": P(lat: 26.21, lon: 127.68, latDelta: 2.2, lonDelta: 2.6),
        "海外": P(lat: 36.2, lon: 138.25, latDelta: 25, lonDelta: 25)
    ]
}
