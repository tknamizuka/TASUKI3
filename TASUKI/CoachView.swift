//
//  CoachView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

struct CoachView: View {
    /// 外側に既に `NavigationStack` があるときは `false`（二重スタックでのクラッシュを避ける）。
    var embedNavigationStack: Bool = true

    @AppStorage("myName") private var myName: String = "Hiro"
    @State private var showQuestionSheet = false
    @EnvironmentObject private var coachCertification: CoachCertificationManager
    @ObservedObject private var qaStore = CoachQAStore.shared
    @ObservedObject private var activityStore = RunActivityStore.shared
    
    private var userQAItems: [QAItem] {
        qaStore.items.filter { $0.askerName == myName }
            .sorted { $0.postedDate > $1.postedDate }
    }
    
    var body: some View {
        // #region agent log
        let _ = AgentDebugLog.log(
            location: "CoachView.body",
            message: "coach_body_evaluated",
            hypothesisId: "C3",
            data: [
                "embedNavigationStack": "\(embedNavigationStack)",
                "isCertifiedCoach": "\(coachCertification.isCertifiedCoach)"
            ]
        )
        // #endregion
        Group {
            if embedNavigationStack {
                NavigationStack {
                    coachScaffold
                }
            } else {
                coachScaffold
            }
        }
    }

