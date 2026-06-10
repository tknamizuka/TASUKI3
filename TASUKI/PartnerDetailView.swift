//
//  PartnerDetailView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI
import UIKit

// MARK: - Partner Detail View
struct PartnerDetailView: View {
    let user: User
    let ownerFirebaseUid: String?

    @State private var displayUser: User
    @State private var remoteActivities: [RunActivity] = []
    @State private var isLoadingRemoteData = false
    @State private var connectionStatus: ConnectionStatus
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showRequestAlert = false
    @State private var showInviteComposer = false
    @State private var isSendingRequest = false

    private let userManager = UserManager()

    init(user: User? = nil, ownerFirebaseUid: String? = nil, initialStatus: ConnectionStatus = .none) {
        let resolved = user ?? mockUser
        self.user = resolved
        self.ownerFirebaseUid = ownerFirebaseUid ?? resolved.firebaseUid
        _displayUser = State(initialValue: resolved)
        _connectionStatus = State(initialValue: initialStatus)
    }

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    UserPublicProfileScrollContent(
                        user: displayUser,
                        remoteActivities: remoteActivities,
                        isLoadingRemoteActivities: isLoadingRemoteData,
                        heroAccessory: .partnerOnline
                    )

                    actionButtonsView
                        .padding(.bottom, 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Profile")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .onAppear {
            loadRemoteProfileAndActivities()
        }
        .alert("リクエスト送信完了", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("パートナー申請を送信しますか？", isPresented: $showRequestAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("続ける", role: .none) {
                showInviteComposer = true
            }
        } message: {
            Text("相手にパートナー申請を送ります。日時・場所を入力してください。")
        }
        .sheet(isPresented: $showInviteComposer) {
            MatchInviteComposerSheet(
                navigationTitle: "パートナー申請",
                submitLabel: "送る",
                onSubmit: { payload in
                    Task { await sendPartnerRequest(payload) }
                }
            )
        }
    }

    @MainActor
    private func sendPartnerRequest(_ payload: MatchInvitePayload) async {
        guard let toUid = ownerFirebaseUid, !toUid.isEmpty else {
            alertMessage = "送信先ユーザーが特定できません"
            showAlert = true
            return
        }
        guard FindComplianceService.shared.canAccessFindFeatures else {
            alertMessage = "本人確認とメール確認を完了してください"
            showAlert = true
            return
        }
        isSendingRequest = true
        defer { isSendingRequest = false }
        do {
            _ = try await FindComplianceService.shared.sendMatchRequest(
                toUid: toUid,
                payload: payload,
                sourceScreen: "PartnerDetailView"
            )
            connectionStatus = .requested
            alertMessage = "リクエストを送信しました"
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func loadRemoteProfileAndActivities() {
        guard let uid = ownerFirebaseUid, !uid.isEmpty else { return }
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

    @ViewBuilder
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            switch connectionStatus {
            case .none:
                VStack(spacing: 8) {
                    Text("承認されるとメッセージが可能になります")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.55))

                    Button(action: {
                        showRequestAlert = true
                    }) {
                        HStack {
                            Spacer()
                            Text("リクエストを送る")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.tasukiOnBrandYellow)
                            Spacer()
                        }
                        .frame(height: 50)
                        .background(
                            Capsule()
                                .fill(Color.tasukiPrimaryButtonFill)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

            case .requested:
                Button(action: {}) {
                    HStack {
                        Spacer()
                        Text("申請中")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black.opacity(0.45))
                        Spacer()
                    }
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(true)

            case .received:
                HStack(spacing: 12) {
                    Button(action: {
                        connectionStatus = .none
                    }) {
                        Text("拒否")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black.opacity(0.7))
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(Color.gray.opacity(0.2))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        connectionStatus = .matched
                    }) {
                        Text("承認")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(Color.tasukiPrimaryButtonFill)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

            case .matched:
                Button(action: {
                    // MessageListView またはチャット画面へ遷移
                    // TODO: ナビゲーション実装
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("メッセージ")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(Color.tasukiPrimaryButtonFill)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview("None (初対面)") {
    NavigationStack {
        PartnerDetailView(user: mockUser, initialStatus: .none)
    }
}

#Preview("Requested (申請中)") {
    NavigationStack {
        PartnerDetailView(user: mockUser, initialStatus: .requested)
    }
}

#Preview("Received (申請受信)") {
    NavigationStack {
        PartnerDetailView(user: mockUser, initialStatus: .received)
    }
}

#Preview("Matched (マッチング済み)") {
    NavigationStack {
        PartnerDetailView(user: mockUser, initialStatus: .matched)
    }
}
