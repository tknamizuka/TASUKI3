//
//  RunHistoryView.swift
//  TASUKI
//
//  走行履歴一覧・詳細（いつ・何km・ペース・地図）
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Route Distance Helper（座標から経路長を計算しマップと一致させる）
private func routeDistanceKm(_ coordinates: [CLLocationCoordinate2D]) -> Double {
    guard coordinates.count >= 2 else { return 0 }
    var totalMeters: CLLocationDistance = 0
    var previous = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
    for i in 1..<coordinates.count {
        let next = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
        totalMeters += previous.distance(from: next)
        previous = next
    }
    return totalMeters / 1000.0
}

// MARK: - Run History Entry
struct RunHistoryEntry: Identifiable {
    let id: UUID
    let date: Date
    let endedAt: Date?
    let durationSeconds: TimeInterval?
    let distanceKm: Double
    let pace: String  // 例: "5:30/km"
    let routeCoordinates: [CLLocationCoordinate2D]
    let source: String?
    let title: String?
    let note: String?
    let perceivedEffort: Int?
    let postRunMood: Int?
    
    init(
        id: UUID = UUID(),
        date: Date,
        endedAt: Date? = nil,
        durationSeconds: TimeInterval? = nil,
        distanceKm: Double,
        pace: String,
        routeCoordinates: [CLLocationCoordinate2D],
        source: String? = nil,
        title: String? = nil,
        note: String? = nil,
        perceivedEffort: Int? = nil,
        postRunMood: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.pace = pace
        self.routeCoordinates = routeCoordinates
        self.source = source
        self.title = title
        self.note = note
        self.perceivedEffort = perceivedEffort
        self.postRunMood = postRunMood
    }
}

// MARK: - Sample Data（皇居周辺などサンプルルート）
private let sampleRunHistory: [RunHistoryEntry] = {
    let cal = Calendar.current
    let now = Date()
    
    // ルート1: 皇居外苑っぽいルート（サンプル座標）
    let route1: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7640),
        CLLocationCoordinate2D(latitude: 35.6780, longitude: 139.7620),
        CLLocationCoordinate2D(latitude: 35.6745, longitude: 139.7650),
        CLLocationCoordinate2D(latitude: 35.6730, longitude: 139.7720),
        CLLocationCoordinate2D(latitude: 35.6760, longitude: 139.7760),
        CLLocationCoordinate2D(latitude: 35.6800, longitude: 139.7740),
        CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7640)
    ]
    
    // ルート2: 代々木公園周辺
    let route2: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.6692, longitude: 139.6889),
        CLLocationCoordinate2D(latitude: 35.6670, longitude: 139.6920),
        CLLocationCoordinate2D(latitude: 35.6640, longitude: 139.6900),
        CLLocationCoordinate2D(latitude: 35.6655, longitude: 139.6850),
        CLLocationCoordinate2D(latitude: 35.6692, longitude: 139.6889)
    ]
    
    // ルート3: 多摩川沿い
    let route3: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 35.6120, longitude: 139.6120),
        CLLocationCoordinate2D(latitude: 35.6080, longitude: 139.6180),
        CLLocationCoordinate2D(latitude: 35.6040, longitude: 139.6150),
        CLLocationCoordinate2D(latitude: 35.6060, longitude: 139.6080),
        CLLocationCoordinate2D(latitude: 35.6120, longitude: 139.6120)
    ]
    
    // 座標から経路長を計算（マップの道に沿った距離）
    let dist1 = round(routeDistanceKm(route1) * 10) / 10
    let dist2 = round(routeDistanceKm(route2) * 10) / 10
    let dist3 = round(routeDistanceKm(route3) * 10) / 10

    return [
        RunHistoryEntry(
            date: cal.date(byAdding: .day, value: -1, to: now)!,
            distanceKm: dist1,
            pace: "5:12/km",
            routeCoordinates: route1
        ),
        RunHistoryEntry(
            date: cal.date(byAdding: .day, value: -3, to: now)!,
            distanceKm: dist2,
            pace: "5:45/km",
            routeCoordinates: route2
        ),
        RunHistoryEntry(
            date: cal.date(byAdding: .day, value: -5, to: now)!,
            distanceKm: dist1,
            pace: "5:30/km",
            routeCoordinates: route1
        ),
        RunHistoryEntry(
            date: cal.date(byAdding: .day, value: -7, to: now)!,
            distanceKm: dist3,
            pace: "5:00/km",
            routeCoordinates: route3
        ),
        RunHistoryEntry(
            date: cal.date(byAdding: .day, value: -10, to: now)!,
            distanceKm: dist2,
            pace: "6:00/km",
            routeCoordinates: route2
        )
    ]
}()

