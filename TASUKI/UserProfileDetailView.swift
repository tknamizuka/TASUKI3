import SwiftUI
import UIKit

/// Find などから開く他ユーザープロフィール（`MyProfileView` と同じ項目構成の公開ビュー）。
struct UserProfileDetailView: View {
    let user: User
    private let activityChartPoints: [WeeklyActivityChartPoint]
    @State private var displayUser: User
    @State private var remoteActivities: [RunActivity] = []
    @State private var isLoadingRemoteData = false
    @State private var showInviteComposer = false
    @State private var showRequestSent = false
    @State private var showRequestError = false
    @State private var requestErrorMessage = ""
    @State private var isSendingRequest = false
    @Environment(\.dismiss) private var dismiss

    private let userManager = UserManager()

    init(user: User, activityChartPoints: [WeeklyActivityChartPoint]? = nil) {
        self.user = user
        self.activityChartPoints = activityChartPoints ?? FindMockWeeklyActivity.chartPoints(for: user)
        _displayUser = State(initialValue: user)
    }

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    UserPublicProfileScrollContent(
                        user: displayUser,
                        activityChartPoints: activityChartPoints,
                        remoteActivities: remoteActivities,
                        isLoadingRemoteActivities: isLoadingRemoteData,
                        heroAccessory: .findMatchRate(displayUser.matchRate)
                    )
                    .padding(.bottom, 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadRemoteProfileAndActivities()
            if let uid = displayUser.firebaseUid {
                Task {
                    await FindComplianceService.shared.logProfileView(
                        targetUid: uid,
                        sourceScreen: "UserProfileDetailView"
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Profile")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .overlay(alignment: .bottom) {
            Button(action: {
                guard FindComplianceService.shared.canAccessFindFeatures else {
                    requestErrorMessage = "本人確認とメール確認を完了してください"
                    showRequestError = true
                    return
                }
                showInviteComposer = true
            }) {
                Text(isSendingRequest ? "送信中…" : "マッチングのリクエストを送る")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.tasukiPrimaryButtonFill)
                    .cornerRadius(30)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.tasukiDarkBackground.opacity(0), Color.tasukiDarkBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
            )
            .disabled(isSendingRequest)
        }
        .sheet(isPresented: $showInviteComposer) {
            MatchInviteComposerSheet(
                navigationTitle: "マッチング招待",
                submitLabel: "送る",
                onSubmit: { payload in
                    Task { await sendMatchInvite(payload) }
                }
            )
        }
        .alert("送信完了", isPresented: $showRequestSent) {
            Button("OK") { }
        } message: {
            Text("\(displayUser.name)さんにマッチングの招待（日時・場所付き）を送りました。")
        }
        .alert("送信できませんでした", isPresented: $showRequestError) {
            Button("OK") { }
        } message: {
            Text(requestErrorMessage)
        }
    }

    @MainActor
    private func sendMatchInvite(_ payload: MatchInvitePayload) async {
        guard let toUid = displayUser.firebaseUid, !toUid.isEmpty else {
            requestErrorMessage = "送信先ユーザーが特定できません"
            showRequestError = true
            return
        }
        isSendingRequest = true
        defer { isSendingRequest = false }
        do {
            _ = try await FindComplianceService.shared.sendMatchRequest(
                toUid: toUid,
                payload: payload,
                sourceScreen: "UserProfileDetailView"
            )
            showRequestSent = true
        } catch {
            requestErrorMessage = error.localizedDescription
            showRequestError = true
        }
    }

    private func loadRemoteProfileAndActivities() {
        guard let uid = displayUser.firebaseUid, !uid.isEmpty else { return }
        isLoadingRemoteData = true

        let group = DispatchGroup()

        group.enter()
        userManager.fetchPublicProfile(firebaseUid: uid) { result in
            if case .success(let profile) = result {
                displayUser = profile
            }
            group.leave()
        }

        group.enter()
        RunActivityStore.shared.fetchActivitiesForUser(firebaseUid: uid) { result in
            if case .success(let activities) = result {
                remoteActivities = activities
            }
            group.leave()
        }

        group.notify(queue: .main) {
            isLoadingRemoteData = false
        }
    }
}

#Preview {
    NavigationStack {
        UserProfileDetailView(user: mockUsers[0])
    }
}
