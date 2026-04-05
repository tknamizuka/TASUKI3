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
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        titleCard
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 20)

                        metricCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        mapCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)

                        actionButtons
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)

                        activityGraphCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)

                        recentActivitiesCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
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
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiPrimaryButtonFill))
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
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
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
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.tasukiMutedText.opacity(0.18))
                    .frame(height: 1)
            }

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
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(Color.tasukiPrimaryButtonFill))
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
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(Color.tasukiPrimaryButtonFill))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RUN RECORDER")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            Text("GPSで記録して履歴・チャレンジに反映")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                metricItem(title: "距離", value: String(format: "%.2f", tracker.distanceKm), unit: "km")
                metricItem(title: "時間", value: formatDuration(elapsedSeconds), unit: "")
                metricItem(title: "ペース", value: currentPaceText.replacingOccurrences(of: "/km", with: ""), unit: "/km")
            }
            Rectangle()
                .fill(Color.tasukiMutedText.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ルート")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            Map(initialPosition: .region(mapRegion), interactionModes: .all) {
                if routeCoordinates.count >= 2 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(Color.tasukiAccent, lineWidth: 4)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .tasukiFlatCard()
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if tracker.isTracking {
                Button {
                    finishAndSave()
                } label: {
                    Text("走行を終了して保存")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.tasukiOnBrandYellow)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
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
                        .foregroundColor(Color.tasukiOnBrandYellow)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentActivitiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近のアクティビティ")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Color.tasukiMutedText)
                Spacer()
                NavigationLink(destination: RunHistoryListView()) {
                    Text("すべて見る")
                        .font(.caption)
                        .foregroundColor(Color.tasukiAccent)
                }
            }
            .padding(.bottom, 12)

            if activityStore.activities.isEmpty {
                Text("まだ記録がありません。走行を開始して最初のアクティビティを作成しましょう。")
                    .font(.footnote)
                    .foregroundColor(Color.tasukiMutedText)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(activityStore.activities.prefix(3).enumerated()), id: \.element.id) { index, activity in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.tasukiMutedText.opacity(0.18))
                            .frame(height: 1)
                    }
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
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var activityGraphCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("活動推移")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    trendStat(title: "今週距離", value: String(format: "%.1f km", weeklyDistanceKm()))
                    trendStat(title: "今週回数", value: "\(activityStore.weeklyRunCount()) 回")
                    trendStat(title: "今月距離", value: String(format: "%.1f km", activityStore.monthlyDistanceKm()))
                }

                TasukiWeeklyActivityLineChart(points: activityStore.weeklyActivityChartPoints())
                    .frame(height: 190)
                    .padding(.horizontal, 4)
            }
            .tasukiFlatCard()
        }
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

    private func weeklyDistanceKm() -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let weekRange = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return activityStore.activities
            .filter { weekRange.contains($0.startedAt) }
            .reduce(0) { $0 + $1.distanceKm }
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

#Preview {
    NavigationStack {
        RunRecordingView()
    }
}
