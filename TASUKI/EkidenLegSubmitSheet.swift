//
//  EkidenLegSubmitSheet.swift
//  TASUKI
//
//  区間提出シート: その場で記録 / RunRecording / デバイス記録 から選択して提出
//

import SwiftUI
import MapKit
import HealthKit
import FirebaseAuth
import Combine

// MARK: - 提出ソース
enum EkidenSubmitSource: String, CaseIterable {
    case appRecord = "その場で記録する"
    case runRecording = "RunRecordingから選ぶ"
    case deviceRecord = "デバイス記録から選ぶ"
}

// MARK: - EkidenLegSubmitSheet
struct EkidenLegSubmitSheet: View {
    let leg: EkidenLeg
    let state: EkidenViewState
    let teamId: String
    let isSampleTeam: Bool
    let onDismiss: () -> Void
    let onSuccess: () -> Void

    @State private var phase: Phase = .sourcePicker
    @State private var selectedRunActivityId: String? = nil  // デバイス記録の UUID
    /// HealthKit 選択時の詳細（Firestore 提出用）
    @State private var selectedHealthKitDetail: RunningWorkoutInfo?
    @State private var selectedRecordedActivityId: String? = nil
    @State private var healthKitWorkouts: [RunningWorkoutInfo] = []
    @State private var healthKitLoading = false
    @State private var healthKitError: String?
    @State private var confirmDistanceKm: Double = 0
    @State private var confirmElapsedSeconds: Double = 0
    @State private var confirmIsUnderTarget: Bool = false
    @State private var confirmSplitAtTargetSeconds: Double?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showRecorder = false
    @State private var showRunRecordingView = false
    @State private var showFinishRelayView = false
    @State private var didTapRelayConnect = false

    @ObservedObject private var tracker = RunTracker.shared
    @ObservedObject private var activityStore = RunActivityStore.shared

    private let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var recorderNow = Date()

    enum Phase {
        case sourcePicker
        case runRecordingList
        case healthKitList
        case confirm
    }

    private var targetKm: Double { leg.targetKm }

    /// EKIDEN（箱根）: 前走者が区間を完了（記録保存）した日時より前に開始した走行は提出不可
    private var minimumRunStartDateForStrictRelay: Date? {
        state.minimumActivityStartDateForRelay(legIndex: leg.id)
    }

    private var filteredRunRecordingsForRelay: [RunActivity] {
        let base = eventPeriodRunRecordingsBase
        guard let minD = minimumRunStartDateForStrictRelay else { return base }
        return base.filter { $0.startedAt >= minD }
    }

    
    private var selectedSourceLabel: String {
        if selectedRecordedActivityId != nil {
            return EkidenSubmitSource.runRecording.rawValue
        }
        if selectedRunActivityId != nil {
            return EkidenSubmitSource.deviceRecord.rawValue
        }
        return EkidenSubmitSource.appRecord.rawValue
    }
    
