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
    let distanceKm: Double
    let pace: String  // 例: "5:30/km"
    let routeCoordinates: [CLLocationCoordinate2D]
    let metrics: RunActivityMetrics?
    
    init(
        id: UUID = UUID(),
        date: Date,
        distanceKm: Double,
        pace: String,
        routeCoordinates: [CLLocationCoordinate2D],
        metrics: RunActivityMetrics? = nil
    ) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.pace = pace
        self.routeCoordinates = routeCoordinates
        self.metrics = metrics
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
    @EnvironmentObject private var mainTabRouter: MainTabRouter
    @ObservedObject private var activityStore = RunActivityStore.shared
    var entries: [RunHistoryEntry]? = nil
    /// Run タブの `NavigationLink` から開いたときのみ true（MainTabView の「Home」ボタンとナビの戻るが二重になるのを防ぐ）
    var suppressMainTabBackToHomeButton: Bool = false

    private var resolvedEntries: [RunHistoryEntry] {
        if let entries {
            return entries.sorted { $0.date > $1.date }
        }
        let converted = activityStore.activities.map { activity in
            RunHistoryEntry(
                id: activity.id,
                date: activity.startedAt,
                distanceKm: activity.distanceKm,
                pace: activity.paceLabel,
                routeCoordinates: activity.route.map(\.coordinate),
                metrics: activity.metrics
            )
        }
        if converted.isEmpty {
            return sampleRunHistory
        }
        return converted.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            List(resolvedEntries) { entry in
                NavigationLink {
                    RunHistoryDetailView(entry: entry)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(entry.date))
                                .font(.subheadline)
                                .foregroundColor(Color.tasukiPrimary)
                            Text("\(String(format: "%.1f", entry.distanceKm)) km · \(entry.pace)")
                                .font(.caption)
                                .foregroundColor(Color.tasukiMutedText)
                            if let metrics = entry.metrics {
                                Text(activitySupplementarySummary(metrics))
                                    .font(.caption2)
                                    .foregroundColor(Color.tasukiMutedText.opacity(0.85))
                                    .lineLimit(1)
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
        .onAppear {
            if suppressMainTabBackToHomeButton {
                mainTabRouter.suppressBackToHomeOverlay = true
            }
        }
        .onDisappear {
            if suppressMainTabBackToHomeButton {
                mainTabRouter.suppressBackToHomeOverlay = false
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E) HH:mm"
        return f.string(from: date)
    }
    
    private func activitySupplementarySummary(_ metrics: RunActivityMetrics) -> String {
        let cadence: String
        if let v = metrics.averageCadenceSpm, v > 0 {
            cadence = String(format: "平均ピッチ %.0f spm", v)
        } else {
            cadence = "平均ピッチ --"
        }
        let ascent: String
        if let v = metrics.totalAscentMeters {
            ascent = String(format: "上昇 %.0f m", v)
        } else {
            ascent = "上昇 -- m"
        }
        return "\(cadence) ・ \(ascent)"
    }
}

// MARK: - Run History Detail View（地図付き）
struct RunHistoryDetailView: View {
    let entry: RunHistoryEntry
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: DetailTab = .overview
    
    private enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "概要"
        case stats = "統計"
        case laps = "ラップ数"
        case graphs = "グラフ"
        
        var id: String { rawValue }
    }
    
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
        VStack(spacing: 0) {
            tabSelector
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .stats:
                        if let metrics = entry.metrics {
                            detailedMetricsSection(metrics)
                        } else {
                            emptyMetricsState
                        }
                    case .laps:
                        lapsContent
                    case .graphs:
                        graphsContent
                    }
                }
                .padding()
            }
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
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundColor(selectedTab == tab ? Color.tasukiPrimary : Color.tasukiMutedText)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.tasukiPrimary : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.tasukiDarkBackground)
    }
    
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Color.tasukiMutedText)
                Text(formatDate(entry.date))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.tasukiPrimary)
                HStack(spacing: 24) {
                    labelValue(title: "距離", value: "\(String(format: "%.1f", entry.distanceKm)) km")
                    labelValue(title: "平均ペース", value: entry.pace)
                }
                if let metrics = entry.metrics {
                    HStack(spacing: 24) {
                        labelValue(title: "合計タイム", value: formatDuration(metrics.totalTimeSeconds))
                        labelValue(title: "カロリー", value: formatCalories(metrics.caloriesKcal))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tasukiDarkCardSecondary)
            )
            
            RunHistoryMapView(coordinates: entry.routeCoordinates, region: mapRegion)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var lapsContent: some View {
        Group {
            if let laps = entry.metrics?.lapSplits, !laps.isEmpty {
                lapCard(laps: laps)
            } else {
                emptyMetricsState
            }
        }
    }
    
    private var graphsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let metrics = entry.metrics {
                trendGraphCard(
                    title: "ペース推移",
                    color: .blue,
                    values: metrics.lapSplits.map(\.paceSecondsPerKm),
                    minText: formatPace(metrics.bestPaceSecondsPerKm),
                    maxText: formatPace(metrics.averagePaceSecondsPerKm)
                )
                trendGraphCard(
                    title: "高度推移",
                    color: .green,
                    values: metrics.altitudeTrendMeters ?? [],
                    minText: formatMeters(metrics.minAltitudeMeters),
                    maxText: formatMeters(metrics.maxAltitudeMeters)
                )
            } else {
                emptyMetricsState
            }
        }
    }
    
    private var emptyMetricsState: some View {
        Text("このアクティビティには詳細データがありません。")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color.tasukiMutedText)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCardSecondary))
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E) HH:mm"
        return f.string(from: date)
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
    
    @ViewBuilder
    private func detailedMetricsSection(_ metrics: RunActivityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("統計")
                .font(.headline)
                .foregroundColor(Color.tasukiPrimary)
            detailsCard(items: [
                ("移動時間", formatDuration(metrics.movingTimeSeconds)),
                ("経過時間", formatDuration(metrics.elapsedTimeSeconds)),
                ("平均移動ペース", formatPace(metrics.averageMovingPaceSecondsPerKm)),
                ("GAP", formatPace(metrics.gradeAdjustedPaceSecondsPerKm)),
                ("最速ペース", formatPace(metrics.bestPaceSecondsPerKm)),
                ("平均速度", formatSpeed(metrics.averageSpeedKmh)),
                ("最高速度", formatSpeed(metrics.maxSpeedKmh)),
                ("消費カロリー", formatCalories(metrics.caloriesKcal))
            ])
            detailsCard(items: [
                ("走行時間", formatDuration(metrics.runningTimeSeconds)),
                ("ウォーク時間", formatDuration(metrics.walkingTimeSeconds)),
                ("休憩時間", formatDuration(metrics.restTimeSeconds)),
                ("平均ピッチ", formatCadence(metrics.averageCadenceSpm)),
                ("最高ピッチ", formatCadence(metrics.maxCadenceSpm)),
                ("平均ストライド", formatStride(metrics.averageStrideLengthMeters)),
                ("総上昇量", formatMeters(metrics.totalAscentMeters)),
                ("総下降量", formatMeters(metrics.totalDescentMeters)),
                ("最低高度", formatMeters(metrics.minAltitudeMeters)),
                ("最高高度", formatMeters(metrics.maxAltitudeMeters))
            ])
            if !metrics.lapSplits.isEmpty {
                lapCard(laps: metrics.lapSplits)
            }
        }
    }
    
    private func detailsCard(items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { idx in
                let item = items[idx]
                HStack(alignment: .firstTextBaseline) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundColor(Color.tasukiMutedText)
                    Spacer()
                    Text(item.1)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                if idx < items.count - 1 {
                    Divider().overlay(Color.tasukiMutedText.opacity(0.2))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCardSecondary))
    }
    
    private func lapCard(laps: [RunActivityLapSplit]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ラップ（1kmごと）")
                .font(.caption)
                .foregroundColor(Color.tasukiMutedText)
            ForEach(laps, id: \.index) { lap in
                HStack(spacing: 8) {
                    Text("Lap \(lap.index)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(width: 58, alignment: .leading)
                    Text(String(format: "%.2fkm", lap.distanceKm))
                        .font(.caption)
                        .foregroundColor(Color.tasukiMutedText)
                        .frame(width: 60, alignment: .leading)
                    Spacer()
                    Text(formatDuration(lap.durationSeconds))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text(formatPace(lap.paceSecondsPerKm))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCardSecondary))
    }
    
    private func trendGraphCard(
        title: String,
        color: Color,
        values: [Double],
        minText: String,
        maxText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(Color.tasukiPrimary)
            HStack(spacing: 24) {
                labelValue(title: "最小", value: minText)
                labelValue(title: "最大/平均", value: maxText)
            }
            if values.count >= 2 {
                metricLineGraph(values: values, color: color)
                    .frame(height: 150)
            } else {
                Text("データ不足")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCardSecondary))
    }
    
    private func metricLineGraph(values: [Double], color: Color) -> some View {
        GeometryReader { geo in
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 1
            let range = max(maxV - minV, 0.0001)
            let width = geo.size.width
            let height = geo.size.height
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let normalized = (value - minV) / range
                    let y = height - (CGFloat(normalized) * height)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func formatDuration(_ sec: TimeInterval?) -> String {
        guard let sec, sec > 0 else { return "--:--" }
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
    
    private func formatPace(_ secPerKm: Double?) -> String {
        guard let secPerKm, secPerKm > 0 else { return "--:--/km" }
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d/km", m, s)
    }
    
    private func formatSpeed(_ kmh: Double?) -> String {
        guard let kmh, kmh > 0 else { return "--.- km/h" }
        return String(format: "%.1f km/h", kmh)
    }
    
    private func formatCalories(_ kcal: Int?) -> String {
        guard let kcal, kcal > 0 else { return "-- kcal" }
        return "\(kcal) kcal"
    }
    
    private func formatCadence(_ spm: Double?) -> String {
        guard let spm, spm > 0 else { return "-- spm" }
        return String(format: "%.0f spm", spm)
    }
    
    private func formatStride(_ meters: Double?) -> String {
        guard let meters, meters > 0 else { return "-- m" }
        return String(format: "%.2f m", meters)
    }
    
    private func formatMeters(_ meters: Double?) -> String {
        guard let meters else { return "-- m" }
        return String(format: "%.0f m", meters)
    }
}

// MARK: - Map View（ルート線を描画）
struct RunHistoryMapView: View {
    let coordinates: [CLLocationCoordinate2D]
    let region: MKCoordinateRegion

    private var displayCoordinates: [CLLocationCoordinate2D] {
        smoothCoordinates(coordinates)
    }
    
    var body: some View {
        Map(initialPosition: .region(region), interactionModes: .all) {
            if displayCoordinates.count >= 2 {
                MapPolyline(coordinates: displayCoordinates)
                    .stroke(Color.tasukiAccent, lineWidth: 4)
            }
            ForEach(Array(displayCoordinates.enumerated()), id: \.offset) { index, coord in
                if index == 0 {
                    Annotation("スタート", coordinate: coord) {
                        Image(systemName: "flag.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                } else if index == displayCoordinates.count - 1 {
                    Annotation("ゴール", coordinate: coord) {
                        Image(systemName: "flag.checkered")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private func smoothCoordinates(_ raw: [CLLocationCoordinate2D], window: Int = 5) -> [CLLocationCoordinate2D] {
        guard raw.count >= 3 else { return raw }
        let radius = max(1, window / 2)
        var smoothed = raw
        for i in 1..<(raw.count - 1) {
            let start = max(0, i - radius)
            let end = min(raw.count - 1, i + radius)
            let segment = raw[start...end]
            let lat = segment.reduce(0.0) { $0 + $1.latitude } / Double(segment.count)
            let lon = segment.reduce(0.0) { $0 + $1.longitude } / Double(segment.count)
            smoothed[i] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        smoothed[0] = raw[0]
        smoothed[raw.count - 1] = raw[raw.count - 1]
        return smoothed
    }
}

#Preview("走行履歴一覧") {
    RunHistoryListView()
        .environmentObject(MainTabRouter())
}

#Preview("走行詳細") {
    NavigationStack {
        RunHistoryDetailView(entry: sampleRunHistory[0])
    }
}
