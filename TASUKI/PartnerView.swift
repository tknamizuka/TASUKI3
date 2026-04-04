//
//  PartnerView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

// MARK: - Partner View
struct PartnerView: View {
    // ダミーデータ（元のリスト）
    @State private var mockUsers: [PartnerUser] = [
        PartnerUser(
            name: "Kenji_Run",
            rank: "S",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .half,
            bestTime: "1:25:00",
            age: 28,
            runningSchedule: .weekendMorning,
            purpose: "サブ3目標",
            nextRace: "東京マラソン2025",
            targetTime: "フル 2:55:00",
            runningSpots: ["皇居", "代々木公園", "多摩川"],
            prefecture: "Tokyo",
            gender: .male,
            condition: .excellent,
            statusMessage: "調子が良い！今月は200km走る目標です🔥",
            ageGroup: "20s",
            runningGoal: "Sub3",
            personalBest: "2:58:00",
            activeTime: "Morning",
            easyPace: "4:30/km",
            connectionStyle: .real,
            totalPoints: 28000
        ),
        PartnerUser(
            name: "さっちゃん",
            rank: "A",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .full,
            bestTime: "3:15:00",
            age: 32,
            runningSchedule: .weekdayEvening,
            purpose: "サブ3目標",
            nextRace: "横浜マラソン2025",
            targetTime: "フル 2:58:00",
            runningSpots: ["お台場", "多摩川", "駒沢公園"],
            prefecture: "Kanagawa",
            gender: .female,
            condition: .good,
            statusMessage: "今月も頑張ります！週3回のペースで走ってます",
            ageGroup: "30s",
            runningGoal: "Sub3",
            personalBest: "3:15:00",
            activeTime: "Night",
            easyPace: "5:00/km",
            connectionStyle: .real,
            totalPoints: 12000
        ),
        PartnerUser(
            name: "Taka@Sub3",
            rank: "B",
            avatarImage: "person.circle.fill",
            isOnline: false,
            bestCategory: .tenKm,
            bestTime: "35:00",
            age: 25,
            runningSchedule: .weekendMorning,
            purpose: "健康維持",
            nextRace: "東京10kmロードレース",
            targetTime: "10km 33:00",
            runningSpots: ["皇居", "代々木公園"],
            prefecture: "Tokyo",
            gender: .male,
            condition: .good,
            statusMessage: "週末の朝ランが楽しみです！",
            ageGroup: "20s",
            runningGoal: "健康維持",
            personalBest: nil,
            activeTime: "Morning",
            easyPace: "5:30/km",
            connectionStyle: .both,
            totalPoints: 6500
        ),
        PartnerUser(
            name: "Momo",
            rank: "C",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .half,
            bestTime: "1:35:00",
            age: 29,
            runningSchedule: .flexible,
            purpose: "ダイエット",
            nextRace: nil,
            targetTime: nil,
            runningSpots: ["大阪城公園", "中之島公園"],
            prefecture: "Osaka",
            gender: .female,
            condition: .tired,
            statusMessage: "最近忙しくて疲れ気味...でも走りたい！",
            ageGroup: "20s",
            runningGoal: "ダイエット",
            personalBest: nil,
            activeTime: "Holiday",
            easyPace: "6:00/km",
            connectionStyle: .virtual,
            totalPoints: 2200
        ),
        PartnerUser(
            name: "Runner123",
            rank: "D",
            avatarImage: "person.circle.fill",
            isOnline: false,
            bestCategory: .tenKm,
            bestTime: "42:00",
            age: 24,
            runningSchedule: .weekdayEvening,
            purpose: "ダイエット",
            nextRace: nil,
            targetTime: nil,
            runningSpots: ["代々木公園"],
            prefecture: "Tokyo",
            gender: .female,
            condition: .sos,
            statusMessage: "足を痛めてしまいました...しばらく休みます💦",
            ageGroup: "20s",
            runningGoal: "ダイエット",
            personalBest: nil,
            activeTime: "Night",
            easyPace: "6:30/km",
            connectionStyle: .both,
            totalPoints: 800
        ),
        PartnerUser(
            name: "マラソン太郎",
            rank: "S",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .full,
            bestTime: "2:45:00",
            age: 35,
            runningSchedule: .weekdayMorning,
            purpose: "自己ベスト更新",
            nextRace: "大阪マラソン2025",
            targetTime: "フル 2:40:00",
            runningSpots: ["大阪城公園", "中之島公園"],
            prefecture: "Osaka",
            gender: .male,
            condition: .excellent,
            statusMessage: "朝ランで気持ちいい！PB更新に向けて頑張ります",
            ageGroup: "30s",
            runningGoal: "Sub3",
            personalBest: "2:45:00",
            activeTime: "Morning",
            easyPace: "4:00/km",
            connectionStyle: .real,
            totalPoints: 52000
        ),
        PartnerUser(
            name: "みか",
            rank: "A",
            avatarImage: "person.circle.fill",
            isOnline: false,
            bestCategory: .half,
            bestTime: "1:30:00",
            age: 27,
            runningSchedule: .weekendMorning,
            purpose: "ファンラン",
            nextRace: "名古屋ウィメンズマラソン2025",
            targetTime: "ハーフ 1:25:00",
            runningSpots: ["名古屋城", "名城公園"],
            prefecture: "Aichi",
            gender: .female,
            condition: .good,
            statusMessage: "週末のランニングが楽しみ！一緒に走りましょう",
            ageGroup: "20s",
            runningGoal: "完走",
            personalBest: "3:45:00",
            activeTime: "Morning",
            easyPace: "5:15/km",
            connectionStyle: .both,
            totalPoints: 15000
        ),
        PartnerUser(
            name: "Hiro_Runner",
            rank: "B",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .tenKm,
            bestTime: "38:00",
            age: 42,
            runningSchedule: .weekdayEvening,
            purpose: "健康維持",
            nextRace: "福岡マラソン2025",
            targetTime: "10km 36:00",
            runningSpots: ["大濠公園", "福岡タワー"],
            prefecture: "Fukuoka",
            gender: .male,
            condition: .good,
            statusMessage: "仕事終わりのランでリフレッシュ！",
            ageGroup: "40s",
            runningGoal: "健康維持",
            personalBest: "3:30:00",
            activeTime: "Night",
            easyPace: "5:45/km",
            connectionStyle: .virtual,
            totalPoints: 3500
        ),
        PartnerUser(
            name: "あきこ",
            rank: "C",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .half,
            bestTime: "1:40:00",
            age: 38,
            runningSchedule: .weekendAfternoon,
            purpose: "ダイエット",
            nextRace: nil,
            targetTime: nil,
            runningSpots: ["大通公園", "円山公園"],
            prefecture: "Hokkaido",
            gender: .female,
            condition: .tired,
            statusMessage: "最近体重が落ちてきて嬉しい！でも少し疲れ気味...",
            ageGroup: "30s",
            runningGoal: "ダイエット",
            personalBest: nil,
            activeTime: "Holiday",
            easyPace: "6:15/km",
            connectionStyle: .virtual,
            totalPoints: 1100
        ),
        PartnerUser(
            name: "RunTaka",
            rank: "D",
            avatarImage: "person.circle.fill",
            isOnline: false,
            bestCategory: .fiveKm,
            bestTime: "22:00",
            age: 22,
            runningSchedule: .flexible,
            purpose: "ファンラン",
            nextRace: nil,
            targetTime: nil,
            runningSpots: ["皇居", "新宿御苑"],
            prefecture: "Tokyo",
            gender: .male,
            condition: .good,
            statusMessage: "ランニング始めたばかり！一緒に楽しみましょう",
            ageGroup: "20s",
            runningGoal: "完走",
            personalBest: nil,
            activeTime: "Holiday",
            easyPace: "6:45/km",
            connectionStyle: .both,
            totalPoints: 500
        )
    ]
    
