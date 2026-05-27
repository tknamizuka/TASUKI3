import Combine
import Foundation
import MapKit
import SwiftUI

// MARK: - よく走るエリア候補（公園・河川敷・陸上競技場などに限定）

enum ActivityAreaCompletionFilter {
    static let maxResults = 32

    private static let residentialMarkers: [String] = [
        "番地", "号室", "マンション", "アパート", "レジデンス", "コーポ", "ハイツ"
    ]

    private static let excludeKeywords: [String] = [
        "駅", "停留所", "バス停", "改札", "ホーム", "プラットホーム", "駅前", "駅ビル",
        "コンビニ", "セブン", "ローソン", "ファミリー", "ミニストップ",
        "スーパー", "イオン", "マーケット", "ストア", "ショップ", "百貨", "デパート", "モール", "アウトレット",
        "レストラン", "カフェ", "喫茶", "ラーメン", "寿司", "焼肉", "居酒屋", "バー", "ピザ", "マクドナルド", "スターバックス",
        "ホテル", "旅館", "民宿", "ゲストハウス",
        "銀行", "郵便局", "信用金庫", "ATM",
        "病院", "クリニック", "診療", "薬局", "ドラッグ",
        "学校", "高校", "大学", "中学校", "小学校", "保育園", "幼稚園", "学園",
        "市役所", "区役所", "町役場", "県庁", "役所", "警察署", "消防署",
        "駐車場", "パーキング", "ガソリン", "給油",
        "カラオケ", "ゲームセンター", "パチンコ", "映画館", "劇場", "美術館", "博物館",
        "葬儀", "斎場", "墓園", "霊園",
        "株式会社", "有限会社", "事務所", "オフィス", "ビル", "タワー"
    ]

    private static let includeKeywords: [String] = {
        var keys = [
            "公園", "緑地", "広場", "遊歩道", "河川", "河川敷", "土手", "堤防", "水辺", "沿い",
            "海浜", "海岸", "ビーチ", "浜", "渚", "砂浜", "臨海",
            "陸上", "トラック", "スタジアム", "競技場", "運動場", "運動公園", "総合運動", "体育館", "サッカー場",
            "ジョギング", "ランニング", "マラソン", "ウォーキング", "ラムサール",
            "自然公園", "国民公園", "湿原", "森林", "林道",
            "皇居", "外苑", "神宮", "宮苑", "離宮", "城址", "城跡", "古城",
            "代々木", "駒沢", "明治神宮", "芝公園", "井の頭", "砧", "善福寺", "高輪",
            "日比谷", "浜離宮", "お台場", "台場", "若洲", "夢の島", "昭和記念",
            "大濠", "御苑", "鴨川", "広瀬川", "豊平川"
        ]
        keys.append(contentsOf: JapanRunningSpotCatalog.allSpotNames)
        return keys
    }()

    private static func normalized(_ completion: MKLocalSearchCompletion) -> String {
        (completion.title + " " + completion.subtitle).lowercased()
    }

    static func shouldExclude(_ completion: MKLocalSearchCompletion) -> Bool {
        let t = completion.title + completion.subtitle
        if residentialMarkers.contains(where: { t.contains($0) }) { return true }
        let n = normalized(completion)
        if excludeKeywords.contains(where: { n.contains($0.lowercased()) }) { return true }
        let title = completion.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasSuffix("駅") { return true }
        return false
    }

    static func isRunningSpot(_ completion: MKLocalSearchCompletion) -> Bool {
        guard !shouldExclude(completion) else { return false }
        let n = normalized(completion)
        return includeKeywords.contains { n.contains($0.lowercased()) }
    }

    static func priorityScore(_ completion: MKLocalSearchCompletion) -> Int {
        let n = normalized(completion)
        var score = 0
        if n.contains("公園") { score += 6 }
        if n.contains("河川") || n.contains("遊歩") { score += 5 }
        if n.contains("陸上") || n.contains("トラック") || n.contains("スタジアム") { score += 5 }
        if n.contains("皇居") || n.contains("外苑") { score += 4 }
        return score
    }

    static func process(_ raw: [MKLocalSearchCompletion]) -> [MKLocalSearchCompletion] {
        let filtered = raw.filter { isRunningSpot($0) }
        let sorted = filtered.sorted { priorityScore($0) > priorityScore($1) }
        return Array(sorted.prefix(maxResults))
    }
}