// MARK: - Run History List View
struct RunHistoryListView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var activityStore = RunActivityStore.shared
    var entries: [RunHistoryEntry]? = nil

    private var resolvedEntries: [RunHistoryEntry] {
        if let entries {
            return entries.sorted { $0.date > $1.date }
        }
        let converted = activityStore.activities.map { activity in
            RunHistoryEntry(
                id: activity.id,
                date: activity.startedAt,
                endedAt: activity.endedAt,
                durationSeconds: activity.durationSeconds,
                distanceKm: activity.distanceKm,
                pace: activity.paceLabel,
                routeCoordinates: activity.route.map(\.coordinate),
                source: activity.source,
                title: activity.title,
                note: activity.note,
                perceivedEffort: activity.perceivedEffort,
                postRunMood: activity.postRunMood
            )
        }
        return converted.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if resolvedEntries.isEmpty {
                    VStack(spacing: 10) {
                        Text("履歴がありません")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        Text("走行を記録するとここに表示されます。")
                            .font(.system(size: 13))
                            .foregroundColor(Color.tasukiMutedText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                } else {
                    List(resolvedEntries) { entry in
                        NavigationLink {
                            RunHistoryDetailView(entry: entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatDate(entry.date))
                                        .font(.subheadline)
                                        .foregroundColor(Color.tasukiPrimary)
                                    if let title = entry.title, !title.isEmpty {
                                        Text(title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color.tasukiPrimary)
                                            .lineLimit(1)
                                    }
                                    Text("\(String(format: "%.1f", entry.distanceKm)) km · \(entry.pace)")
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                    if let sec = entry.durationSeconds {
                                        Text("\(formatDuration(sec)) · \(sourceLabel(entry.source))")
                                            .font(.caption2)
                                            .foregroundColor(Color.tasukiMutedText)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color.tasukiMutedText)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.tasukiDarkCardSecondary.opacity(0.45))
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.tasukiDarkBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Activity")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(Color.tasukiAccentOrange)
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E) HH:mm"
        return f.string(from: date)
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func sourceLabel(_ source: String?) -> String {
        switch source {
        case "run_recorder": return "Run記録"
        case "health_kit": return "HealthKit"
        case "app_record": return "アプリ記録"
        case "manual": return "手入力"
        case .some(let raw) where !raw.isEmpty: return raw
        default: return "不明"
        }
    }
}

// MARK: - Run History Detail View（地図付き）
struct RunHistoryDetailView: View {
    let entry: RunHistoryEntry
    @Environment(\.dismiss) var dismiss
    
    private var mapRegion: MKCoordinateRegion {
        guard !entry.routeCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        let minLat = entry.routeCoordinates.map(\.latitude).min() ?? 35.68
        let maxLat = entry.routeCoordinates.map(\.latitude).max() ?? 35.68
        let minLon = entry.routeCoordinates.map(\.longitude).min() ?? 139.76
        let maxLon = entry.routeCoordinates.map(\.longitude).max() ?? 139.76
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.008),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.008)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 日時・距離・ペース
                VStack(alignment: .leading, spacing: 12) {
                    Text(formatDate(entry.date))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color.tasukiPrimary)
                    if let title = entry.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                    }
                    
                    HStack(spacing: 24) {
                        labelValue(title: "距離", value: "\(String(format: "%.1f", entry.distanceKm)) km")
                        labelValue(title: "ペース", value: entry.pace)
                    }
                    HStack(spacing: 24) {
                        labelValue(title: "時間", value: formatDuration(entry.durationSeconds ?? 0))
                        labelValue(title: "ソース", value: sourceLabel(entry.source))
                    }
                    if let effort = entry.perceivedEffort {
                        labelValue(title: "きつさ", value: "\(effort)/5")
                    }
                    if let mood = entry.postRunMood {
                        labelValue(title: "気分", value: "\(mood)/5")
                    }
                    if let note = entry.note, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("メモ")
                                .font(.caption)
                                .foregroundColor(Color.tasukiMutedText)
                            Text(note)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color.tasukiPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                )
                
                // 地図
                Text("走行ルート")
                    .font(.headline)
                    .foregroundColor(Color.tasukiPrimary)
                
                RunHistoryMapView(coordinates: entry.routeCoordinates, region: mapRegion)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .background(Color.tasukiDarkBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("走行詳細")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E) HH:mm"
        return f.string(from: date)
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func sourceLabel(_ source: String?) -> String {
        switch source {
        case "run_recorder": return "Run記録"
        case "health_kit": return "HealthKit"
        case "app_record": return "アプリ記録"
        case "manual": return "手入力"
        case .some(let raw) where !raw.isEmpty: return raw
        default: return "不明"
        }
    }
    
    private func labelValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.tasukiMutedText)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(Color.tasukiPrimary)
        }
    }
}

// MARK: - Map View（ルート線を描画）
struct RunHistoryMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let region: MKCoordinateRegion
    
    var body: some View {
        Map(initialPosition: .region(region), interactionModes: .all) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.tasukiAccent, lineWidth: 4)
            }
            ForEach(Array(coordinates.enumerated()), id: \.offset) { index, coord in
                if index == 0 {
                    Annotation("スタート", coordinate: coord) {
                        Image(systemName: "flag.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                } else if index == coordinates.count - 1 {
                    Annotation("ゴール", coordinate: coord) {
                        Image(systemName: "flag.checkered")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

#Preview("走行履歴一覧") {
    RunHistoryListView()
}

#Preview("走行詳細") {
    NavigationStack {
        RunHistoryDetailView(entry: sampleRunHistory[0])
    }
}
