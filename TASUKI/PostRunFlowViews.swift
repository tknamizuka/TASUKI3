import SwiftUI
import MapKit
import CoreLocation

// MARK: - Draft

/// 走行終了直後、保存前に保持する計測データ（走行記録フロー用）
struct RunFinishDraft: Identifiable {
    let id = UUID()
    let endedAt: Date
    let distanceKm: Double
    let durationSeconds: TimeInterval
    let routeCoordinates: [CLLocationCoordinate2D]
    let metrics: RunActivityMetrics?
}

// MARK: - Root flow

struct PostRunFlowView: View {
    let draft: RunFinishDraft
    let onActivitySavedAndDismiss: ((RunActivity) -> Void)?
    @EnvironmentObject private var activityStore: RunActivityStore
    @EnvironmentObject private var mainTabRouter: MainTabRouter
    @Environment(\.dismiss) private var dismiss

    @State private var phase: PostRunPhase = .save
    @State private var savedActivity: RunActivity?

    init(
        draft: RunFinishDraft,
        onActivitySavedAndDismiss: ((RunActivity) -> Void)? = nil
    ) {
        self.draft = draft
        self.onActivitySavedAndDismiss = onActivitySavedAndDismiss
    }

    private enum PostRunPhase: Equatable {
        case save
        case celebration
        case review
    }

    var body: some View {
        Group {
            switch phase {
            case .save:
                PostRunActivitySaveView(draft: draft) { activity in
                    savedActivity = activity
                    if let onActivitySavedAndDismiss {
                        onActivitySavedAndDismiss(activity)
                        dismiss()
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.28)) {
                        phase = .celebration
                    }
                } onCancel: {
                    dismiss()
                }
            case .celebration:
                PostRunCelebrationView {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        phase = .review
                    }
                }
            case .review:
                if let activity = savedActivity {
                    NavigationStack {
                        PostRunActivityReviewView(
                            activity: activity,
                            onDismissFlow: {
                                dismiss()
                            },
                            onGoHome: {
                                mainTabRouter.selectedTab = 0
                                dismiss()
                            },
                            onUpdateActivity: { updated in
                                savedActivity = updated
                            }
                        )
                    }
                } else {
                    Color.tasukiDarkBackground.ignoresSafeArea()
                }
            }
        }
    }
}

// MARK: - Save

private struct PostRunActivitySaveView: View {
    let draft: RunFinishDraft
    let onSaved: (RunActivity) -> Void
    let onCancel: () -> Void

    @ObservedObject private var activityStore = RunActivityStore.shared
    @State private var titleText: String = ""
    @State private var commentText: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(String(format: "%.2f km · %@", draft.distanceKm, formatDuration(draft.durationSeconds)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.tasukiMutedText)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("題名")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        TextField("例: 朝の皇居ラン", text: $titleText)
                            .font(.system(size: 16))
                            .foregroundColor(Color.tasukiPrimary)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCard))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("コメント")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        TextField("今日の走りのメモ", text: $commentText, axis: .vertical)
                            .font(.system(size: 16))
                            .foregroundColor(Color.tasukiPrimary)
                            .lineLimit(4...10)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCard))
                    }

                    Button {
                        save()
                    } label: {
                        Text("保存")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.tasukiBase.ignoresSafeArea())
            .navigationTitle("アクティビティを保存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        onCancel()
                    }
                    .foregroundColor(Color.tasukiAccentOrange)
                }
            }
        }
    }

    private func save() {
        let titleTrim = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteTrim = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let activity = activityStore.addActivity(
            distanceKm: draft.distanceKm,
            durationSeconds: draft.durationSeconds,
            routeCoordinates: draft.routeCoordinates,
            source: "run_recorder",
            endedAt: draft.endedAt,
            title: titleTrim.isEmpty ? nil : titleTrim,
            note: noteTrim.isEmpty ? nil : noteTrim,
            perceivedEffort: nil,
            postRunMood: nil,
            metrics: draft.metrics
        )
        let earnedPoints = max(20, Int(activity.distanceKm * 12))
        PointService.shared.addPointsToCurrentUser(
            amount: earnedPoints,
            actionId: "run_activity:\(activity.id.uuidString)"
        )
        onSaved(activity)
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Celebration

private struct PostRunCelebrationView: View {
    let onContinue: () -> Void

    private let subline = "今日の積み重ねが、次のレースにつながります。"

    @State private var headlineShown = false
    @State private var headlineNudge = false
    @State private var sublineShown = false
    @State private var buttonShown = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)
            VStack(spacing: 12) {
                Text("Nice Run!")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundColor(Color.tasukiPrimary)
                    .shadow(
                        color: Color.tasukiBrandYellow.opacity(headlineShown ? 0.35 : 0),
                        radius: headlineShown ? 14 : 0,
                        y: 2
                    )
                    .scaleEffect(headlineShown ? (headlineNudge ? 1.07 : 1.0) : 0.38)
                    .opacity(headlineShown ? 1 : 0)
                Text(subline)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .offset(y: sublineShown ? 0 : 10)
                    .opacity(sublineShown ? 1 : 0)
            }
            Spacer()
            Button {
                onContinue()
            } label: {
                Text("振り返りへ")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiPrimaryButtonFill))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .offset(y: buttonShown ? 0 : 24)
            .opacity(buttonShown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.68)) {
                headlineShown = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) {
                    headlineNudge = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) {
                        headlineNudge = false
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.45)) {
                    sublineShown = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                    buttonShown = true
                }
            }
        }
    }
}

