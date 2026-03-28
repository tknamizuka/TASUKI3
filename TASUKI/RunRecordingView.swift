import SwiftUI
import MapKit
import Combine

struct RunRecordingView: View {
    @ObservedObject private var tracker = RunTracker.shared
    @ObservedObject private var activityStore = RunActivityStore.shared

    @State private var now = Date()
    @State private var latestSaved: RunActivity?
    @State private var showSavedToast = false
    @State private var pendingSubjectiveActivityId: UUID?
    @State private var showPostRunSubjective = false
    @State private var draftEffort: Int = 3
    @State private var draftMood: Int = 3

    private let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsedSeconds: TimeInterval {
        tracker.elapsedSeconds(now: now)
    }

    private var currentPaceText: String {
        guard tracker.distanceKm > 0 else { return "--:--/km" }
        let secPerKm = elapsedSeconds / tracker.distanceKm
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d/km", m, s)
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        tracker.routeCoordinates
    }

    private var mapRegion: MKCoordinateRegion {
        guard let first = routeCoordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        let lats = routeCoordinates.map(\.latitude)
        let lons = routeCoordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.008),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.008)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        Group {
            if tracker.isTracking {
                trackingFocusedView
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        titleCard
                        metricCard
                        mapCard
                        actionButtons
                        activityGraphCard
                        recentActivitiesCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(elapsedTimer) { now = $0 }
        .onAppear {
            activityStore.refreshFromRemote()
        }
        .overlay(alignment: .top) {
            if showSavedToast, let latestSaved {
                Text("保存完了: \(String(format: "%.1f", latestSaved.distanceKm))km")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiPrimary))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showPostRunSubjective) {
            postRunSubjectiveSheet
        }
    }

    private var postRunSubjectiveSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("走り終えた今の感覚（任意）")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("スキップしても記録は残ります")
                    .font(.subheadline)
                    .foregroundColor(Color.tasukiMutedText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("きつさ \(draftEffort) / 5")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.tasukiPrimary)
                    Slider(value: Binding(
                        get: { Double(draftEffort) },
                        set: { draftEffort = Int($0.rounded()) }
                    ), in: 1...5, step: 1)
                    .tint(Color.tasukiAccent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("気分 \(draftMood) / 5")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.tasukiPrimary)
                    Slider(value: Binding(
                        get: { Double(draftMood) },
                        set: { draftMood = Int($0.rounded()) }
                    ), in: 1...5, step: 1)
                    .tint(Color.tasukiAccentOrange)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button("スキップ") {
                        showPostRunSubjective = false
                        pendingSubjectiveActivityId = nil
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.tasukiDarkCardSecondary, lineWidth: 1)
                    )

                    Button("保存") {
                        if let id = pendingSubjectiveActivityId {
                            activityStore.updateActivitySubjective(
                                id: id,
                                perceivedEffort: draftEffort,
                                postRunMood: draftMood
                            )
                        }
                        showPostRunSubjective = false
                        pendingSubjectiveActivityId = nil
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimary))
                }
            }
            .padding(20)
            .background(Color.tasukiBase.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        showPostRunSubjective = false
                        pendingSubjectiveActivityId = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var trackingFocusedView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("自動停止")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text(formatDuration(elapsedSeconds))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(Color.tasukiSurface)

            Spacer(minLength: 18)

            Text(String(format: "%.1f", averageSpeedKmh))
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .foregroundColor(Color.tasukiPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("平均速度 (km/時)")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)

            Spacer(minLength: 24)

            HStack(spacing: 18) {
                trackingValueCard(value: String(format: "%.2f", tracker.distanceKm), unit: "距離 (km)")
                trackingValueCard(value: String(format: "%.0f", tracker.elevationGainMeters), unit: "獲得標高 (m)")
            }

            trackingValueCard(value: String(format: "%.0f", tracker.currentAltitudeMeters), unit: "現在の標高 (m)")
                .padding(.top, 6)

            Spacer()

            HStack(spacing: 14) {
                Button {
                    if tracker.isPaused {
                        tracker.resume()
                    } else {
                        tracker.pause()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tracker.isPaused ? "play.fill" : "pause.fill")
                        Text(tracker.isPaused ? "再開" : "一時停止")
                    }
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(Color.tasukiAccentOrange))
                }
                .buttonStyle(.plain)

                Button {
                    finishAndSave()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                        Text("終了")
                    }
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(Color.tasukiPrimary))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RUN RECORDER")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(Color.tasukiMutedText)
                .tracking(1.5)
            Text("GPSで記録して履歴・チャレンジに反映")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tasukiCard()
    }

    private var metricCard: some View {
        HStack(spacing: 12) {
            metricItem(title: "距離", value: String(format: "%.2f", tracker.distanceKm), unit: "km")
            metricItem(title: "時間", value: formatDuration(elapsedSeconds), unit: "")
            metricItem(title: "ペース", value: currentPaceText.replacingOccurrences(of: "/km", with: ""), unit: "/km")
        }
        .tasukiCard()
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ルート")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
            Map(initialPosition: .region(mapRegion), interactionModes: .all) {
                if routeCoordinates.count >= 2 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(Color.tasukiAccent, lineWidth: 4)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .tasukiCard()
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if tracker.isTracking {
                Button {
                    finishAndSave()
                } label: {
                    Text("走行を終了して保存")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiAccent))
                }
                .buttonStyle(.plain)

                Button {
                    tracker.stop()
                    tracker.reset()
                } label: {
                    Text("保存せずに破棄")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.tasukiDarkCardSecondary, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    tracker.start()
                    now = Date()
                } label: {
                    Text("走行を開始")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimary))
                }
                .buttonStyle(.plain)
            }
        }
        .tasukiCard()
    }

    private var recentActivitiesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近のアクティビティ")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Spacer()
                NavigationLink(destination: RunHistoryListView()) {
                    Text("すべて見る")
                        .font(.caption)
                        .foregroundColor(Color.tasukiAccent)
                }
            }
            if activityStore.activities.isEmpty {
                Text("まだ記録がありません。走行を開始して最初のアクティビティを作成しましょう。")
                    .font(.footnote)
                    .foregroundColor(Color.tasukiMutedText)
            } else {
                ForEach(Array(activityStore.activities.prefix(3))) { activity in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(formatDate(activity.startedAt))
                                .font(.caption)
                                .foregroundColor(Color.tasukiMutedText)
                            Text("\(String(format: "%.1f", activity.distanceKm))km · \(activity.paceLabel)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.tasukiPrimary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .tasukiCard()
    }

    private var activityGraphCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("活動推移")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)

            HStack(spacing: 12) {
                trendStat(title: "今週距離", value: String(format: "%.1f km", weeklyDistanceKm()))
                trendStat(title: "今週回数", value: "\(activityStore.weeklyRunCount()) 回")
                trendStat(title: "今月距離", value: String(format: "%.1f km", activityStore.monthlyDistanceKm()))
            }

            WeeklyActivityLineChart(points: weeklyActivityPoints)
                .frame(height: 165)
        }
        .tasukiCard()
    }

    private func metricItem(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(Color.tasukiMutedText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(Color.tasukiMutedText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(Color.tasukiMutedText)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var averageSpeedKmh: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return tracker.distanceKm / (elapsedSeconds / 3600.0)
    }

    private func trackingValueCard(value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundColor(Color.tasukiPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)
        }
        .frame(maxWidth: .infinity)
    }

    private var weeklyActivityPoints: [WeeklyActivityPoint] {
        let calendar = Calendar.current
        let now = Date()
        let real = weeklyDistances(weeks: 8, calendar: calendar, now: now)
        if real.contains(where: { $0.distanceKm > 0 }) {
            return real
        }

        let fallbackValues: [Double] = [10.5, 14.8, 9.2, 17.0, 12.6, 18.3, 15.4, 20.1]
        return fallbackValues.enumerated().map { index, value in
            let offset = index - (fallbackValues.count - 1)
            let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            return WeeklyActivityPoint(label: shortWeekLabel(for: weekStart, calendar: calendar), distanceKm: value)
        }
    }

    private func weeklyDistanceKm() -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let weekRange = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return activityStore.activities
            .filter { weekRange.contains($0.startedAt) }
            .reduce(0) { $0 + $1.distanceKm }
    }

    private func weeklyDistances(weeks: Int, calendar: Calendar, now: Date) -> [WeeklyActivityPoint] {
        (0..<weeks).map { idx in
            let offset = idx - (weeks - 1)
            let targetDate = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: targetDate) else {
                return WeeklyActivityPoint(label: shortWeekLabel(for: targetDate, calendar: calendar), distanceKm: 0)
            }
            let distance = activityStore.activities
                .filter { interval.contains($0.startedAt) }
                .reduce(0) { $0 + $1.distanceKm }
            return WeeklyActivityPoint(
                label: shortWeekLabel(for: targetDate, calendar: calendar),
                distanceKm: distance
            )
        }
    }

    private func shortWeekLabel(for date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }

    private func finishAndSave() {
        tracker.stop()
        guard tracker.distanceKm >= 0.05 else {
            tracker.reset()
            return
        }
        let activity = activityStore.addActivity(
            distanceKm: tracker.distanceKm,
            durationSeconds: max(elapsedSeconds, 1),
            routeCoordinates: tracker.routeCoordinates,
            source: "run_recorder"
        )
        let earnedPoints = max(20, Int(activity.distanceKm * 12))
        PointService.shared.addPointsToCurrentUser(amount: earnedPoints)
        tracker.reset()
        latestSaved = activity
        draftEffort = 3
        draftMood = 3
        pendingSubjectiveActivityId = activity.id
        showPostRunSubjective = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showSavedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSavedToast = false
            }
        }
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

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }
}

