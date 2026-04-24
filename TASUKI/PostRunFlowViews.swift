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
            postRunMood: nil
        )
        let earnedPoints = max(20, Int(activity.distanceKm * 12))
        PointService.shared.addPointsToCurrentUser(amount: earnedPoints)
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let t = activity.title, !t.isEmpty {
                    Text(t)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(formatDate(activity.startedAt))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.tasukiMutedText)
                    HStack(spacing: 20) {
                        reviewStat(title: "距離", value: String(format: "%.2f km", activity.distanceKm))
                        reviewStat(title: "時間", value: formatDuration(activity.durationSeconds))
                        reviewStat(title: "平均ペース", value: activity.paceLabel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiDarkCardSecondary))

                if let note = activity.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 15))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.tasukiDarkCard))
                }

                Text("走行ルート")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.tasukiMutedText)

                RunHistoryMapView(coordinates: routeCoordinates, region: mapRegion)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(20)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .navigationTitle("振り返り")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
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
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
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