    private var eventPeriodRunRecordingsBase: [RunActivity] {
        activityStore.activities.filter {
            $0.startedAt >= state.event.startAt && $0.startedAt <= state.event.endAt
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground.ignoresSafeArea()
                switch phase {
                case .sourcePicker:
                    sourcePickerView
                case .runRecordingList:
                    runRecordingListView
                case .healthKitList:
                    healthKitListView
                case .confirm:
                    confirmView
                }
            }
            .navigationTitle("区間提出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        onDismiss()
                    }
                    .foregroundColor(Color.tasukiMutedText)
                }
            }
        }
        .fullScreenCover(isPresented: $showRecorder) {
            ekidenRecorderView
                .onReceive(elapsedTimer) { recorderNow = $0 }
        }
        .fullScreenCover(isPresented: $showRunRecordingView) {
            NavigationStack {
                RunRecordingView(onEkidenActivitySaved: { activity in
                    let isWithinEventPeriod = activity.startedAt >= state.event.startAt && activity.startedAt <= state.event.endAt
                    guard isWithinEventPeriod else {
                        showRunRecordingView = false
                        submitError = "イベント期間内の記録のみ提出できます。"
                        phase = .sourcePicker
                        return
                    }
                    if let minDate = minimumRunStartDateForStrictRelay, activity.startedAt < minDate {
                        showRunRecordingView = false
                        submitError = "この走行は前走者の保存完了より前に開始されています。"
                        phase = .sourcePicker
                        return
                    }
                    applyRunRecording(activity)
                    submitError = nil
                    showRunRecordingView = false
                    phase = .confirm
                })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") {
                                showRunRecordingView = false
                            }
                            .foregroundColor(Color.tasukiMutedText)
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showFinishRelayView) {
            finishRelayCelebrationView
        }
        .onAppear {
            activityStore.refreshFromRemote()
            if phase == .healthKitList && healthKitWorkouts.isEmpty {
                loadHealthKitWorkouts()
            }
        }
    }

    // MARK: - Source Picker
    private var sourcePickerView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(leg.id + 1)区（参考: \(String(format: "%.1f", targetKm)) km）")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("イベント期間内の記録を選んで提出できます")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
                if let cut = minimumRunStartDateForStrictRelay {
                    Text("EKIDEN: 走行の開始は「\(formatWorkoutFullDate(cut))」以降の記録のみ有効です（前走者の保存完了後）。")
                        .font(.caption)
                        .foregroundColor(Color.tasukiAccentOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tasukiCard()

            Button {
                showRunRecordingView = true
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text(EkidenSubmitSource.appRecord.rawValue)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.tasukiOnBrandYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
            }
            .buttonStyle(.plain)

            Button {
                phase = .runRecordingList
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text(EkidenSubmitSource.runRecording.rawValue)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.tasukiOnBrandYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
            }
            .buttonStyle(.plain)

            Button {
                phase = .healthKitList
                loadHealthKitWorkouts()
            } label: {
                HStack {
                    Image(systemName: "heart.fill")
                    Text(EkidenSubmitSource.deviceRecord.rawValue)
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.tasukiOnBrandYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
            }
            .buttonStyle(.plain)
            
            Text("提出できるのはイベント期間内の記録のみです。")
                .font(.caption)
                .foregroundColor(Color.tasukiMutedText)

            Spacer()
        }
        .padding(16)
    }
    
    // MARK: - RunRecording List
    private var runRecordingListView: some View {
        VStack(spacing: 0) {
            if filteredRunRecordingsForRelay.isEmpty {
                VStack(spacing: 12) {
                    Text(minimumRunStartDateForStrictRelay != nil
                         ? "条件を満たす RunRecording がありません（前走者完了後に開始した記録のみ）"
                         : "イベント期間内の RunRecording がありません")
                        .font(.subheadline)
                        .foregroundColor(Color.tasukiMutedText)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("戻る") { phase = .sourcePicker }
                        .foregroundColor(Color.tasukiAccent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRunRecordingsForRelay) { activity in
                        Button {
                            applyRunRecording(activity)
                            phase = .confirm
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatWorkoutDate(activity.startedAt))
                                        .font(.subheadline)
                                        .foregroundColor(Color.tasukiMutedText)
                                    Text("\(String(format: "%.2f", activity.distanceKm)) km")
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(formatDuration(activity.durationSeconds))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.tasukiPrimary)
                                    Text(activity.paceLabel)
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color.tasukiMutedText)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.tasukiDarkBackground)
            }
        }
    }

    // MARK: - HealthKit List
    private var healthKitListView: some View {
        VStack(spacing: 0) {
            if healthKitLoading {
                ProgressView("ランの記録を取得中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = healthKitError, healthKitWorkouts.isEmpty {
                VStack(spacing: 12) {
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(Color.tasukiMutedText)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("戻る") { phase = .sourcePicker }
                        .foregroundColor(Color.tasukiAccent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(healthKitWorkouts) { info in
                        Button {
                            applyHealthKitWorkout(info)
                            phase = .confirm
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(formatWorkoutDate(info.startDate)) 〜 \(formatWorkoutDate(info.endDate))")
                                        .font(.subheadline)
                                        .foregroundColor(Color.tasukiMutedText)
                                    Text("\(String(format: "%.2f", info.totalDistanceKm)) km · \(info.sourceName)")
                                        .font(.caption)
                                        .foregroundColor(Color.tasukiMutedText)
                                }
                                Spacer()
                                Text(info.durationFormatted)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.tasukiPrimary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color.tasukiMutedText)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.tasukiDarkBackground)
            }
        }
    }

    // MARK: - Confirm View
    private var confirmView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("提出内容を確認")
                    .font(.caption)
                    .foregroundColor(Color.tasukiMutedText)
                Text("問題なければ提出してください")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tasukiCard()

            VStack(alignment: .leading, spacing: 10) {
                confirmRow("提出元", selectedSourceLabel)
                confirmRow("距離", "\(String(format: "%.2f", confirmDistanceKm)) km")
                confirmRow("区間タイム", EkidenViewState.formatElapsed(confirmElapsedSeconds))
                if let hk = selectedHealthKitDetail {
                    confirmRow("デバイス開始", formatWorkoutFullDate(hk.startDate))
                    confirmRow("デバイス終了", formatWorkoutFullDate(hk.endDate))
                    confirmRow("活動時間 / 壁時計", "\(hk.durationFormatted) / \(hk.wallClockDurationFormatted)")
                    confirmRow("データソース", hk.sourceName)
                    if let m = hk.deviceModel, !m.isEmpty {
                        confirmRow("デバイス", [hk.deviceManufacturer, m].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                    }
                }
            }
            .tasukiCard()

            if let err = submitError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button {
                    phase = .sourcePicker
                    submitError = nil
                    selectedRunActivityId = nil
                    selectedRecordedActivityId = nil
                    selectedHealthKitDetail = nil
                } label: {
                    Text("戻る")
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
                .disabled(isSubmitting)

                Button {
                    submitLeg()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("提出する")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                .disabled(isSubmitting)
                .buttonStyle(.plain)
            }
            .tasukiCard()

            Spacer()
        }
        .padding(16)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("戻る") {
                    phase = .sourcePicker
                    submitError = nil
                    selectedRunActivityId = nil
                    selectedRecordedActivityId = nil
                    selectedHealthKitDetail = nil
                }
                .foregroundColor(Color.tasukiMutedText)
            }
        }
    }

    // MARK: - Recorder View
    private var ekidenRecorderView: some View {
        ZStack {
            Color.tasukiDarkBackground.ignoresSafeArea()
            if tracker.isTracking {
                VStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("記録中")
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

                    Text(String(format: "%.2f", tracker.distanceKm))
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .foregroundColor(Color.tasukiPrimary)
                        .monospacedDigit()
                    Text("km")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(Color.tasukiMutedText)

                    Spacer(minLength: 24)

                    HStack(spacing: 16) {
                        recorderValueCard(value: String(format: "%.0f", tracker.elevationGainMeters), title: "獲得標高 (m)")
                        recorderValueCard(value: String(format: "%.0f", tracker.currentAltitudeMeters), title: "現在の標高 (m)")
                    }

                    Spacer()

                    HStack(spacing: 14) {
                        Button {
                            if tracker.isPaused { tracker.resume() } else { tracker.pause() }
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
                            finishRecorderAndPrepareSubmission()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "flag.checkered")
                                Text("終了して提出")
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
                    Text("ランニングを記録して区間を提出")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                    Button {
                        tracker.start()
                        recorderNow = Date()
                    } label: {
                        Text("記録を開始")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                tracker.stop()
                tracker.reset()
                showRecorder = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color.tasukiMutedText)
            }
            .padding()
        }
    }

    // MARK: - Helpers
    private var recorderElapsedSeconds: Double {
        tracker.elapsedSeconds(now: recorderNow)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        if m >= 60 {
            let h = m / 60
            let mm = m % 60
            return String(format: "%d:%02d:%02d", h, mm, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func formatWorkoutDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }

    private func formatWorkoutFullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/M/d HH:mm:ss"
        return f.string(from: date)
    }

    private func confirmRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(Color.tasukiMutedText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(Color.tasukiPrimary)
        }
    }

    private func recorderValueCard(value: String, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(Color.tasukiPrimary)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.tasukiMutedText)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadHealthKitWorkouts() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitError = "HealthKit の利用を許可してください"
            healthKitLoading = false
            return
        }
        healthKitLoading = true
        healthKitError = nil
        HealthKitManager.shared.requestAuthorization { success, error in
            guard success else {
                healthKitLoading = false
                healthKitError = error?.localizedDescription ?? "HealthKit の利用を許可してください"
                healthKitWorkouts = []
                return
            }
            HealthKitManager.shared.fetchRunningWorkouts(
                from: state.event.startAt,
                to: state.event.endAt,
                minDistanceKm: 0,
                targetDistanceKm: targetKm,
                dataSource: .all
            ) { result in
                healthKitLoading = false
                switch result {
                case .success(let list):
                    let minD = self.state.minimumActivityStartDateForRelay(legIndex: self.leg.id)
                    let filtered = minD.map { cut in list.filter { $0.startDate >= cut } } ?? list
                    healthKitWorkouts = filtered
                    if filtered.isEmpty {
                        healthKitError = minD != nil
                            ? "前走者の区間保存完了より後に開始したデバイス記録がありません"
                            : "イベント期間内のデバイス記録がありません"
                    }
                case .failure(let e):
                    healthKitError = e.localizedDescription
                    healthKitWorkouts = []
                }
            }
        }
    }
    
    private func setSubmissionMetrics(distanceKm: Double, durationSeconds: Double, timeAtTargetSeconds: Double?) {
        confirmDistanceKm = distanceKm
        confirmIsUnderTarget = state.isCumulativeMode ? false : distanceKm < targetKm
        if !state.isCumulativeMode, distanceKm >= targetKm, let targetSeconds = timeAtTargetSeconds {
            confirmElapsedSeconds = targetSeconds
            confirmSplitAtTargetSeconds = targetSeconds
        } else {
            confirmElapsedSeconds = durationSeconds
            confirmSplitAtTargetSeconds = nil
        }
    }
    
    private func applyRunRecording(_ activity: RunActivity) {
        setSubmissionMetrics(
            distanceKm: activity.distanceKm,
            durationSeconds: activity.durationSeconds,
            timeAtTargetSeconds: nil
        )
        selectedRecordedActivityId = activity.id.uuidString
        selectedRunActivityId = nil
        selectedHealthKitDetail = nil
    }

    private func applyHealthKitWorkout(_ info: RunningWorkoutInfo) {
        setSubmissionMetrics(
            distanceKm: info.totalDistanceKm,
            durationSeconds: info.durationSeconds,
            timeAtTargetSeconds: info.timeAtTargetSeconds
        )
        selectedRunActivityId = info.id.uuidString
        selectedRecordedActivityId = nil
        selectedHealthKitDetail = info
    }

    private func finishRecorderAndPrepareSubmission() {
        tracker.stop()
        setSubmissionMetrics(
            distanceKm: tracker.distanceKm,
            durationSeconds: recorderElapsedSeconds,
            timeAtTargetSeconds: nil
        )
        selectedRunActivityId = nil
        selectedRecordedActivityId = nil
        selectedHealthKitDetail = nil
        tracker.reset()
        showRecorder = false
        phase = .confirm
    }

    private func submitLeg() {
        let submittedByUid: String
        if isSampleTeam {
            submittedByUid = leg.assignedUid ?? "sample_owner"
        } else {
            submittedByUid = Auth.auth().currentUser?.uid ?? ""
        }
        guard !submittedByUid.isEmpty else {
            submitError = "ログインが必要です"
            return
        }

        if let minD = state.minimumActivityStartDateForRelay(legIndex: leg.id) {
            if let hk = selectedHealthKitDetail, hk.startDate < minD {
                submitError = "この走行は前走者の保存完了（\(formatWorkoutFullDate(minD))）より前に開始されています。"
                return
            }
            if let rid = selectedRecordedActivityId, let uuid = UUID(uuidString: rid),
               let act = activityStore.activities.first(where: { $0.id == uuid }), act.startedAt < minD {
                submitError = "この走行は前走者の保存完了より前に開始されています。"
                return
            }
        }

        isSubmitting = true
        submitError = nil
        let source: String
        let runActivityId: String?
        if let activityId = selectedRecordedActivityId {
            source = "run_recorder"
            runActivityId = activityId
        } else if let workoutId = selectedRunActivityId {
            source = "health_kit"
            runActivityId = workoutId
        } else {
            source = "app_record"
            runActivityId = nil
        }
        let hkPayload = (source == "health_kit") ? selectedHealthKitDetail?.firestoreHealthKitPayload() : nil
        Task {
            let result = await EkidenDataService.shared.submitLeg(
                teamId: teamId,
                entryId: state.entry.id,
                eventId: state.event.id,
                legIndex: leg.id,
                actualDistanceKm: confirmDistanceKm,
                elapsedSeconds: confirmElapsedSeconds,
                isUnderTarget: confirmIsUnderTarget,
                splitAtTargetSeconds: confirmSplitAtTargetSeconds,
                totalLegCount: state.event.legCount,
                submittedByUid: submittedByUid,
                isSampleTeam: isSampleTeam,
                source: source,
                runActivityId: runActivityId,
                healthKitFirestorePayload: hkPayload
            )
            await MainActor.run {
                isSubmitting = false
                switch result {
                case .success:
                    let accumulatedDistance = (leg.actualDistanceKm ?? 0) + confirmDistanceKm
                    if !state.isCumulativeMode && accumulatedDistance >= targetKm {
                        didTapRelayConnect = false
                        showFinishRelayView = true
                    } else {
                        TasukiHandoffNotifier.notifyAfterLegSubmission(state: state, completedLegIndex: leg.id)
                        onSuccess()
                        onDismiss()
                    }
                case .failure(let e):
                    submitError = e.localizedDescription
                }
            }
        }
    }

    private var finishRelayCelebrationView: some View {
        ZStack {
            Color.tasukiDarkBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: didTapRelayConnect ? "sparkles" : "figure.run")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(Color.tasukiBrandYellow)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: didTapRelayConnect)
                Text(didTapRelayConnect ? "お疲れ様！\(leg.id + 1)区を走破した！" : "お疲れ様！ここまでよく頑張ったね！")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Color.tasukiPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if !didTapRelayConnect {
                    Button {
                        didTapRelayConnect = true
                        Task {
                            TasukiHandoffNotifier.notifyAfterLegSubmission(state: state, completedLegIndex: leg.id)
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            await MainActor.run {
                                showFinishRelayView = false
                                onSuccess()
                                onDismiss()
                            }
                        }
                    } label: {
                        Text("TASUKIをつなぐ")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Color.tasukiPrimaryButtonFill))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                }
                Spacer()
            }
        }
        .interactiveDismissDisabled(true)
    }
}
