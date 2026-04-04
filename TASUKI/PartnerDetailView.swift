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
    @Environment(\.dismiss) var dismiss
    
    // Userモデルを使用
    let user: User
    
    // テスト用: 状態を変更可能にする
    // 以下の値を変更して各状態の表示を確認できます:
    // .none, .requested, .received, .matched
    @State private var connectionStatus: ConnectionStatus
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showRequestAlert = false
    
    init(user: User? = nil, initialStatus: ConnectionStatus = .none) {
        // プレビュー用のデフォルトデータ（mockUserを使用）
        self.user = user ?? mockUser
        // テスト用: 初期状態を設定
        _connectionStatus = State(initialValue: initialStatus)
    }
    
    // Userモデルから統計情報を計算
    private var stats: RunningStats {
        RunningStats(
            avgPace: user.avgPace,
            monthlyDist: "\(Int(user.monthlyDistance))km / \(Int(user.monthlyTarget))km",
            streak: "\(Int(user.monthlyDistance / user.monthlyTarget * 100))%"
        )
    }
    
    var body: some View {
        ZStack {
            // 背景色: White
            Color.white
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // 閉じるボタン（左上）
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color.tasukiPrimary)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color.tasukiDarkCardSecondary)
                                )
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    // ヘッダーセクション
                    VStack(spacing: 16) {
                        // アバター画像（大）
                        if UIImage(named: user.profileImage) != nil {
                            Image(user.profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 180)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.royalBlue.opacity(0.3), lineWidth: 3)
                                )
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 120))
                                .foregroundColor(Color.tasukiPrimary)
                                .saturation(0)
                                .frame(width: 180, height: 180)
                                .background(
                                    Circle()
                                        .fill(Color.tasukiDarkCardSecondary)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.royalBlue.opacity(0.3), lineWidth: 3)
                                )
                        }
                        
                        // 名前 + バッジ（公認マーク風）、年齢、ランク
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Text(user.name)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(Color.tasukiPrimary)
                                if let tier = PointBadgeHelper.tier(forTotalPoints: user.totalPoints) {
                                    Image(systemName: tier.iconName)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(tier.color)
                                }
                                Text("(\(user.age))")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                                
                                Text("•")
                                    .font(.system(size: 20, weight: .regular))
                                    .foregroundColor(Color.tasukiPrimary.opacity(0.5))
                                
                                Text("Rank \(user.rank)")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color.royalBlue)
                            }
                            
                            // オンライン/オフラインステータス
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(user.isOnline ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                
                                Text(user.isOnline ? "オンライン" : "オフライン")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // タグセクション（Running Spots & Purpose）
                    VStack(alignment: .leading, spacing: 12) {
                        // Purpose タグ
                        HStack {
                            Text("目的")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            tagView(text: user.purpose, isPrimary: true)
                            Spacer()
                        }
                        
                        // Running Spot タグ
                        if !user.spotName.isEmpty {
                            HStack {
                                Text("よく走る場所")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                                Spacer()
                            }
                            .padding(.top, 8)
                            
                            HStack(spacing: 8) {
                                tagView(text: user.spotName, isPrimary: false)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // 情報カード（Personal Best, Schedule, Next Race, Target）
                    VStack(spacing: 12) {
                        // Personal Best
                        infoCardView(
                            icon: "trophy.fill",
                            title: "Personal Best",
                            value: user.personalBest
                        )
                        
                        infoCardView(
                            icon: "calendar",
                            title: "Schedule",
                            value: user.schedule
                        )
                        
                        if !user.nextRace.isEmpty {
                            infoCardView(
                                icon: "flag.checkered",
                                title: "Next Race",
                                value: user.nextRace
                            )
                        }
                        
                        if !user.targetTime.isEmpty {
                            infoCardView(
                                icon: "scope",
                                title: "Target",
                                value: user.targetTime
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // ランニングスタッツ（2列×2行のグリッド）
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ランニング統計")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .padding(.horizontal, 20)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            statCardView(title: "Avg Pace", value: stats.avgPace)
                            statCardView(title: "Monthly Dist", value: stats.monthlyDist)
                            statCardView(title: "Progress", value: stats.streak)
                            statCardView(title: "Personal Best", value: user.personalBest)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)
                    
                    // アクションボタン（最下部）- 状態に応じて分岐
                    actionButtonsView
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
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
    
    // MARK: - Action Buttons View
    @ViewBuilder
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            switch connectionStatus {
            case .none:
                // Case 1: 初対面
                VStack(spacing: 8) {
                    Text("承認されるとメッセージが可能になります")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                    
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
                // Case 2: 申請中
                Button(action: {}) {
                    HStack {
                        Spacer()
                        Text("申請中")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.5))
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
                // Case 3: 相手から申請あり
                HStack(spacing: 12) {
                    Button(action: {
                        connectionStatus = .none
                    }) {
                        Text("拒否")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.7))
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
                // Case 4: マッチング済み
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
                    .foregroundColor(.white)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule()
                            .fill(Color.green)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Tag View
    private func tagView(text: String, isPrimary: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isPrimary ? Color.tasukiOnBrandYellow : Color.tasukiPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isPrimary ? Color.tasukiPrimaryButtonFill : Color.tasukiDarkCardSecondary)
            )
    }
    
    // MARK: - Info Card View
    private func infoCardView(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Color.royalBlue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.royalBlue.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Stat Card View
    private func statCardView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                .tracking(0.5)
            
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundColor(Color.tasukiPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
}

// MARK: - Running Stats Model
struct RunningStats {
    let avgPace: String
    let monthlyDist: String
    let streak: String
}

#Preview("None (初対面)") {
    PartnerDetailView(user: mockUser, initialStatus: .none)
}

#Preview("Requested (申請中)") {
    PartnerDetailView(user: mockUser, initialStatus: .requested)
}

#Preview("Received (申請受信)") {
    PartnerDetailView(user: mockUser, initialStatus: .received)
}

#Preview("Matched (マッチング済み)") {
    PartnerDetailView(user: mockUser, initialStatus: .matched)
}
