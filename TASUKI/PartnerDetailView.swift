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

    @State private var connectionStatus: ConnectionStatus
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showRequestAlert = false

    init(user: User? = nil, initialStatus: ConnectionStatus = .none) {
        self.user = user ?? mockUser
        _connectionStatus = State(initialValue: initialStatus)
    }

    private var monthlyDistDisplay: String {
        "\(Int(user.monthlyDistance))km / \(Int(user.monthlyTarget))km"
    }

    private var partnerAreaDisplay: String {
        let p = user.prefecture.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = user.area.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty && !a.isEmpty { return "\(p), \(a)" }
        if !a.isEmpty { return a }
        if !p.isEmpty { return p }
        return "—"
    }

    private var runningSpotTags: [String] {
        user.spotName.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.bottom, 28)

                    statsSection
                        .padding(.bottom, 28)

                    profileSection
                        .padding(.bottom, 28)

                    if !user.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        aboutSection
                            .padding(.bottom, 28)
                    }

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
        .alert("リクエスト送信完了", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("パートナー申請を送信しますか？", isPresented: $showRequestAlert) {
            Button("キャンセル", role: .cancel) { }
            Button("送信", role: .none) {
                connectionStatus = .requested
                alertMessage = "リクエストを送信しました"
                showAlert = true
            }
        } message: {
            Text("相手にパートナー申請を送ります。よろしいですか？")
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            Group {
                if UIImage(named: user.profileImage) != nil {
                    Image(user.profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 96))
                        .foregroundColor(.black)
                        .frame(width: 140, height: 140)
                }
            }

            HStack(spacing: 8) {
                Text(user.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
                if let tier = PointBadgeHelper.tier(forTotalPoints: user.totalPoints) {
                    HStack(spacing: 4) {
                        Image(systemName: tier.iconName)
                        Text(tier.displayName)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                }
            }

            Text(user.rank)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)

            Text("\(user.age)歳 · \(user.gender)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black)

            HStack(spacing: 5) {
                Text("保有ポイント")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                Text("\(user.totalPoints)pt")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(user.isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(user.isOnline ? "オンライン" : "オフライン")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.black.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("RUNNING STATS")

            HStack(spacing: 12) {
                statItem(title: "Avg Pace", value: user.avgPace)
                statItem(title: "Monthly Dist", value: monthlyDistDisplay)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("PROFILE")

            HStack {
                Image(systemName: "mappin.and.ellipse")
                Text(partnerAreaDisplay)
            }
            .font(.subheadline)
            .foregroundColor(.black)

            if !user.purpose.isEmpty {
                tagView(text: user.purpose, isPrimary: true)
            }

            if !runningSpotTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(runningSpotTags, id: \.self) { spot in
                        tagView(text: spot, isPrimary: false)
                    }
                }
            }

            VStack(spacing: 0) {
                infoRow(icon: "trophy.fill", title: "Personal Best", value: user.personalBest)
                infoRow(icon: "calendar", title: "Schedule", value: user.schedule)
                if !user.nextRace.isEmpty {
                    infoRow(icon: "flag.fill", title: "Next Race", value: user.nextRace)
                }
                if !user.targetTime.isEmpty {
                    infoRow(icon: "scope", title: "Target", value: user.targetTime)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionEyebrow("ABOUT ME")
            Text(user.bio)
                .font(.system(size: 15))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.black)
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tagView(text: String, isPrimary: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
            .foregroundColor(.black)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            Spacer()
        }
        .padding(.vertical, 10)
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