@MainActor
final class ActivityAreaSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var curatedSpots: [JapanRunningSpot] = []

    private var regionPrefecture: String = "東京都"
    private var currentQuery: String = ""

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = .pointOfInterest
        c.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .park, .nationalPark, .beach, .marina, .stadium, .fitnessCenter
        ])
        c.region = PrefectureMapRegions.japanWide
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
        updateRegion(forPrefecture: "東京都")
    }

    func updateRegion(forPrefecture name: String) {
        regionPrefecture = name
        if let region = PrefectureMapRegions.region(for: name) {
            completer.region = region
        } else {
            completer.region = PrefectureMapRegions.japanWide
        }
        refreshCuratedSpots()
    }

    func setQuery(_ fragment: String) {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        currentQuery = trimmed
        completer.queryFragment = trimmed
        refreshCuratedSpots()
        if trimmed.isEmpty {
            completions = []
        }
    }

    private func refreshCuratedSpots() {
        curatedSpots = JapanRunningSpotCatalog.matching(prefecture: regionPrefecture, query: currentQuery)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.completions = ActivityAreaCompletionFilter.process(completer.results)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
        }
    }
}

enum ActivityAreaSpotLabel {
    static func displayLabel(for completion: MKLocalSearchCompletion) -> String {
        if completion.subtitle.isEmpty {
            return completion.title
        }
        return "\(completion.title)（\(completion.subtitle)）"
    }

    static func parseStoredSpots(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func joinedSpots(_ spots: [String]) -> String {
        spots.joined(separator: ", ")
    }

    /// 「東京都世田谷区」や「東京都, 世田谷」から都道府県名を推定。
    static func prefectureName(from areaField: String) -> String {
        let trimmed = areaField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "東京都" }
        let head = trimmed.split(separator: ",").first.map(String.init) ?? trimmed
        if let match = head.range(of: #"^(..+?[都道府県])"#, options: .regularExpression) {
            return String(head[match])
        }
        return head
    }
}

/// プロフィール登録・編集で共有する「よく走るエリア」検索 UI。
struct ActivityAreaSpotSearchSection: View {
    @Binding var selectedSpots: [String]
    @Binding var query: String
    @ObservedObject var completer: ActivityAreaSearchCompleter
    var regionPrefecture: String
    var scrollMaxHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("例）皇居、代々木公園", text: $query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onChange(of: query) { _, newValue in
                    completer.setQuery(newValue)
                }

            if !selectedSpots.isEmpty {
                Text("選択中")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.tasukiPrimary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedSpots, id: \.self) { spot in
                        Button {
                            toggle(spot: spot)
                        } label: {
                            HStack {
                                Text(spot)
                                    .font(.subheadline)
                                    .foregroundColor(Color.tasukiPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color.tasukiMutedText)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                ? "おすすめ（\(regionPrefecture)）"
                : "検索候補（公園・河川敷・陸上トラックなど）")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color.tasukiMutedText)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
                    let mapkit = completer.completions.filter { completion in
                        let label = ActivityAreaSpotLabel.displayLabel(for: completion)
                        return !completer.curatedSpots.contains { $0.displayLabel == label }
                    }

                    if completer.curatedSpots.isEmpty && mapkit.isEmpty {
                        Text(trimmedQuery.isEmpty
                            ? "\(regionPrefecture)のおすすめを読み込めませんでした。キーワードで検索してください"
                            : "公園名・河川名などで検索してみてください")
                            .font(.footnote)
                            .foregroundColor(Color.tasukiMutedText)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(completer.curatedSpots) { spot in
                            curatedRow(spot: spot)
                            Divider()
                        }
                        ForEach(Array(mapkit.enumerated()), id: \.offset) { _, completion in
                            mapkitRow(completion: completion)
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: scrollMaxHeight)
        }
        .onAppear {
            completer.updateRegion(forPrefecture: regionPrefecture)
            completer.setQuery(query)
        }
        .onChange(of: regionPrefecture) { _, newValue in
            completer.updateRegion(forPrefecture: newValue)
            completer.setQuery(query)
        }
    }

    private func curatedRow(spot: JapanRunningSpot) -> some View {
        Button {
            toggle(spot: spot.displayLabel)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(spot.name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text("おすすめ")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color.tasukiAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.tasukiAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !spot.detail.isEmpty {
                    Text(spot.detail)
                        .font(.caption)
                        .foregroundColor(Color.tasukiMutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private func mapkitRow(completion: MKLocalSearchCompletion) -> some View {
        let label = ActivityAreaSpotLabel.displayLabel(for: completion)
        return Button {
            toggle(spot: label)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(completion.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color.tasukiPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !completion.subtitle.isEmpty {
                    Text(completion.subtitle)
                        .font(.caption)
                        .foregroundColor(Color.tasukiMutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private func toggle(spot: String) {
        if let idx = selectedSpots.firstIndex(of: spot) {
            selectedSpots.remove(at: idx)
        } else {
            selectedSpots.append(spot)
        }
        query = ""
        completer.setQuery("")
    }
}
