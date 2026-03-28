//
//  CoachProfileView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/03/04.
//

import SwiftUI

struct CoachProfileView: View {
    let coachName: String
    @Environment(\.dismiss) var dismiss
    
    // コーチプロフィールのモックデータ
    private var coachProfile: CoachProfile {
        getCoachProfile(by: coachName)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // ヘッダー画像とプロフィール
                        headerSection
                        
                        // プロフィール情報
                        profileInfoSection
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // 経歴/資格セクション
                        backgroundSection
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // 専門分野セクション
                        expertiseSection
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                        
                        Divider()
                            .padding(.horizontal, 20)
                        
                        // 質問一覧セクション
                        answersSection
                            .padding(.horizontal, 20)
                            .padding(.vertical, 24)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle(coachProfile.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // プロフィール画像（yoshiki_hiro.imageset を想定）
            // 横幅・縦幅を固定し、サークルでクリップしてサイズ調整
            Image(coachProfile.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(radius: 2)
                .background(
                    Circle().fill(Color.tasukiDarkCardSecondary)
                        .frame(width: 124, height: 124)
                )
            
            // レーティング
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: index < coachProfile.rating ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "FFB800"))
                    }
                }
                Text("\(coachProfile.rating).0 (\(coachProfile.reviewCount)件)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color.tasukiDarkCard)
    }
    
    // MARK: - Profile Info Section
    private var profileInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("肩書")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText)
                Text(coachProfile.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("自己紹介")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText)
                Text(coachProfile.bio)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.tasukiPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Background Section
    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("経歴/資格")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(coachProfile.background, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color.tasukiAccentOrange)
                            .padding(.top, 2)
                        
                        Text(item)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.tasukiPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Expertise Section
    private var expertiseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("専門分野")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(coachProfile.expertise, id: \.self) { item in
                    HStack(spacing: 0) {
                        Text(item)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color.tasukiAccentOrange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.tasukiDarkCard)
                            )
                        
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Answers Section
    private var answersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("回答済み質問（最近3件）")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
            
            VStack(spacing: 12) {
                ForEach(coachProfile.recentAnswers, id: \.self) { answer in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(answer)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color.tasukiPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("タップして詳細を見る →")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.tasukiAccentOrange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.tasukiDarkCard)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Helper: Get Coach Profile
    private func getCoachProfile(by name: String) -> CoachProfile {
        switch name {
        case "廣 佳樹":
            return CoachProfile(
                name: "廣 佳樹",
                title: "Arke Running Club コーチ",
                bio: "中央学院大学時代に箱根駅伝4年連続出場（3・4年時は「花の2区」担当）。マツダ陸上競技部で実業団ランナーとして活躍後、SUBARUでコーチ・マネージャーを歴任。2025年6月設立のArke Running Clubでは、一般ランナーから中学生まで幅広く指導。「走ることの楽しさ」と「目標達成の喜び」を伝える指導を行っています。",
                rating: 5,
                reviewCount: 156,
                background: [
                    "兵庫県立西宮高校",
                    "中央学院大学 箱根駅伝4年連続出場（2区担当）",
                    "マツダ陸上競技部 実業団ランナー（2022年引退）",
                    "SUBARU陸上競技部 コーチ兼マネージャー",
                    "Arke Running Club コーチ（現職）"
                ],
                expertise: ["トレーニング計画", "ペース走指導", "フルマラソンコーチング", "ジュニア育成", "目標達成支援"],
                recentAnswers: [
                    "ラン後のストレッチはどのくらい時間をかけるべきですか？",
                    "サブ4を目指す場合、週間距離はどのくらい必要ですか？",
                    "フルマラソンに向けた練習計画について"
                ],
                imageName: "yoshiki_hiro"
            )
        default:
            return CoachProfile(
                name: "廣 佳樹",
                title: "Arke Running Club コーチ",
                bio: "中央学院大学時代に箱根駅伝4年連続出場（3・4年時は「花の2区」担当）。マツダ陸上競技部で実業団ランナーとして活躍後、2025年6月設立のArke Running Clubでは、一般ランナーから中学生まで幅広く指導。「走ることの楽しさ」と「目標達成の喜び」を伝える指導を行っています。",
                rating: 5,
                reviewCount: 156,
                background: [
                    "兵庫県立西宮高校",
                    "中央学院大学 箱根駅伝4年連続出場（2区担当）",
                    "マツダ陸上競技部 実業団ランナー（2022年引退）",
                    "SUBARU陸上競技部 コーチ兼マネージャー",
                    "Arke Running Club コーチ（現職）"
                ],
                expertise: ["トレーニング計画", "ペース走指導", "フルマラソンコーチング", "ジュニア育成", "目標達成支援"],
                recentAnswers: [
                    "ラン後のストレッチはどのくらい時間をかけるべきですか？",
                    "サブ4を目指す場合、週間距離はどのくらい必要ですか？",
                    "フルマラソンに向けた練習計画について"
                ],
                imageName: "yoshiki_hiro"
            )
        }
    }
}

// MARK: - Coach Profile Model
struct CoachProfile {
    let name: String
    let title: String
    let bio: String
    let rating: Int
    let reviewCount: Int
    let background: [String]
    let expertise: [String]
    let recentAnswers: [String]
    // 画像名（アセットカタログに登録されているもの）
    let imageName: String
}

#Preview {
    CoachProfileView(coachName: "廣 佳樹")
}
