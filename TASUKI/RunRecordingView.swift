import SwiftUI
import MapKit
import Combine
import CoreLocation

struct RunRecordingView: View {
    let onEkidenActivitySaved: ((RunActivity) -> Void)?
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
    /// 走行開始前のルートカード用（現在地に追従）
    @State private var idleMapCamera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    @State private var postRunDraft: RunFinishDraft?
    @State private var navigateToCoach = false
    /// 記録中: 背面マップの上に載るシートの高さ比率。最大＝デフォルトの記録主体画面（上端にマップが細く見える）、最小＝折りたたみ。スナップはこの二段階のみ。
    @State private var recordingSheetFraction: CGFloat = 0.94
    @State private var recordingSheetDragStartFraction: CGFloat?
    /// 「走行を開始」後の 3→2→1。nil のときは表示しない。
    @State private var runStartCountdownPhase: Int? = nil
    @State private var runStartCountdownTask: Task<Void, Never>? = nil

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

    /// 記録中画面の地図用リージョン（現在地を中心に追従）
    private var trackingLiveMapRegion: MKCoordinateRegion {
        if let current = tracker.lastKnownCoordinate {
            return MKCoordinateRegion(
                center: current,
                span: MKCoordinateSpan(latitudeDelta: 0.0065, longitudeDelta: 0.0065)
            )
        }
        guard let first = routeCoordinates.first else {
            let c = tracker.lastKnownCoordinate ?? CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
            return MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008))
        }
        let lats = routeCoordinates.map(\.latitude)
        let lons = routeCoordinates.map(\.longitude)
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

    private func syncIdleMapCameraFromTracker() {
        guard !tracker.isTracking else { return }
        let fallback = CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76)
        let center = tracker.lastKnownCoordinate ?? fallback
        let span = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        idleMapCamera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func requestCurrentLocationOnIdleMap() {
        tracker.startMapPreviewLocationUpdates()
        syncIdleMapCameraFromTracker()
    }

    var body: some View {
        ZStack {
            Group {
                if tracker.isTracking {
                    trackingFocusedView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            TasukiBrandedHeroHeader(title: "RUN", compactToolbarStyle: true)
                            runHeroTagline
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)

                            primaryStartRunButton
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)

                            Button {
                                AgentDebugLog.log(
                                    location: "RunRecordingView.coachLink.tap",
                                    message: "coach_link_tapped",
                                    hypothesisId: "C1",
                                    data: [
                                        "hasReplySnippet": "\(coachHubReplySnippet != nil)",
                                        "isCertifiedCoach": "\(coachCertification.isCertifiedCoach)"
                                    ]
                                )
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

                            recentActivitiesCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)

                            mapCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)

                            activityGraphCard
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }
                    }
                }
            }
            if let phase = runStartCountdownPhase {
                runStartCountdownOverlay(phase: phase)
            }
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(RunRecordingNavigationBarHiddenModifier(isHidden: tracker.isTracking))
        .onChange(of: tracker.isTracking) { _, isOn in
            if isOn {
                recordingSheetFraction = recordingSheetMaxFraction
            } else {
                tracker.startMapPreviewLocationUpdates()
                syncIdleMapCameraFromTracker()
            }
        }
        .onChange(of: tracker.lastKnownCoordinate?.latitude) { _, _ in
            if !tracker.isTracking {
                syncIdleMapCameraFromTracker()
            }
        }
        .navigationDestination(isPresented: $navigateToCoach) {
            CoachView(embedNavigationStack: false)
                .onAppear {
                    AgentDebugLog.log(
                        location: "RunRecordingView.coachNavigationDestination",
                        message: "coach_destination_onAppear",
                        hypothesisId: "C5",
                        data: ["runId": "post-fix"]
                    )
                }
        }
        .onReceive(elapsedTimer) { now = $0 }
        .onAppear {
            AgentDebugLog.log(
                location: "RunRecordingView.onAppear",
                message: "run_screen_appeared",
                hypothesisId: "C4",
                data: [
                    "qaCount": "\(qaStore.items.count)",
                    "hasReplySnippet": "\(coachHubReplySnippet != nil)"
                ]
            )
            activityStore.refreshFromRemote()
            if !tracker.isTracking {
                tracker.startMapPreviewLocationUpdates()
                syncIdleMapCameraFromTracker()
            }
        }
        .onDisappear {
            runStartCountdownTask?.cancel()
            runStartCountdownTask = nil
            runStartCountdownPhase = nil
            tracker.stopMapPreviewLocationUpdates()
        }
        .fullScreenCover(item: $postRunDraft) { draft in
            PostRunFlowView(draft: draft, onActivitySavedAndDismiss: onEkidenActivitySaved)
                .environmentObject(activityStore)
                .environmentObject(mainTabRouter)
        }
    }

    private var trackingFocusedView: some View {
        GeometryReader { geo in
            let totalH = geo.size.height
            let safeBottom = geo.safeAreaInsets.bottom
            let bottomControlsHeight: CGFloat = 64 + safeBottom
            let contentH = max(120, totalH - bottomControlsHeight)
            let minF = effectiveRecordingSheetMinFraction(contentHeight: contentH)
            let maxF = recordingSheetMaxFraction
            let frac = min(max(recordingSheetFraction, minF), maxF)
            let sheetH = contentH * frac

            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    trackingMapBackgroundLayer(height: contentH, width: geo.size.width, contentHeight: contentH)

                    recordingTrackingSheet(totalHeight: contentH, topSafeInset: geo.safeAreaInsets.top, contentHeight: contentH)
                        .frame(height: sheetH)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .clipped()
                }
                .frame(height: contentH)
                .frame(maxWidth: .infinity)

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
                        .foregroundColor(Color.pureWhite)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Capsule().fill(Color.tasukiPrimary))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.bottom, safeBottom > 0 ? 0 : 8)
                .background(Color.tasukiDarkBackground)
            }
            .frame(width: geo.size.width, height: totalH, alignment: .top)
        }
        .background(Color.tasukiDarkBackground)
        .ignoresSafeArea(edges: .top)
        .onChange(of: now) { _, _ in
            syncTrackingMapCamera()
        }
        .onChange(of: tracker.distanceKm) { _, _ in
            syncTrackingMapCamera()
        }
        .onChange(of: tracker.lastKnownCoordinate?.latitude) { _, _ in
            syncTrackingMapCamera()
        }
        .onChange(of: recordingSheetFraction) { _, _ in
            syncTrackingMapCamera()
        }
        .onAppear {
            syncTrackingMapCamera()
        }
    }

    /// 折りたたみ時コンパクト UI（ハンドル＋黄帯）の目標最小高さ（実際の比率は `recordingSheetCollapsedFractionUpperBound` で頭打ち）
    private let recordingCompactSheetMinimumHeight: CGFloat = 102
    /// 折りたたみでシートが記録エリアを占める比率の上限（これよりマップを広く見せる）
    private let recordingSheetCollapsedFractionUpperBound: CGFloat = 0.20
    /// 極端に低い比率だけは避ける（運動中シートが潰れすぎないための下限）
    private let recordingSheetMinFractionFloor: CGFloat = 0.08
    /// デフォルト展開（画像1: 記録が主役・上端にマップが細く見える）
    private let recordingSheetMaxFraction: CGFloat = 0.94

    private func effectiveRecordingSheetMinFraction(contentHeight: CGFloat) -> CGFloat {
        let intrinsic = recordingCompactSheetMinimumHeight / max(contentHeight, 120)
        let capped = min(intrinsic, recordingSheetCollapsedFractionUpperBound)
        return max(recordingSheetMinFractionFloor, capped)
    }

    /// 二段階 UI の切り替え境界（スナップの中央値と一致）
    private func recordingSheetCollapsedThreshold(contentHeight: CGFloat) -> CGFloat {
        let minF = effectiveRecordingSheetMinFraction(contentHeight: contentHeight)
        return (minF + recordingSheetMaxFraction) / 2
    }

    /// 走行中: 記録シートの下に敷く全幅マップ（常に同じ領域に配置し、シートで覆う／見せる）。
    private func trackingMapBackgroundLayer(height: CGFloat, width: CGFloat, contentHeight: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
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
            .frame(width: width, height: height)
            .allowsHitTesting(recordingSheetFraction < recordingSheetCollapsedThreshold(contentHeight: contentHeight))

            if tracker.lastKnownCoordinate != nil {
                Label("GPS", systemImage: "location.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.tasukiAccent)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .simultaneousGesture(recordingSheetResizeGesture(contentHeight: height))
    }

    private func recordingTrackingSheet(totalHeight: CGFloat, topSafeInset: CGFloat, contentHeight: CGFloat) -> some View {
        /// スナップが二値のため、中央より下なら折りたたみ UI（マップ最大化側）
        let collapsed = recordingSheetFraction < recordingSheetCollapsedThreshold(contentHeight: contentHeight)
        let hintTopPadding = max(topSafeInset, 12)
        return Group {
            if collapsed {
                VStack(spacing: 0) {
                    recordingSheetDragHandleRow(compact: true)
                    recordingCompactYellowStatsBar
                }
            } else {
                VStack(spacing: 0) {
                    recordingSheetDragHandleRow(compact: false)
                        .padding(.top, hintTopPadding)
                    recordingExpandedYellowHeaderBlock
                    trackingStatsBlock
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.tasukiDarkBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 22,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: -6)
        .highPriorityGesture(recordingSheetResizeGesture(contentHeight: totalHeight))
    }

    private func recordingSheetDragHandleRow(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 8) {
            Capsule()
                .fill(Color.tasukiPrimary.opacity(0.28))
                .frame(width: 42, height: 5)
            Text(compact ? "上にスワイプして記録を全画面に" : "下にスワイプしてマップを表示")
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .lineLimit(compact ? 1 : nil)
                .minimumScaleFactor(compact ? 0.78 : 1)
        }
        .padding(.top, compact ? 6 : 0)
        .padding(.bottom, compact ? 4 : 14)
        .frame(maxWidth: .infinity)
    }

    /// パネルを狭めたときの黄帯（時間・ペース）
    private var recordingCompactYellowStatsBar: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("時間")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Color.tasukiPrimary.opacity(0.65))
                Text(formatDuration(elapsedSeconds))
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color.tasukiPrimary.opacity(0.2))
                .frame(width: 1, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text("平均ペース")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Color.tasukiPrimary.opacity(0.65))
                Text(currentPaceText)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.tasukiBrandYellow)
    }

    /// パネルを広げたときの黄ヘッダ（時間・カロリー）
    private var recordingExpandedYellowHeaderBlock: some View {
        VStack(spacing: 12) {
            Text("記録中")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiPrimary.opacity(0.75))
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .center, spacing: 6) {
                    Text("時間")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                    Text(formatDuration(elapsedSeconds))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(Color.tasukiPrimary.opacity(0.2))
                    .frame(width: 1, height: 48)
                VStack(alignment: .center, spacing: 6) {
                    Text("消費カロリー")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(estimatedCaloriesKcal)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .monospacedDigit()
                        Text("kcal")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(Color.tasukiPrimary.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Color.tasukiBrandYellow)
    }

    private func recordingSheetResizeGesture(contentHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let dx = abs(value.translation.width)
                let dy = value.translation.height
                guard abs(dy) > dx * 0.45 else { return }
                if recordingSheetDragStartFraction == nil {
                    recordingSheetDragStartFraction = recordingSheetFraction
                }
                guard let start = recordingSheetDragStartFraction else { return }
                let delta = dy / max(contentHeight, 120)
                let next = start - delta
                let minF = effectiveRecordingSheetMinFraction(contentHeight: contentHeight)
                recordingSheetFraction = min(max(next, minF), recordingSheetMaxFraction)
            }
            .onEnded { value in
                recordingSheetDragStartFraction = nil
                withAnimation(.spring(response: 0.38, dampingFraction: 0.92)) {
                    recordingSheetFraction = snapRecordingSheetFraction(
                        recordingSheetFraction,
                        contentHeight: contentHeight,
                        predictedEndTranslation: value.predictedEndTranslation,
                        totalTranslation: value.translation
                    )
                }
            }
    }

    /// シート比率は常に「最小＝マップ優先」か「最大＝記録」の二択のみ（中間には止めない）。
    private func snapRecordingSheetFraction(
        _ f: CGFloat,
        contentHeight: CGFloat,
        predictedEndTranslation: CGSize,
        totalTranslation: CGSize
    ) -> CGFloat {
        let minF = effectiveRecordingSheetMinFraction(contentHeight: contentHeight)
        let maxF = recordingSheetMaxFraction
        let ty = totalTranslation.height
        let py = predictedEndTranslation.height

        // 下スワイプ → マップ優先（シート最小）
        if ty > 6 || py > 20 {
            return minF
        }
        // 上スワイプ → 記録優先（シート最大）
        if ty < -6 || py < -20 {
            return maxF
        }

        // 動きが小さいときも min / max のどちらかへ寄せる
        let clamped = min(max(f, minF), maxF)
        let mid = (minF + maxF) / 2
        return clamped >= mid ? maxF : minF
    }

    private func syncTrackingMapCamera() {
        trackingMapCamera = .region(trackingLiveMapRegion)
    }

    /// 平均速度・距離（展開パネル内）
    private var trackingStatsBlock: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(String(format: "%.1f", averageSpeedKmh))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("平均速度（km/h）")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
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
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(unit)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
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

    private var runHeroTagline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RUN RECORDER")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            Text("GPSで記録して履歴に反映")
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

    /// 旧 CHALLENGE 行の位置。カウントダウン後に `beginRunStartCountdown` と同じフローで記録開始。
    private var primaryStartRunButton: some View {
        Button {
            beginRunStartCountdown()
        } label: {
            Text(runStartCountdownPhase != nil ? "準備中…" : "走行を開始")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.tasukiOnBrandYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
        }
        .buttonStyle(.plain)
        .disabled(runStartCountdownPhase != nil)
    }

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("スタート地点付近")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            ZStack {
                Map(position: $idleMapCamera, interactionModes: .all) {
                    if let cur = tracker.lastKnownCoordinate, !tracker.isTracking {
                        Annotation("現在地", coordinate: cur) {
                            ZStack {
                                Circle()
                                    .fill(Color.tasukiAccent.opacity(0.35))
                                    .frame(width: 22, height: 22)
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(Color.tasukiAccent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    if routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(Color.tasukiAccent, lineWidth: 4)
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .tasukiFlatCard()

                if idleMapLocationOverlayVisible {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(idleMapLocationOverlayMessage)
                            .font(.caption)
                            .foregroundColor(Color.tasukiMutedText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let err = tracker.locationError, !tracker.isTracking {
                Text(err)
                    .font(.caption)
                    .foregroundColor(Color.tasukiAccentOrange)
            }
            Button {
                requestCurrentLocationOnIdleMap()
            } label: {
                Label("現在地を取得", systemImage: "location.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.tasukiDarkCardSecondary, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var idleMapLocationOverlayVisible: Bool {
        guard !tracker.isTracking, tracker.lastKnownCoordinate == nil, tracker.locationError == nil else {
            return false
        }
        switch tracker.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            return true
        default:
            return false
        }
    }

    private var idleMapLocationOverlayMessage: String {
        switch tracker.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "現在地を取得しています…"
        case .notDetermined:
            return "位置情報を許可すると現在地が表示されます"
        default:
            return ""
        }
    }

    @ViewBuilder
    private func runStartCountdownOverlay(phase: Int) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            Text("\(phase)")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(Color.tasukiBrandYellow)
                .monospacedDigit()
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        }
        .allowsHitTesting(true)
        .transition(.opacity)
    }

    private func beginRunStartCountdown() {
        runStartCountdownTask?.cancel()
        runStartCountdownTask = Task { @MainActor in
            defer { runStartCountdownTask = nil }
            do {
                for phase in (1...3).reversed() {
                    runStartCountdownPhase = phase
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    try Task.checkCancellation()
                }
                runStartCountdownPhase = nil
                recordingSheetFraction = recordingSheetMaxFraction
                tracker.start()
                now = Date()
            } catch {
                runStartCountdownPhase = nil
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
                NavigationLink(
                    destination: RunHistoryListView(
                        entries: historyEntriesFromActivities,
                        suppressMainTabBackToHomeButton: true
                    )
                ) {
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

    private var historyEntriesFromActivities: [RunHistoryEntry] {
        activityStore.activities.map { activity in
            RunHistoryEntry(
                id: activity.id,
                date: activity.startedAt,
                distanceKm: activity.distanceKm,
                pace: activity.paceLabel,
                routeCoordinates: activity.route.map(\.coordinate)
            )
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
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
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

    init(onEkidenActivitySaved: ((RunActivity) -> Void)? = nil) {
        self.onEkidenActivitySaved = onEkidenActivitySaved
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
            .environmentObject(TabBarVisibility())
    }
}