// MARK: - Review

private struct PostRunActivityReviewView: View {
    @ObservedObject private var activityStore = RunActivityStore.shared
    @State private var activity: RunActivity
    let onDismissFlow: () -> Void
    let onGoHome: () -> Void
    let onUpdateActivity: (RunActivity) -> Void

    @State private var showEditSheet = false
    @State private var selectedTab: DetailTab = .overview

    private enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "概要"
        case stats = "統計"
        case laps = "ラップ数"
        case graphs = "グラフ"

        var id: String { rawValue }
    }

    init(
        activity: RunActivity,
        onDismissFlow: @escaping () -> Void,
        onGoHome: @escaping () -> Void,
        onUpdateActivity: @escaping (RunActivity) -> Void
    ) {
        _activity = State(initialValue: activity)
        self.onDismissFlow = onDismissFlow
        self.onGoHome = onGoHome
        self.onUpdateActivity = onUpdateActivity
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        activity.route.map(\.coordinate)
    }
    
    private var metrics: RunActivityMetrics? {
        activity.metrics
    }

    private var mapRegion: MKCoordinateRegion {
        guard !routeCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        let minLat = routeCoordinates.map(\.latitude).min() ?? 35.68
        let maxLat = routeCoordinates.map(\.latitude).max() ?? 35.68
        let minLon = routeCoordinates.map(\.longitude).min() ?? 139.76
        let maxLon = routeCoordinates.map(\.longitude).max() ?? 139.76
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .stats:
                        if let metrics {
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
                .padding(20)
            }
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("振り返り")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onGoHome()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.tasukiAccentOrange)
                }
                .accessibilityLabel("ホームへ戻る")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    onDismissFlow()
                } label: {
                    Text("閉じる")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiAccentOrange)
                }
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("題名・コメントを編集", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PostRunActivityEditSheet(activity: activity) { updated in
                activity = updated
                onUpdateActivity(updated)
            }
        }
        .onAppear {
            syncActivityFromStore()
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
            VStack(alignment: .leading, spacing: 10) {
                Text("ACTIVITY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Color.tasukiMutedText)
                Text(formatDate(activity.startedAt))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
                if let t = activity.title, !t.isEmpty {
                    Text(t)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                HStack(spacing: 16) {
                    reviewStat(title: "距離", value: String(format: "%.2f km", activity.distanceKm))
                    reviewStat(title: "平均ペース", value: activity.paceLabel)
                }
                HStack(spacing: 16) {
                    reviewStat(title: "合計タイム", value: formatDuration(activity.durationSeconds))
                    reviewStat(title: "カロリー", value: formatCalories(metrics?.caloriesKcal))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiDarkCardSecondary))
            
            RunHistoryMapView(coordinates: routeCoordinates, region: mapRegion)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if let note = activity.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 15))
                    .foregroundColor(Color.tasukiPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiDarkCard))
            }
        }
    }

    private var lapsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let laps = metrics?.lapSplits, !laps.isEmpty {
                lapSplitsCard(laps)
            } else {
                emptyMetricsState
            }
        }
    }

    private var graphsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let metrics {
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

    private func syncActivityFromStore() {
        if let latest = activityStore.activities.first(where: { $0.id == activity.id }) {
            activity = latest
        }
    }

    private func reviewStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func detailedMetricsSection(_ metrics: RunActivityMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("統計")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.tasukiMutedText)
            
            detailedGridCard(items: [
                ("移動時間", formatDuration(metrics.movingTimeSeconds)),
                ("経過時間", formatDuration(metrics.elapsedTimeSeconds)),
                ("平均移動ペース", formatPace(metrics.averageMovingPaceSecondsPerKm)),
                ("GAP", formatPace(metrics.gradeAdjustedPaceSecondsPerKm)),
                ("最速ペース", formatPace(metrics.bestPaceSecondsPerKm)),
                ("平均速度", formatSpeed(metrics.averageSpeedKmh)),
                ("最高速度", formatSpeed(metrics.maxSpeedKmh)),
                ("消費カロリー", formatCalories(metrics.caloriesKcal))
            ])
            
            detailedGridCard(items: [
                ("走行時間", formatDuration(metrics.runningTimeSeconds)),
                ("ウォーク時間", formatDuration(metrics.walkingTimeSeconds)),
                ("休憩時間", formatDuration(metrics.restTimeSeconds)),
                ("平均ピッチ", formatCadence(metrics.averageCadenceSpm)),
                ("最高ピッチ", formatCadence(metrics.maxCadenceSpm)),
                ("平均ストライド", formatStride(metrics.averageStrideLengthMeters))
            ])
            
            detailedGridCard(items: [
                ("総上昇量", formatMeters(metrics.totalAscentMeters)),
                ("総下降量", formatMeters(metrics.totalDescentMeters)),
                ("最低高度", formatMeters(metrics.minAltitudeMeters)),
                ("最高高度", formatMeters(metrics.maxAltitudeMeters))
            ])
            
            if !metrics.lapSplits.isEmpty {
                lapSplitsCard(metrics.lapSplits)
            }
        }
    }
    
    private func detailedGridCard(items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { idx in
                let item = items[idx]
                HStack(alignment: .firstTextBaseline) {
                    Text(item.0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.tasukiMutedText)
                    Spacer()
                    Text(item.1)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                if idx < items.count - 1 {
                    Divider().overlay(Color.tasukiMutedText.opacity(0.2))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCardSecondary))
    }
    
    private func lapSplitsCard(_ laps: [RunActivityLapSplit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ラップ（1kmごと）")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)
            ForEach(laps, id: \.index) { lap in
                HStack(spacing: 8) {
                    Text("Lap \(lap.index)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(width: 58, alignment: .leading)
                    Text(String(format: "%.2fkm", lap.distanceKm))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.tasukiMutedText)
                        .frame(width: 62, alignment: .leading)
                    Spacer()
                    Text(formatDuration(lap.durationSeconds))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                    Text(formatPace(lap.paceSecondsPerKm))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(width: 72, alignment: .trailing)
                }
                Divider().overlay(Color.tasukiMutedText.opacity(0.18))
            }
        }
        .padding(14)
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
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.tasukiMutedText)
            HStack(spacing: 24) {
                reviewStat(title: "最小", value: minText)
                reviewStat(title: "最大/平均", value: maxText)
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
        .padding(14)
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

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(E) HH:mm"
        return f.string(from: date)
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        guard sec > 0 else { return "--:--" }
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
    
    private func formatDuration(_ sec: TimeInterval?) -> String {
        guard let sec else { return "--:--" }
        return formatDuration(sec)
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

// MARK: - Edit sheet

private struct PostRunActivityEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var activityStore = RunActivityStore.shared
    @State private var titleText: String
    @State private var commentText: String
    private let activityId: UUID
    let onSaved: (RunActivity) -> Void

    init(activity: RunActivity, onSaved: @escaping (RunActivity) -> Void) {
        activityId = activity.id
        _titleText = State(initialValue: activity.title ?? "")
        _commentText = State(initialValue: activity.note ?? "")
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("題名")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        TextField("題名", text: $titleText)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCard))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("コメント")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        TextField("コメント", text: $commentText, axis: .vertical)
                            .lineLimit(4...10)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCard))
                    }
                    Button {
                        let t = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let n = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
                        activityStore.updateActivityTitleNote(id: activityId, title: t.isEmpty ? nil : t, note: n.isEmpty ? nil : n)
                        if let updated = activityStore.activities.first(where: { $0.id == activityId }) {
                            onSaved(updated)
                        }
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Color.tasukiBase.ignoresSafeArea())
            .navigationTitle("アクティビティを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