    // 検索とフィルター用のState
    @State private var searchMode: String = "Real"  // "Real" or "Online"
    @State private var searchText = ""
    @State private var showFilterSheet = false
    
    // 自分の性別を取得
    @AppStorage("myGender") private var myGender: String = "male"
    
    // フィルター条件
    @State private var selectedPrefecture: String = "All"
    @State private var selectedAgeGroups: Set<String> = []
    @State private var selectedGender: String = "All"  // "All", "Male", "Female", "Other"
    @State private var runSpotText = ""
    @State private var selectedRunSpot: String = ""
    @State private var selectedPurposes: Set<String> = []
    @State private var selectedSchedules: Set<String> = []
    @State private var selectedRanks: Set<String> = []
    @State private var nextRaceText = ""
    
    // ランスポットの候補リスト
    private let runSpotSuggestions = [
        "Imperial Palace", "Yoyogi Park", "Komazawa Park", "Tama River",
        "Odaiba", "Osaka Castle", "Nakanoshima Park", "Nagoya Castle",
        "Meijo Park", "Ohori Park", "Fukuoka Tower", "Sapporo Odori Park",
        "Maruyama Park", "Shinjuku Gyoen"
    ]
    
    // フィルタリングされたユーザーリスト
    private var filteredUsers: [PartnerUser] {
        var filtered = mockUsers
        
        // Real Runモード: 同性限定フィルタ（強制）
        if searchMode == "Real" {
            if let currentUserGender = Gender(rawValue: myGender) {
                filtered = filtered.filter { $0.gender == currentUserGender }
            }
        }
        
        // 名前検索
        if !searchText.isEmpty {
            filtered = filtered.filter { user in
                user.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 居住地フィルター
        if selectedPrefecture != "All" {
            filtered = filtered.filter { $0.prefecture == selectedPrefecture }
        }
        
        // 年齢グループフィルター（OR検索）
        if !selectedAgeGroups.isEmpty {
            filtered = filtered.filter { user in
                let ageGroup = getAgeGroup(user.age)
                return selectedAgeGroups.contains(ageGroup)
            }
        }
        
        // 性別フィルター（Onlineモードのみ有効）
        if searchMode == "Online" && selectedGender != "All" {
            if let gender = Gender(rawValue: selectedGender.lowercased()) {
                filtered = filtered.filter { $0.gender == gender }
            }
        }
        
        // ランスポットフィルター（部分一致）
        if !selectedRunSpot.isEmpty {
            filtered = filtered.filter { user in
                user.runningSpots.contains { spot in
                    spot.localizedCaseInsensitiveContains(selectedRunSpot)
                }
            }
        }
        
        // 目的フィルター（OR検索）
        if !selectedPurposes.isEmpty {
            filtered = filtered.filter { user in
                selectedPurposes.contains(user.purpose)
            }
        }
        
        // スケジュールフィルター（OR検索）
        if !selectedSchedules.isEmpty {
            filtered = filtered.filter { user in
                let scheduleString = getScheduleString(user.runningSchedule)
                return selectedSchedules.contains(scheduleString)
            }
        }
        
        // ランクフィルター（OR検索）
        if !selectedRanks.isEmpty {
            filtered = filtered.filter { user in
                selectedRanks.contains(user.rank)
            }
        }
        
        // 次回のレースフィルター（部分一致）
        if !nextRaceText.isEmpty {
            filtered = filtered.filter { user in
                if let nextRace = user.nextRace {
                    return nextRace.localizedCaseInsensitiveContains(nextRaceText)
                }
                return false
            }
        }
        
        return filtered
    }
    
    // 年齢グループを取得
    private func getAgeGroup(_ age: Int) -> String {
        switch age {
        case 10..<20: return "10代"
        case 20..<30: return "20代"
        case 30..<40: return "30代"
        case 40..<50: return "40代"
        case 50..<60: return "50代"
        default: return "60代以上"
        }
    }
    
    // スケジュールを文字列に変換
    private func getScheduleString(_ schedule: RunningSchedule) -> String {
        switch schedule {
        case .weekdayMorning: return "平日朝"
        case .weekdayEvening: return "平日夜"
        case .weekendMorning, .weekendAfternoon: return "土日祝"
        case .flexible: return "不定期"
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 検索モード切替
                    Picker("Search Mode", selection: $searchMode) {
                        Text("Real (対面)").tag("Real")
                        Text("Online (バーチャル)").tag("Online")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    
                    // 検索バーとフィルターボタン
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(Color.tasukiPrimary.opacity(0.5))
                                .padding(.leading, 12)
                            
                            TextField("名前で検索", text: $searchText)
                                .font(.system(size: 16))
                                .foregroundColor(Color.tasukiPrimary)
                                .padding(.vertical, 12)
                                .padding(.trailing, 12)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.tasukiDarkCardSecondary)
                        )
                        
                        Button(action: {
                            showFilterSheet = true
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(Color.tasukiPrimary)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.tasukiDarkCardSecondary)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                            ForEach(filteredUsers) { user in
                            NavigationLink(destination: PartnerDetailView(user: user.toUser())) {
                                userCardView(user: user)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("パートナーを探す")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterView(
                    searchMode: searchMode,
                    selectedPrefecture: $selectedPrefecture,
                    selectedAgeGroups: $selectedAgeGroups,
                    selectedGender: $selectedGender,
                    runSpotText: $runSpotText,
                    selectedRunSpot: $selectedRunSpot,
                    selectedPurposes: $selectedPurposes,
                    selectedSchedules: $selectedSchedules,
                    selectedRanks: $selectedRanks,
                    nextRaceText: $nextRaceText,
                    runSpotSuggestions: runSpotSuggestions,
                    onApply: {
                        showFilterSheet = false
                    },
                    onReset: {
                        selectedPrefecture = "All"
                        selectedAgeGroups = []
                        selectedGender = "All"
                        runSpotText = ""
                        selectedRunSpot = ""
                        selectedPurposes = []
                        selectedSchedules = []
                        selectedRanks = []
                        nextRaceText = ""
                    }
                )
            }
        }
    }
    
    // MARK: - User Card View
    private func userCardView(user: PartnerUser) -> some View {
        HStack(spacing: 16) {
            // アバター画像（左端、彩度を落とす）
            if let avatarImage = user.avatarImage {
                Image(systemName: avatarImage)
                    .font(.system(size: 48))
                    .foregroundColor(Color.tasukiPrimary)
                    .saturation(0)  // モノトーン調
                    .frame(width: 56, height: 56)
            } else {
                Circle()
                    .fill(Color.tasukiDarkCardSecondary)
                    .frame(width: 56, height: 56)
            }
            
            // ユーザー情報
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // ユーザー名 + バッジ（公認マーク風）とランク
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(user.name)
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundColor(Color.tasukiPrimary)
                        if let tier = PointBadgeHelper.tier(forTotalPoints: user.totalPoints) {
                            Image(systemName: tier.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(tier.color)
                        }
                        Text("Rank \(user.rank)")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // ステータスインジケーター（右端）
                HStack(spacing: 6) {
                    Circle()
                        .fill(user.isOnline ? Color.royalBlue : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                    
                    Text(user.isOnline ? "オンライン" : "オフライン")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiDarkCardSecondary)
        )
    }
}

// MARK: - Filter View
struct FilterView: View {
    let searchMode: String
    @Binding var selectedPrefecture: String
    @Binding var selectedAgeGroups: Set<String>
    @Binding var selectedGender: String
    @Binding var runSpotText: String
    @Binding var selectedRunSpot: String
    @Binding var selectedPurposes: Set<String>
    @Binding var selectedSchedules: Set<String>
    @Binding var selectedRanks: Set<String>
    @Binding var nextRaceText: String
    let runSpotSuggestions: [String]
    let onApply: () -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) var dismiss
    
    private let prefectures = allPrefectures
    // ageGroups, purposes, schedules は Models.swift のグローバル定数を直接参照
    private let genders = ["All", "Male", "Female", "Other"]
    private let ranks = ["S", "A", "B", "C", "D"]
    private let rankLabels = ["S (Elite)", "A (Athlete)", "B (Advanced)", "C (General)", "D (Starter)"]
    
    @State private var showRunSpotSuggestions = false
    
    // フィルターされたランスポット候補
    private var filteredRunSpotSuggestions: [String] {
        if runSpotText.isEmpty {
            return []
        }
        return runSpotSuggestions.filter { spot in
            spot.localizedCaseInsensitiveContains(runSpotText)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Basic Info セクション
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Basic Info")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Color.tasukiPrimary)
                                .padding(.horizontal, 20)
                            
                            Divider()
                                .padding(.horizontal, 20)
                            
                            // Prefecture
                            VStack(alignment: .leading, spacing: 12) {
                                Text("都道府県")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                Picker("Prefecture", selection: $selectedPrefecture) {
                                    ForEach(prefectures, id: \.self) { prefecture in
                                        Text(prefecture).tag(prefecture)
                                    }
                                }
                                .pickerStyle(.menu)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.tasukiDarkCardSecondary)
                                )
                            }
                            .padding(.horizontal, 20)
                            
                            // Age Group
                            VStack(alignment: .leading, spacing: 12) {
                                Text("年齢")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(ageGroups, id: \.self) { ageGroup in
                                        tagButton(
                                            text: ageGroup,
                                            isSelected: selectedAgeGroups.contains(ageGroup),
                                            action: {
                                                if selectedAgeGroups.contains(ageGroup) {
                                                    selectedAgeGroups.remove(ageGroup)
                                                } else {
                                                    selectedAgeGroups.insert(ageGroup)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Gender
                            VStack(alignment: .leading, spacing: 12) {
                                Text("性別")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                Picker("Gender", selection: $selectedGender) {
                                    ForEach(genders, id: \.self) { gender in
                                        Text(gender).tag(gender)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .disabled(searchMode == "Real")
                                
                                // Realモード時の注釈
                                if searchMode == "Real" {
                                    HStack(spacing: 6) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.tasukiAccent)
                                        Text("安全のため同性のみ表示しています")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Style セクション
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Style")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Color.tasukiPrimary)
                                .padding(.horizontal, 20)
                            
                            Divider()
                                .padding(.horizontal, 20)
                            
                            // Run Spot (入力サジェスト)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ランニングスポット")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("例: 皇居", text: $runSpotText)
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.tasukiPrimary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.tasukiDarkCardSecondary)
                                        )
                                        .onChange(of: runSpotText) { oldValue, newValue in
                                            showRunSpotSuggestions = !newValue.isEmpty && !filteredRunSpotSuggestions.isEmpty
                                        }
                                    
                                    // サジェストリスト
                                    if showRunSpotSuggestions {
                                        VStack(alignment: .leading, spacing: 4) {
                                            ForEach(filteredRunSpotSuggestions, id: \.self) { suggestion in
                                                Button(action: {
                                                    selectedRunSpot = suggestion
                                                    runSpotText = suggestion
                                                    showRunSpotSuggestions = false
                                                }) {
                                                    HStack {
                                                        Text(suggestion)
                                                            .font(.system(size: 14))
                                                            .foregroundColor(Color.tasukiPrimary)
                                                        Spacer()
                                                    }
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 10)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color.tasukiDarkCardSecondary)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    
                                    // 選択されたランスポット表示
                                    if !selectedRunSpot.isEmpty {
                                        HStack {
                                            Text(selectedRunSpot)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(Color.tasukiOnBrandYellow)
                                            
                                            Button(action: {
                                                selectedRunSpot = ""
                                                runSpotText = ""
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(Color.tasukiOnBrandYellow.opacity(0.75))
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(Color.tasukiPrimaryButtonFill)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Purpose
                            VStack(alignment: .leading, spacing: 12) {
                                Text("目的")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(purposes, id: \.self) { purpose in
                                        tagButton(
                                            text: purpose,
                                            isSelected: selectedPurposes.contains(purpose),
                                            action: {
                                                if selectedPurposes.contains(purpose) {
                                                    selectedPurposes.remove(purpose)
                                                } else {
                                                    selectedPurposes.insert(purpose)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Schedule
                            VStack(alignment: .leading, spacing: 12) {
                                Text("スケジュール")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(schedules, id: \.self) { schedule in
                                        tagButton(
                                            text: schedule,
                                            isSelected: selectedSchedules.contains(schedule),
                                            action: {
                                                if selectedSchedules.contains(schedule) {
                                                    selectedSchedules.remove(schedule)
                                                } else {
                                                    selectedSchedules.insert(schedule)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Level セクション
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Level")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Color.tasukiPrimary)
                                .padding(.horizontal, 20)
                            
                            Divider()
                                .padding(.horizontal, 20)
                            
                            // Class (Rank)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ランク")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(Array(zip(ranks, rankLabels)), id: \.0) { rank, label in
                                        tagButton(
                                            text: label,
                                            isSelected: selectedRanks.contains(rank),
                                            action: {
                                                if selectedRanks.contains(rank) {
                                                    selectedRanks.remove(rank)
                                                } else {
                                                    selectedRanks.insert(rank)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Next Race
                            VStack(alignment: .leading, spacing: 12) {
                                Text("次回のレース")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                
                                TextField("例: 東京マラソン2025", text: $nextRaceText)
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.tasukiPrimary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.tasukiDarkCardSecondary)
                                    )
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, 20)
                }
            }
            .navigationTitle("フィルター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundColor(Color.tasukiPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("リセット") {
                        onReset()
                    }
                    .foregroundColor(Color.tasukiAccent)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    onApply()
                }) {
                    HStack {
                        Spacer()
                        Text("フィルターを適用")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                        Spacer()
                    }
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.tasukiPrimaryButtonFill)
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .background(Color.white)
            }
        }
    }
    
    // MARK: - Tag Button
    private func tagButton(text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? Color.tasukiOnBrandYellow : Color.tasukiPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.tasukiPrimaryButtonFill : Color.tasukiDarkCardSecondary)
                )
        }
    }
}

#Preview {
    PartnerView()
}
