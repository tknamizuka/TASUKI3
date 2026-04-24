import SwiftUI
import MapKit
import Combine
import CoreLocation

struct RunRecordingView: View {
    @ObservedObject private var tracker = RunTracker.shared
    @ObservedObject private var activityStore = RunActivityStore.shared
    @ObservedObject private var qaStore = CoachQAStore.shared
    @EnvironmentObject private var coachCertification: CoachCertificationManager
    @EnvironmentObject private var mainTabRouter: MainTabRouter
    @AppStorage("myName") private var myName: String = "Hiro"
    /// 0 のときは推定に 65kg を使う
    @AppStorage("runnerWeightKg") private var runnerWeightKg: Double = 0

    @State private var now = Date()
    @State private var trackingMapCamera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )
    @State private var postRunDraft: RunFinishDraft?
    @State private var navigateToCoach = false
    /// 走行開始直後は false。黄帯を下にスワイプすると true になり地図表示＋ヘッダー折りたたみ
    @State private var isTrackingMapExpanded = false

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
    
    /// 体重×距離のおおよその消費 kcal（走行中の目安）
    private var estimatedCaloriesKcal: Int {
        let kg = runnerWeightKg > 0 ? runnerWeightKg : 65.0
        return max(0, Int((tracker.distanceKm * kg * 1.036).rounded()))
    }
    
    /// 記録中画面の地図用リージョン（ルート＋現在地を含む）
    private var trackingLiveMapRegion: MKCoordinateRegion {
        var coords = routeCoordinates
        if let last = tracker.lastKnownCoordinate {
            if coords.isEmpty || coords.last?.latitude != last.latitude || coords.last?.longitude != last.longitude {
                coords.append(last)
            }
        }
        guard let first = coords.first else {
            let c = tracker.lastKnownCoordinate ?? CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
            return MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.45, 0.006),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.45, 0.006)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// 自分宛てでコーチ回答済みの Q&A のうち、最新（サンプル＋保存済みを合算）。
    private var latestAnsweredQAForHub: QAItem? {
        let answered =
            qaStore.items.filter { $0.askerName == myName && $0.answer != nil }
            + coachPersonalSampleQAItems.filter { $0.askerName == myName && $0.answer != nil }
        return answered.max(by: { $0.postedDate < $1.postedDate })
    }

    /// COACH 行右側サムネイル用の短文。
    private var coachHubReplySnippet: String? {
        guard let text = latestAnsweredQAForHub?.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let maxChars = 100
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars)) + "…"
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        titleCard
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 20)

                        Button {
                            // #region agent log
                            AgentDebugLog.log(
                                location: "RunRecordingView.coachLink.tap",
                                message: "coach_link_tapped",
                                hypothesisId: "C1",
                                data: [
                                    "hasReplySnippet": "\(coachHubReplySnippet != nil)",
                                    "isCertifiedCoach": "\(coachCertification.isCertifiedCoach)"
                                ]
                            )
                            // #endregion
                            navigateToCoach = true
                        } label: {
                            TasukiFlatHubRow(
                                title: "COACH",
                                subtitle: "パーソナルコーチ",
                                systemImage: "graduationcap.fill",
                                iconForegroundColor: Color.tasukiAccent,
                                replySnippet: coachHubReplySnippet
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
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
        .navigationTitle(tracker.isTracking ? "" : "Run")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(RunRecordingNavigationBarHiddenModifier(isHidden: tracker.isTracking))
        .onChange(of: tracker.isTracking) { _, isOn in
            if isOn {
                isTrackingMapExpanded = false
            }
        }
        .navigationDestination(isPresented: $navigateToCoach) {
            CoachView(embedNavigationStack: false)
                .onAppear {
                    // #region agent log
                    AgentDebugLog.log(
                        location: "RunRecordingView.coachNavigationDestination",
                        message: "coach_destination_onAppear",
                        hypothesisId: "C5",
                        data: ["runId": "post-fix"]
                    )
                    // #endregion
                }
        }
        .onReceive(elapsedTimer) { now = $0 }
        .onAppear {
            // #region agent log
            AgentDebugLog.log(
                location: "RunRecordingView.onAppear",
                message: "run_screen_appeared",
                hypothesisId: "C4",
                data: [
                    "qaCount": "\(qaStore.items.count)",
                    "hasReplySnippet": "\(coachHubReplySnippet != nil)"
                ]
            )
            // #endregion
            activityStore.refreshFromRemote()
        }
        .fullScreenCover(item: $postRunDraft) { draft in
            PostRunFlowView(draft: draft)
                .environmentObject(activityStore)
                .environmentObject(mainTabRouter)
        }
    }

    private var trackingFocusedView: some View {
        VStack(spacing: 0) {
            Group {
                if isTrackingMapExpanded {
                    trackingCompactYellowBar
                } else {
                    VStack(spacing: 0) {
                        trackingExpandedYellowHeaderOnly
                        Spacer(minLength: 0)
                        trackingStatsBlock
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isTrackingMapExpanded)

            if isTrackingMapExpanded {
                trackingMapFillContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.tasukiPrimaryButtonFill))
                }
                .buttonStyle(.plain)

                Button {
                    finishAndPrepareDraft()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                        Text("終了")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.tasukiPrimaryButtonFill))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.tasukiDarkBackground)
        }
        .background(Color.tasukiDarkBackground)
        .onChange(of: now) { _, _ in
            syncTrackingMapCamera()
        }
        .onChange(of: tracker.distanceKm) { _, _ in
            syncTrackingMapCamera()
        }
        .onChange(of: tracker.lastKnownCoordinate?.latitude) { _, _ in
            syncTrackingMapCamera()
        }
        .onChange(of: isTrackingMapExpanded) { _, expanded in
            if expanded {
                syncTrackingMapCamera()
            }
        }
        .onAppear {
            syncTrackingMapCamera()
        }
    }
    
    private func syncTrackingMapCamera() {
        trackingMapCamera = .region(trackingLiveMapRegion)
    }
    
    /// 展開前: 黄帯（画面上端まで）＋下スワイプで地図
    private var trackingExpandedYellowHeaderOnly: some View {
        VStack(spacing: 12) {
            Text("記録中")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundColor(Color.tasukiPrimary.opacity(0.75))
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .center, spacing: 6) {
                    Text("時間")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                    Text(formatDuration(elapsedSeconds))
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.tasukiPrimary.opacity(0.2))
                    .frame(width: 1, height: 56)
                VStack(alignment: .center, spacing: 6) {
                    Text("消費カロリー")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(estimatedCaloriesKcal)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .monospacedDigit()
                        Text("kcal")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("下にスワイプして地図を表示")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Color.tasukiPrimary.opacity(0.55))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            Color.tasukiBrandYellow
                .ignoresSafeArea(edges: .top)
        )
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height > 56 {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            isTrackingMapExpanded = true
                        }
                    }
                }
        )
    }
    
    /// 地図表示時: 時間と平均ペースのみの折りたたみヘッダー
    private var trackingCompactYellowBar: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("時間")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.65))
                Text(formatDuration(elapsedSeconds))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color.tasukiPrimary.opacity(0.2))
                .frame(width: 1, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("平均ペース")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.65))
                Text(currentPaceText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary.opacity(0.45))
                .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .background(
            Color.tasukiBrandYellow
                .ignoresSafeArea(edges: .top)
        )
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -48 {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            isTrackingMapExpanded = false
                        }
                    }
                }
        )
    }
    
    /// 平均速度・距離（黄帯の下）
    private var trackingStatsBlock: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(String(format: "%.1f", averageSpeedKmh))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("平均速度（km/h）")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            HStack(alignment: .top, spacing: 12) {
                trackingCompactMetric(title: "距離", value: String(format: "%.2f", tracker.distanceKm), unit: "km")
                trackingCompactMetric(title: "ペース", value: currentPaceText.replacingOccurrences(of: "/km", with: ""), unit: "/km")
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    private func trackingCompactMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.tasukiMutedText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.tasukiDarkCard)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        )
    }
    
    /// 地図モード時: 残り領域いっぱい。走行軌跡（ポリライン）＋現在地
    private var trackingMapFillContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Map(position: $trackingMapCamera, interactionModes: [.pan, .zoom, .rotate]) {
                    if routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(Color.tasukiAccent, lineWidth: 5)
                    }
                    if let cur = tracker.lastKnownCoordinate {
                        Annotation("現在地", coordinate: cur) {
                            ZStack {
                                Circle()
                                    .fill(Color.tasukiAccent.opacity(0.35))
                                    .frame(width: 24, height: 24)
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 11, height: 11)
                                Circle()
                                    .fill(Color.tasukiAccent)
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.tasukiDarkCardSecondary, lineWidth: 1)
                )

                if tracker.lastKnownCoordinate != nil {
                    Label("GPS", systemImage: "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.tasukiAccent)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
                    finishAndPrepareDraft()
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
                            if let t = activity.title, !t.isEmpty {
                                Text(t)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                    .lineLimit(1)
                            }
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
            Text("Activity")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    trendStat(title: "今週距離", value: String(format: "%.1f km", activityStore.weeklyDistanceKm()))
                    trendStat(title: "今週回数", value: "\(activityStore.weeklyRunCount()) 回")
                    trendStat(title: "今月距離", value: String(format: "%.1f km", activityStore.monthlyDistanceKm()))
                }

                TasukiWeeklyActivityLineChart(
                    points: activityStore.weeklyActivityChartPoints(),
                    runActivities: activityStore.activities
                )
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

    private func finishAndPrepareDraft() {
        let endedAt = Date()
        let distanceKm = tracker.distanceKm
        let durationSeconds = max(tracker.elapsedSeconds(now: now), 1)
        let routeSnapshot = tracker.routeCoordinates
        tracker.stop()
        guard distanceKm >= 0.05 else {
            tracker.reset()
            return
        }
        postRunDraft = RunFinishDraft(
            endedAt: endedAt,
            distanceKm: distanceKm,
            durationSeconds: durationSeconds,
            routeCoordinates: routeSnapshot
        )
        tracker.reset()
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

private struct RunRecordingNavigationBarHiddenModifier: ViewModifier {
    var isHidden: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if isHidden {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        RunRecordingView()
            .environmentObject(CoachCertificationManager.shared)
            .environmentObject(MainTabRouter())
    }
}