    private var coachScaffold: some View {
        ZStack {
            // #region agent log
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    AgentDebugLog.log(
                        location: "CoachView.coachScaffold",
                        message: "coach_scaffold_onAppear",
                        hypothesisId: "C2",
                        data: [
                            "embedNavigationStack": "\(embedNavigationStack)"
                        ]
                    )
                }
            // #endregion
            Color.tasukiDarkBackground
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ヘッダー
                    headerView
                        .padding(.horizontal, 20)
                        .padding(.top, 32)
                        .padding(.bottom, 20)

                    NavigationLink(destination: WeeklyReflectionView()) {
                        TasukiFlatHubRow(
                            title: "今週の振り返り",
                            subtitle: "回数・休息も含めて振り返る",
                            systemImage: "calendar.badge.clock"
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    
                    // A. コーチプログラム（インライン表示）
                    coachProgramSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    
                    // B. あなたの Q&A（サンプル＋自分の質問）
                    VStack(alignment: .leading, spacing: 12) {
                        Text("あなたの Q&A")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Color.tasukiPrimary)
                            .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("サンプル")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.tasukiMutedText)
                                .padding(.horizontal, 20)
                            VStack(spacing: 16) {
                                ForEach(coachPersonalSampleQAItems) { item in
                                    qaCardView(item: item, isSample: true)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        if !userQAItems.isEmpty {
                            Text("あなたの質問")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.tasukiMutedText)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                            VStack(spacing: 16) {
                                ForEach(userQAItems) { item in
                                    qaCardView(item: item, isSample: false)
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            Text("＋ボタンから、コーチへの質問を投稿できます")
                                .font(.system(size: 13))
                                .foregroundColor(Color.tasukiMutedText)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Coach")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            if coachCertification.isCertifiedCoach {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: CoachPendingQuestionsView()) {
                        Image(systemName: "text.bubble.fill")
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // 質問ボタン（フローティング）
            Button(action: {
                showQuestionSheet = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 56, height: 56)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Color.pureWhite)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            // メインタブのカスタムタブバーと重ならないよう余白を確保
            .padding(.bottom, 88)
        }
        .sheet(isPresented: $showQuestionSheet) {
            QuestionPostSheet(
                onPost: { question, category in
                    qaStore.addQuestion(question: question, category: category, askerName: myName)
                    showQuestionSheet = false
                },
                onCancel: {
                    showQuestionSheet = false
                }
            )
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(myName)さんへのアドバイス")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
            
            Text("走行実績と目標に基づくコーチメッセージ · 実業団選手があなたの質問に回答")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.tasukiMutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Coach Program Section (inline)
    private var coachProgramSection: some View {
        VStack(spacing: 14) {
            // 今週のコーチコメント
            VStack(alignment: .leading, spacing: 8) {
                Text("今週のコーチコメント")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text(coachRecommendationText)
                    .font(.system(size: 14))
                    .foregroundColor(Color.tasukiMutedText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.tasukiDarkCardSecondary)
            )
        }
    }
    
    private var coachRecommendationText: String {
        let weeklyRuns = activityStore.weeklyRunCount()
        switch weeklyRuns {
        case 0:
            return "まずは週2回から。短時間のEASY RUNを習慣化しましょう。"
        case 1...2:
            return "頻度は良い流れです。今週は1回だけ少し強度を上げるのがおすすめです。"
        case 3...4:
            return "十分な走行頻度です。疲労管理を優先しつつ、質を上げていきましょう。"
        default:
            return "高頻度で走れています。休養日を計画的に入れて故障予防を徹底しましょう。"
        }
    }
    
    // MARK: - Q&A Card View
    private func qaCardView(item: QAItem, isSample: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // カテゴリと投稿日
            HStack {
                let badge = qaCategoryBadgeStyle(for: item.category)
                Text(item.category)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(badge.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(badge.background)
                    )
                if isSample {
                    Text("サンプル")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.tasukiMutedText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.tasukiDarkCardSecondary)
                        )
                }
                Spacer()
                Text(formatDate(item.postedDate))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
            }
            
            // 質問
            VStack(alignment: .leading, spacing: 4) {
                Text("Q")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.tasukiAccentOrange)
                
                Text(item.question)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // 質問者（サンプルは「あなた」として現在の表示名を使用）
            HStack(spacing: 4) {
                Text("質問者:")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.tasukiMutedText)
                Text(isSample ? myName : item.askerName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            
            Divider()
                .background(Color.tasukiDarkCardSecondary)
            
            // 回答
            if let answer = item.answer {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("A")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.tasukiMutedText)
                        
                        if let coachName = item.coachName {
                            NavigationLink(destination: CoachProfileView(coachName: coachName)) {
                                Text(coachName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.tasukiAccentOrange)
                            }
                        }
                    }
                    
                    Text(answer)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color.tasukiPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.tasukiMutedText)
                    
                    Text("Coachが回答を作成中...")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color.tasukiMutedText)
                        .italic()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.tasukiDarkCardSecondary)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tasukiDarkCard)
        )
    }
    
    /// カテゴリごとのバッジ色（トレーニング / ケア / 食事 / ギア とその他）
    private func qaCategoryBadgeStyle(for category: String) -> (foreground: Color, background: Color) {
        switch category {
        case "トレーニング":
            return (Color.black.opacity(0.88), Color.black.opacity(0.08))
        case "ケア":
            return (Color(hex: "15654A"), Color(hex: "D8F3E4"))
        case "食事":
            return (Color(hex: "B45309"), Color(hex: "FFEDD5"))
        case "ギア":
            return (Color(hex: "1D4ED8"), Color(hex: "DBEAFE"))
        default:
            return (Color.tasukiPrimary.opacity(0.85), Color.tasukiDarkCardSecondary)
        }
    }

    // MARK: - Date Formatter
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - Question Post Sheet
struct QuestionPostSheet: View {
    let onPost: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var questionText: String = ""
    @State private var selectedCategory: String = "トレーニング"
    @Environment(\.dismiss) var dismiss
    
    private let categories = ["トレーニング", "ケア", "食事", "ギア"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // カテゴリ選択
                        VStack(alignment: .leading, spacing: 12) {
                            Text("カテゴリ")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.tasukiPrimary)
                            
                            Picker("カテゴリ", selection: $selectedCategory) {
                                ForEach(categories, id: \.self) { category in
                                    Text(category).tag(category)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // 質問入力
                        VStack(alignment: .leading, spacing: 12) {
                            Text("質問内容")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.tasukiPrimary)
                            
                            TextEditor(text: $questionText)
                                .font(.system(size: 16))
                                .foregroundColor(Color.tasukiPrimary)
                                .frame(height: 200)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.tasukiDarkCard)
                                )
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("質問を投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                    }
                    .foregroundColor(Color.tasukiPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("投稿") {
                        if !questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onPost(questionText, selectedCategory)
                        }
                    }
                    .foregroundColor(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.tasukiAccentOrange)
                    .fontWeight(.semibold)
                    .disabled(questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    CoachView()
        .environmentObject(CoachCertificationManager.shared)
}