private struct WeeklyActivityPoint: Identifiable {
    let id = UUID()
    let label: String
    let distanceKm: Double
}

private struct WeeklyActivityLineChart: View {
    let points: [WeeklyActivityPoint]

    private var maxY: Double {
        max(points.map(\.distanceKm).max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let leftPadding: CGFloat = 30
            let bottomPadding: CGFloat = 24
            let topPadding: CGFloat = 10
            let plotWidth = max(1, width - leftPadding)
            let plotHeight = max(1, height - bottomPadding - topPadding)
            let count = max(points.count, 2)

            ZStack {
                ForEach(0..<4, id: \.self) { row in
                    let ratio = CGFloat(row) / 3
                    let y = topPadding + plotHeight * ratio
                    Path { path in
                        path.move(to: CGPoint(x: leftPadding, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                        let normalized = CGFloat(point.distanceKm / maxY)
                        let y = topPadding + (1 - normalized) * plotHeight
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.tasukiAccentOrange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                    let normalized = CGFloat(point.distanceKm / maxY)
                    let y = topPadding + (1 - normalized) * plotHeight

                    Circle()
                        .fill(Color.tasukiAccentOrange)
                        .frame(width: 7, height: 7)
                        .position(x: x, y: y)

                    Text(point.label)
                        .font(.system(size: 10))
                        .foregroundColor(Color.tasukiMutedText)
                        .position(x: x, y: height - 10)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%.0fkm", maxY))
                        .font(.system(size: 10))
                        .foregroundColor(Color.tasukiMutedText)
                    Spacer()
                    Text("0km")
                        .font(.system(size: 10))
                        .foregroundColor(Color.tasukiMutedText)
                }
                .padding(.top, topPadding - 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiSurface)
        )
    }
}

#Preview {
    NavigationStack {
        RunRecordingView()
    }
}
