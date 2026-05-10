//
//  TimeTrialView.swift
//  TASUKI
//
//  タイムトライアル: 5〜15km・同ランク20名・1週間で1回走ってタイムで順位・ポイント（EKIDENとは別）
//

import SwiftUI
import MapKit
import Combine

// MARK: - エントリ（距離選択 → マッチング）
struct TimeTrialEntryView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var manager = TimeTrialManager.shared
    @AppStorage("myName") private var myName = "Runner"
    @AppStorage("myRank") private var myRank = "Rank B"
    
    @State private var selectedDistance: TimeTrialDistance = .fiveK
    @State private var isMatching = false
    @State private var matchedRoomId: String?
    @State private var matchError: String?
    @State private var pendingDistance: TimeTrialDistance?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("TIME TRIAL")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(Color.tasukiMutedText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        
                        Text("距離を選んで同ランクの20名とマッチング")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                        
                        VStack(spacing: 0) {
                            ForEach(TimeTrialDistance.allCases) { dist in
                                Button(action: {
                                    pendingDistance = dist
                                }) {
                                    TasukiFlatHubRow(
                                        title: timeTrialHubTitle(dist),
                                        subtitle: "週1回・タイムで順位 · 確認して参加",
                                        systemImage: "stopwatch.fill"
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isMatching)
                                .opacity(isMatching && selectedDistance != dist ? 0.5 : 1)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        if isMatching {
                            ProgressView("マッチング中...")
                                .padding(.top, 20)
                        }
                        if let err = matchError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(Color.tasukiAccentOrange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
                        
                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("タイムトライアル")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.tasukiPrimary)
                }
            }
            .navigationDestination(item: $matchedRoomId) { roomId in
                TimeTrialRoomView(roomId: roomId, onDismiss: { dismiss() })
            }
        }
        .onAppear { matchError = nil }
        .confirmationDialog(
            "この距離でタイムトライアルに参加しますか？",
            isPresented: Binding(
                get: { pendingDistance != nil },
                set: { if !$0 { pendingDistance = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("参加する") {
                guard let distance = pendingDistance else { return }
                selectedDistance = distance
                pendingDistance = nil
                startMatching()
            }
            Button("キャンセル", role: .cancel) {
                pendingDistance = nil
            }
        } message: {
            Text("参加後は同ランクの部屋へ移動します。")
        }
    }
    
    private func timeTrialHubTitle(_ dist: TimeTrialDistance) -> String {
        switch dist {
        case .fiveK: return "5KM"
        case .tenK: return "10KM"
        case .fifteenK: return "15KM"
        }
    }
    
    private func startMatching() {
        isMatching = true
        matchError = nil
        manager.createOrJoinRoom(distance: selectedDistance, userRank: myRank, userName: myName) { result in
            isMatching = false
            switch result {
            case .success(let roomId):
                matchedRoomId = roomId
            case .failure(let e):
                matchError = e.localizedDescription
            }
        }
    }
}

// MARK: - 部屋画面（期間・参加者・タイム提出 or 結果）
struct TimeTrialRoomView: View {
    let roomId: String
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var manager = TimeTrialManager.shared
    
    @State private var showSubmitSheet = false
    @State private var showResults = false
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var ranking: [TimeTrialRankingEntry] = []
    
    enum RecordSource { case choose, healthKit }
    @State private var recordSource: RecordSource = .choose
    @State private var healthKitWorkouts: [RunningWorkoutInfo] = []
    @State private var healthKitLoading = false
    @State private var healthKitError: String?
    @State private var showRecorder = false
    @ObservedObject private var tracker = RunTracker.shared
    @ObservedObject private var activityStore = RunActivityStore.shared
    @State private var recorderNow = Date()
    @State private var recorderTargetSplitSeconds: Double?
    @State private var recorderPreviousDistanceKm: Double = 0
    @State private var recorderPreviousElapsedSeconds: Double = 0
    @State private var recorderPendingSubmission = false
    @State private var recorderPendingCanSubmit = false
    @State private var recorderPendingSplitSeconds: Double = 0
    @State private var recorderPendingDistanceKm: Double = 0
    @State private var recorderPendingElapsedSeconds: Double = 0
    @AppStorage("runningDataSource") private var runningDataSourceRaw: String = RunningDataSource.all.rawValue
    @AppStorage("connectedRunningDevices") private var connectedRunningDevicesRaw: String = ""
    private let recorderTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var myParticipant: TimeTrialParticipant? {
        manager.participants.first { $0.id == manager.currentUserId }
    }
    
    private var hasSubmitted: Bool {
        myParticipant?.isSubmitted ?? false
    }

    private var selectedRunningDataSource: RunningDataSource {
        RunningDataSource(rawValue: runningDataSourceRaw) ?? .all
    }

    private var connectedRunningSources: [RunningDataSource] {
        connectedRunningDevicesRaw
            .split(separator: ",")
            .compactMap { RunningDataSource(rawValue: String($0)) }
            .filter { $0 != .all }
    }

    private var preferredConnectedSource: RunningDataSource? {
        if selectedRunningDataSource != .all, connectedRunningSources.contains(selectedRunningDataSource) {
            return selectedRunningDataSource
        }
        return connectedRunningSources.first
    }

    private var healthKitSourceButtonTitle: String {
        if let source = preferredConnectedSource {
            return "\(source.displayName) の記録から選ぶ"
        }
        if selectedRunningDataSource != .all {
            return "\(selectedRunningDataSource.displayName) の記録から選ぶ"
        }
        return "接続デバイスの記録から選ぶ"
    }

    private var recorderElapsedSeconds: TimeInterval {
        tracker.elapsedSeconds(now: recorderNow)
    }

    private var recorderAverageSpeedKmh: Double {
        guard recorderElapsedSeconds > 0 else { return 0 }
        return tracker.distanceKm / (recorderElapsedSeconds / 3600.0)
    }

    private var recorderRouteCoordinates: [CLLocationCoordinate2D] {
        tracker.routeCoordinates
    }

    private var recorderMapRegion: MKCoordinateRegion {
        guard let first = recorderRouteCoordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
        let lats = recorderRouteCoordinates.map(\.latitude)
        let lons = recorderRouteCoordinates.map(\.longitude)
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
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            Group {
            if let room = manager.currentRoom {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // 期間・距離・ランク
                        VStack(alignment: .leading, spacing: 8) {
                            Text(room.periodLabel)
                                .font(.subheadline)
                                .foregroundColor(Color.tasukiMutedText)
                            Text("\(room.distanceKm.clean) km · Rank \(room.rankTier)")
                                .font(.headline)
                                .foregroundColor(Color.tasukiPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.tasukiDarkCardSecondary)
                        .cornerRadius(12)
                        
                        Text("参加者 \(manager.participants.count) / 20 名")
                            .font(.subheadline)
                            .foregroundColor(Color.tasukiMutedText)
                        
                        if hasSubmitted {
                            Button(action: { loadRanking(); showResults = true }) {
                                HStack {
                                    Text("結果を見る")
                                    Image(systemName: "chart.bar.fill")
                                }
                                .font(.headline)
                                .foregroundColor(Color.tasukiOnBrandYellow)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.tasukiPrimaryButtonFill)
                                .cornerRadius(12)
                            }
                        } else {
                            Button(action: { showSubmitSheet = true }) {
                                HStack {
                                    Text("タイムを記録する")
                                    Image(systemName: "stopwatch.fill")
                                }
                                .font(.headline)
                                .foregroundColor(Color.tasukiOnBrandYellow)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.tasukiPrimaryButtonFill)
                                .cornerRadius(12)
                            }
                        }
                        
                        Divider()
                            .background(Color.tasukiDarkCardSecondary)
                        Text("参加者一覧")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(Color.tasukiMutedText)
                        ForEach(manager.participants) { p in
                            HStack {
                                Text(p.name)
                                    .font(.body)
                                    .foregroundColor(Color.tasukiPrimary)
                                Spacer()
                                if let label = p.timeLabel {
                                    Text(label)
                                        .font(.subheadline)
                                        .foregroundColor(Color.tasukiMutedText)
                                } else {
                                    Text("未記録")
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView("読み込み中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("タイムトライアル")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("閉じる") {
                    manager.stopListening()
                    onDismiss?()
                    dismiss()
                }
                .foregroundColor(Color.tasukiPrimary)
            }
        }
        .onAppear {
            manager.startListening(roomId: roomId)
        }
        .onDisappear {
            manager.stopListening()
        }
        .sheet(isPresented: $showSubmitSheet) {
            timeSubmitSheet(room: manager.currentRoom)
                .onDisappear { recordSource = .choose }
        }
        .sheet(isPresented: $showResults) {
            rankingSheet
        }
    }
    
    private func timeSubmitSheet(room: TimeTrialRoom?) -> some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground.ignoresSafeArea()
                Group {
                if recordSource == .choose {
                    recordSourceChoiceView(room: room)
                } else {
                    healthKitWorkoutListView(room: room)
                }
            }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("タイム記録")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if recordSource != .choose {
                        Button("戻る") { recordSource = .choose }
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("キャンセル") {
                        showSubmitSheet = false
                    }
                    .foregroundColor(Color.tasukiPrimary)
                }
            }
        }
        .onAppear { submitError = nil }
    }
    
    private func recordSourceChoiceView(room: TimeTrialRoom?) -> some View {
        VStack(spacing: 20) {
            Text("記録方法を選んでください")
                .font(.headline)
                .foregroundColor(Color.tasukiPrimary)
                .padding(.top, 24)
            Button(action: {
                showRecorder = true
            }) {
                HStack {
                    Image(systemName: "map.fill")
                    Text("アプリで記録する（地図/GPS）")
                }
                .font(.headline)
                .foregroundColor(Color.tasukiOnBrandYellow)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.tasukiPrimaryButtonFill)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            Button(action: {
                if selectedRunningDataSource.usesHealthKitForQueries {
                    HealthKitManager.shared.requestAuthorization { success, _ in
                        if success {
                            recordSource = .healthKit
                            loadHealthKitWorkouts(room: room)
                        } else {
                            healthKitError = "HealthKit の利用を許可してください"
                            recordSource = .healthKit
                        }
                    }
                } else {
                    recordSource = .healthKit
                    loadHealthKitWorkouts(room: room)
                }
            }) {
                HStack {
                    Image(systemName: "heart.fill")
                    Text(healthKitSourceButtonTitle)
                }
                .font(.headline)
                .foregroundColor(Color.tasukiOnBrandYellow)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.tasukiPrimaryButtonFill)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .fullScreenCover(isPresented: $showRecorder) {
            recorderView(room: room)
                .onReceive(recorderTimer) { recorderNow = $0 }
                .onChange(of: tracker.distanceKm) { _, newDistanceKm in
                    updateTargetSplitIfNeeded(room: room, newDistanceKm: newDistanceKm)
                }
        }
    }
    
    private func loadHealthKitWorkouts(room: TimeTrialRoom?) {
        guard let room = room else { return }
        healthKitLoading = true
        healthKitError = nil
        // サンプル部屋のときは HealthKit を使わずサンプル記録を表示
        if room.id.hasPrefix("sample_") {
            healthKitWorkouts = makeSampleWorkouts(for: room)
            healthKitLoading = false
            return
        }
        let targetKm = room.distanceKm
        let minKm = targetKm * 0.9
        HealthKitManager.shared.fetchRunningWorkouts(from: room.periodStart, to: room.periodEnd, minDistanceKm: minKm, targetDistanceKm: targetKm, dataSource: selectedRunningDataSource) { result in
            healthKitLoading = false
            switch result {
            case .success(let list):
                healthKitWorkouts = list
                if list.isEmpty { healthKitError = "\(selectedRunningDataSource.displayName) で条件を満たすランがありません" }
            case .failure(let e):
                healthKitError = e.localizedDescription
                healthKitWorkouts = []
            }
        }
    }
    
    /// サンプル部屋用のランニング記録（提出可能な複数件）
    private func makeSampleWorkouts(for room: TimeTrialRoom) -> [RunningWorkoutInfo] {
        let targetKm = room.distanceKm
        let now = Date()
        // 目標距離付近・提出可能なタイムのバリエーション
        let samples: [(Double, Double)] = [
            (targetKm * 0.98, 18 * 60 + 45),
            (targetKm * 1.00, 19 * 60 + 10),
            (targetKm * 1.02, 19 * 60 + 35),
            (targetKm * 0.97, 20 * 60),
            (targetKm * 1.03, 20 * 60 + 25)
        ]
        return samples.enumerated().map { index, pair in
            let (dist, sec) = pair
            let start = Calendar.current.date(byAdding: .day, value: -index - 1, to: now) ?? now
            return RunningWorkoutInfo(
                id: UUID(),
                startDate: start,
                durationSeconds: sec,
                totalDistanceKm: dist,
                timeAtTargetSeconds: sec
            )
        }
    }
    
    private func canSubmitWorkout(_ info: RunningWorkoutInfo, targetKm: Double) -> Bool {
        if info.timeAtTargetSeconds != nil { return true }
        let low = targetKm * 0.95
        let high = targetKm * 1.05
        return info.totalDistanceKm >= low && info.totalDistanceKm <= high
    }
    
    private func submitTimeSeconds(for info: RunningWorkoutInfo, targetKm: Double) -> Double? {
        if let t = info.timeAtTargetSeconds { return t }
        let low = targetKm * 0.95
        let high = targetKm * 1.05
        if info.totalDistanceKm >= low && info.totalDistanceKm <= high { return info.durationSeconds }
        return nil
    }
    
    private func healthKitWorkoutListView(room: TimeTrialRoom?) -> some View {
        let targetKm = room?.distanceKm ?? 5.0
        return VStack(spacing: 0) {
            if healthKitLoading {
                ProgressView("ランの記録を取得中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = healthKitError, healthKitWorkouts.isEmpty {
                Text(err)
                    .font(.subheadline)
                    .foregroundColor(Color.tasukiMutedText)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(healthKitWorkouts) { info in
                        let canSubmit = canSubmitWorkout(info, targetKm: targetKm)
                        let timeLabel: String = {
                            if let t = info.timeAtTargetFormatted {
                                return "\(targetKm.clean)km 時点: \(t)"
                            }
                            if canSubmit {
                                return "全体: \(info.durationFormatted)"
                            }
                            return "全体: \(info.durationFormatted) (ルートなし)"
                        }()
                        Button(action: {
                            guard let sec = submitTimeSeconds(for: info, targetKm: targetKm) else { return }
                            submitTimeWithSeconds(sec)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatWorkoutDate(info.startDate))
                                        .font(.subheadline)
                                        .foregroundColor(Color.tasukiMutedText)
                                    Text("\(String(format: "%.2f", info.totalDistanceKm)) km")
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                }
                                Spacer()
                                Text(timeLabel)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(canSubmit ? Color.tasukiPrimary : Color.tasukiMutedText)
                                if canSubmit {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(!canSubmit)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.tasukiDarkBackground)
            }
        }
    }
    
    private func formatWorkoutDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }
    
    private func submitTimeWithSeconds(_ totalSeconds: Double) {
        isSubmitting = true
        submitError = nil
        manager.submitTime(roomId: roomId, timeSeconds: totalSeconds) { result in
            isSubmitting = false
            switch result {
            case .success:
                showSubmitSheet = false
            case .failure(let e):
                submitError = e.localizedDescription
            }
        }
    }

    private func recorderView(room: TimeTrialRoom?) -> some View {
        ZStack {
            Color.tasukiDarkBackground.ignoresSafeArea()
            if recorderPendingSubmission {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("記録を確認")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Color.tasukiMutedText)
                            .tracking(1.5)
                        Text("提出前に内容を確認してください")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tasukiCard()

                    VStack(alignment: .leading, spacing: 8) {
                        recorderConfirmRow("距離", "\(String(format: "%.2f", recorderPendingDistanceKm)) km")
                        recorderConfirmRow("全体タイム", formatDuration(recorderPendingElapsedSeconds))
                        if recorderPendingCanSubmit {
                            recorderConfirmRow("提出タイム", formatDuration(recorderPendingSplitSeconds))
                        } else if let room = room {
                            Text("目標距離 \(room.distanceKm.clean)km に未達のため提出できません。中止して戻ることができます。")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.tasukiMutedText)
                        }
                    }
                    .tasukiCard()

                    HStack(spacing: 12) {
                        if recorderPendingCanSubmit {
                            Button {
                                submitPreparedRecorderTime()
                            } label: {
                                Text("タイムを提出")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(Color.tasukiOnBrandYellow)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                resumeRecorderFromPending()
                            } label: {
                                Text("計測を再開する")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiOnBrandYellow)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            cancelPreparedRecorderTime()
                        } label: {
                            Text(recorderPendingCanSubmit ? "戻る" : "中止して戻る")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.tasukiPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.tasukiDarkCardSecondary, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .tasukiCard()

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else if tracker.isTracking {
                VStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("自動停止")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                        Text(formatDuration(recorderElapsedSeconds))
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundColor(Color.tasukiPrimary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    .background(Color.tasukiSurface)

                    Spacer(minLength: 18)

                    Text(String(format: "%.1f", recorderAverageSpeedKmh))
                        .font(.system(size: 120, weight: .heavy, design: .rounded))
                        .foregroundColor(Color.tasukiPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("平均速度 (km/時)")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(Color.tasukiMutedText)

                    Spacer(minLength: 24)

                    HStack(spacing: 16) {
                        recorderValueCard(value: String(format: "%.2f", tracker.distanceKm), title: "距離 (km)")
                        recorderValueCard(value: String(format: "%.0f", tracker.elevationGainMeters), title: "獲得標高 (m)")
                    }
                    recorderValueCard(value: String(format: "%.0f", tracker.currentAltitudeMeters), title: "現在の標高 (m)")
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
                            finishRecorderAndPrepareSubmission(room: room)
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("アプリ記録")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Color.tasukiMutedText)
                            .tracking(1.5)
                        Text("地図でルート確認しながら記録")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tasukiCard()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ルート")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                        Map(initialPosition: .region(recorderMapRegion), interactionModes: .all) {
                            if recorderRouteCoordinates.count >= 2 {
                                MapPolyline(coordinates: recorderRouteCoordinates)
                                    .stroke(Color.tasukiAccent, lineWidth: 4)
                            }
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .tasukiCard()

                    Button {
                        tracker.start()
                        recorderNow = Date()
                        recorderTargetSplitSeconds = nil
                        recorderPreviousDistanceKm = 0
                        recorderPreviousElapsedSeconds = 0
                        recorderPendingSubmission = false
                    } label: {
                        Text("ランニングを記録する")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                    .tasukiCard()

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func finishRecorderAndPrepareSubmission(room: TimeTrialRoom?) {
        guard let room else { return }
        let elapsed = max(recorderElapsedSeconds, 1)
        if !tracker.isPaused {
            tracker.pause()
        }
        let targetKm = room.distanceKm
        let splitAtTarget: Double = {
            if let split = recorderTargetSplitSeconds {
                return split
            }
            let ratio = targetKm / max(tracker.distanceKm, 0.001)
            return max(1, elapsed * ratio)
        }()
        recorderPendingDistanceKm = tracker.distanceKm
        recorderPendingElapsedSeconds = elapsed
        recorderPendingSplitSeconds = splitAtTarget
        recorderPendingCanSubmit = tracker.distanceKm >= targetKm
        recorderPendingSubmission = true
    }

    private func submitPreparedRecorderTime() {
        guard recorderPendingSubmission, recorderPendingCanSubmit else { return }
        _ = activityStore.addActivity(
            distanceKm: recorderPendingDistanceKm,
            durationSeconds: recorderPendingElapsedSeconds,
            routeCoordinates: tracker.routeCoordinates,
            source: "time_trial_recorder"
        )
        tracker.stop()
        tracker.reset()
        submitTimeWithSeconds(recorderPendingSplitSeconds)
        recorderTargetSplitSeconds = nil
        recorderPendingCanSubmit = false
        recorderPendingSubmission = false
        showRecorder = false
        showSubmitSheet = false
    }

    private func cancelPreparedRecorderTime() {
        tracker.stop()
        tracker.reset()
        recorderTargetSplitSeconds = nil
        recorderPendingCanSubmit = false
        recorderPendingSubmission = false
        showRecorder = false
    }

    private func resumeRecorderFromPending() {
        guard recorderPendingSubmission, !recorderPendingCanSubmit else { return }
        recorderPendingSubmission = false
        tracker.resume()
        recorderNow = Date()
    }

    private func updateTargetSplitIfNeeded(room: TimeTrialRoom?, newDistanceKm: Double) {
        guard let room else { return }
        guard recorderTargetSplitSeconds == nil else {
            recorderPreviousDistanceKm = newDistanceKm
            recorderPreviousElapsedSeconds = recorderElapsedSeconds
            return
        }
        let targetKm = room.distanceKm
        let currentElapsed = recorderElapsedSeconds
        let prevDist = recorderPreviousDistanceKm
        let prevElapsed = recorderPreviousElapsedSeconds

        if newDistanceKm >= targetKm, prevDist < targetKm, newDistanceKm > prevDist {
            let fraction = (targetKm - prevDist) / (newDistanceKm - prevDist)
            let interpolated = prevElapsed + max(0, min(1, fraction)) * (currentElapsed - prevElapsed)
            recorderTargetSplitSeconds = max(1, interpolated)
        }

        recorderPreviousDistanceKm = newDistanceKm
        recorderPreviousElapsedSeconds = currentElapsed
    }

    private func recorderValueCard(value: String, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundColor(Color.tasukiPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)
        }
        .frame(maxWidth: .infinity)
    }

    private func recorderConfirmRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
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
    
    private var rankingSheet: some View {
        NavigationStack {
            List {
                ForEach(ranking) { entry in
                    HStack {
                        Text("\(entry.rank)位")
                            .font(.headline)
                            .foregroundColor(Color.tasukiPrimary)
                            .frame(width: 36, alignment: .leading)
                        Text(entry.name)
                            .foregroundColor(Color.tasukiPrimary)
                        Spacer()
                        Text(entry.timeLabel)
                            .foregroundColor(Color.tasukiMutedText)
                        Text("+\(entry.points)pt")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.tasukiAccentOrange)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .listRowBackground(Color.tasukiDarkCardSecondary.opacity(0.45))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.tasukiDarkBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("結果")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { showResults = false }
                        .foregroundColor(Color.tasukiPrimary)
                }
            }
        }
    }
    
    private func loadRanking() {
        manager.fetchRanking(roomId: roomId) { result in
            switch result {
            case .success(let list):
                ranking = list
            case .failure:
                ranking = []
            }
        }
    }
}

extension Double {
    var clean: String {
        if self == Double(Int(self)) { return "\(Int(self))" }
        return String(format: "%.1f", self)
    }
}

#if DEBUG
#Preview("タイムトライアル エントリ") {
    TimeTrialEntryView()
}
#endif
