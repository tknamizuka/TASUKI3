import SwiftUI
import FirebaseAuth
import PhotosUI

struct ProfileRegistrationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var userManager: UserManager
    @AppStorage("skipProfileRegistration") private var skipProfileRegistration: Bool = false
    @AppStorage("runningDataSource") private var runningDataSourceRaw: String = RunningDataSource.all.rawValue
    @AppStorage("connectedRunningDevices") private var connectedRunningDevicesRaw: String = ""
    
    // 完了時のコールバック
    var onComplete: (() -> Void)? = nil
    
    // 入力値
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var profileImage: UIImage? = nil
    @State private var username: String = ""
    @State private var selectedGender: String? = nil
    @State private var birthDate: Date = Calendar.current.date(from: DateComponents(year: 1998, month: 1, day: 1)) ?? Date()
    @State private var selectedPrefecture: String = allPrefectures.first ?? "東京都"
    @State private var activityArea: String = ""
    @State private var selectedRunCategory: String? = nil  // ビギナー, 5k, 10k, ハーフ, フル
    @State private var runMinutes: String = ""            // カテゴリがビギナー以外のときの所要時間（分）
    @State private var selectedPurposes: [String] = []
    @State private var selectedDeviceSources: Set<RunningDataSource> = []
    @State private var integrationNotice: String?
    @State private var selectedBarrier: ContinuityBarrier?
    @State private var selectedLeaderboardComfort: LeaderboardComfort?
    
    // ステップ管理
    @State private var currentStep: Int = 0
    
    // 利用規約・プライバシーポリシー同意
    @State private var termsAgreed: Bool = false
    @State private var privacyPolicyAgreed: Bool = false
    @State private var showPrivacyPolicy: Bool = false
    
    // 保存状態
    @State private var isSaving: Bool = false
    @State private var saveErrorMessage: String?
    @State private var showSkipAlert: Bool = false
    
    private let genders = ["男性", "女性", "無回答"]
    private let runCategories = ["ビギナー", "5k", "10k", "ハーフ", "フル"]
    private let purposes = ["サブ3", "サブ3.5", "サブ4", "サブ5", "健康維持", "ダイエット", "完走", "自己ベスト更新", "その他"]
    // よく走るエリアの候補（予測用）
    private let areaSuggestions = ["皇居", "代々木公園", "駒沢公園", "多摩川", "大阪城公園", "中之島公園", "大濠公園", "名古屋城", "みなとみらい"]
    
    private var totalSteps: Int { 12 }
    private var progress: CGFloat {
        CGFloat(currentStep + 1) / CGFloat(totalSteps)
    }

    private var availableDeviceSources: [RunningDataSource] {
        RunningDataSource.allCases.filter { $0 != .all }
    }
    
    var body: some View {
        NavigationStack {
                    ZStack {
                        Color.white.ignoresSafeArea()
                        
                        VStack(spacing: 32) {
                            // プログレスバー
                            progressBar
                                .padding(.top, 24)
                                .padding(.horizontal, 20)
                            
                            Spacer()
                            
                            // 質問カード
                            ZStack {
                                stepView()
                                    .padding(.horizontal, 20)
                                    .transition(.asymmetric(insertion: .move(edge: .trailing),
                                                            removal: .move(edge: .leading)))
                            }
                            .animation(.easeInOut, value: currentStep)
                            
                            Spacer()
                            
                            if let message = saveErrorMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 20)
                            }
                            
                            // アクションボタン
                            Button(action: {
                                handleNext()
                            }) {
                                Text(isSaving ? "保存中..." : (isLastStep ? "はじめる" : "次へ"))
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(isCurrentStepValid ? Color(hex: "0F1A2E") : Color.gray.opacity(0.4))
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                            .disabled(!isCurrentStepValid || isSaving)
                        }
                    }
                    .navigationTitle("プロフィール登録")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        // キーボード用ツールバー
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("閉じる") {
                                hideKeyboard()
                            }
                        }
                        // ナビゲーション戻るボタン（ログイン画面へ戻る）
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                if currentStep == 0 {
                                    showSkipAlert = true
                                } else {
                                    withAnimation {
                                        if currentStep == 9, skipsTimeStep {
                                            currentStep = 7  // ビギナー選択時はカテゴリへ
                                        } else {
                                            currentStep = max(currentStep - 1, 0)
                                        }
                                    }
                                }
                            }) {
                                Image(systemName: "chevron.left")
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            if currentStep == 11 {
                                Button("スキップ") {
                                    handleNext()
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        hideKeyboard()
                    }
                    .alert("登録せずに利用しますか？", isPresented: $showSkipAlert) {
                        Button("キャンセル", role: .cancel) { }
                        Button("登録せずに利用する", role: .destructive) {
                            skipProfileRegistration = true
                            onComplete?()
                        }
                    } message: {
                        Text("プロフィールを登録せずにアプリを利用します。一部機能が制限される場合があります。")
                    }
                    .onAppear {
                        var initial = Set<RunningDataSource>()
                        let stored = connectedRunningDevicesRaw
                            .split(separator: ",")
                            .map { String($0) }
                        for raw in stored {
                            if let source = RunningDataSource(rawValue: raw) {
                                initial.insert(source)
                            }
                        }
                        if let selected = RunningDataSource(rawValue: runningDataSourceRaw), selected != .all {
                            initial.insert(selected)
                        }
                        selectedDeviceSources = initial
                    }
        }
    }
    
    // MARK: - Subviews / Logic
    
    private var isLastStep: Bool {
        currentStep == totalSteps - 1
    }
    
    /// カテゴリでビギナーを選んだ場合はタイム入力ステップをスキップ
    private var skipsTimeStep: Bool {
        selectedRunCategory == "ビギナー"
    }
    
    private var isCurrentStepValid: Bool {
        switch currentStep {
        case 0:
            return termsAgreed && privacyPolicyAgreed
        case 1:
            return profileImage != nil // プロフィール写真が必須
        case 2:
            return !username.trimmingCharacters(in: .whitespaces).isEmpty
        case 3:
            return selectedGender != nil
        case 4:
            // 生年月日が18〜80歳の範囲かどうか
            let now = Date()
            let calendar = Calendar.current
            guard let minDate = calendar.date(byAdding: .year, value: -80, to: now),
                  let maxDate = calendar.date(byAdding: .year, value: -18, to: now) else {
                return true
            }
            return (minDate...maxDate).contains(birthDate)
        case 5:
            return !selectedPrefecture.isEmpty
        case 6:
            return !activityArea.trimmingCharacters(in: .whitespaces).isEmpty
        case 7:
            return selectedRunCategory != nil
        case 8:
            // ビギナー以外のときのみこのステップに来る。分で入力（数値・1以上）
            guard let minVal = Int(runMinutes.trimmingCharacters(in: .whitespaces)), minVal > 0 else { return false }
            return true
        case 9:
            return !selectedPurposes.isEmpty
        case 10:
            return selectedBarrier != nil && selectedLeaderboardComfort != nil
        case 11:
            return true
        default:
            return false
        }
    }
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 6)
                
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color(hex: "0F1A2E"))
                    .frame(width: geometry.size.width * progress, height: 6)
            }
        }
        .frame(height: 6)
    }
    
    @ViewBuilder
    private func stepView() -> some View {
        VStack(spacing: 24) {
            switch currentStep {
            case 0:
                // 規約・プライバシー同意画面
                termsAndPrivacyView
            case 1:
                questionTitle("プロフィール写真を選択してください")
                profilePhotoPicker
            case 2:
                questionTitle("お名前を教えてください")
                TextField("例）Hiro", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            case 3:
                questionTitle("性別を教えてください")
                HStack(spacing: 12) {
                    ForEach(genders, id: \.self) { gender in
                        selectableChip(title: gender, isSelected: selectedGender == gender) {
                            selectedGender = gender
                        }
                    }
                }
            case 4:
                questionTitle("生年月日を教えてください")
                DatePicker(
                    "生年月日",
                    selection: $birthDate,
                    in: allowedBirthDateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .frame(height: 150)
            case 5:
                questionTitle("お住まいの都道府県を教えてください")
                Picker("都道府県", selection: $selectedPrefecture) {
                    ForEach(allPrefectures, id: \.self) { prefecture in
                        Text(prefecture).tag(prefecture)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 180)
            case 6:
                questionTitle("よく走るエリアを教えてください")
                VStack(alignment: .leading, spacing: 16) {
                    TextField("例）皇居、代々木公園", text: $activityArea)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    // エリアの予測候補（チップ）: 横並びで自動折り返し
                    let columns = [
                        GridItem(.adaptive(minimum: 90), spacing: 10)
                    ]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(areaSuggestions, id: \.self) { spot in
                            selectableChip(title: spot, isSelected: activityArea.components(separatedBy: "、").contains(spot)) {
                                toggleActivityArea(spot: spot)
                            }
                        }
                    }
                }
            case 7:
                questionTitle("走るカテゴリを教えてください")
                VStack(alignment: .leading, spacing: 16) {
                    let columns = [
                        GridItem(.adaptive(minimum: 90), spacing: 12)
                    ]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(runCategories, id: \.self) { category in
                            selectableChip(title: category, isSelected: selectedRunCategory == category) {
                                selectedRunCategory = category
                            }
                        }
                    }
                }
            case 8:
                questionTitle("その距離を何分で走りますか？")
                VStack(alignment: .leading, spacing: 16) {
                    Text("目安のタイム（分）で入力してください")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    TextField("例）25", text: $runMinutes)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
            case 9:
                questionTitle("ランニングの目的を教えてください（複数選択可）")
                // 画面内で折り返す横並びレイアウト（グリッド）
                let columns = [
                    GridItem(.adaptive(minimum: 90), spacing: 12)
                ]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(purposes, id: \.self) { purpose in
                        let isSelected = selectedPurposes.contains(purpose)
                        selectableChip(title: purpose, isSelected: isSelected) {
                            togglePurpose(purpose)
                        }
                    }
                }
            case 10:
                questionTitle("続けるときの障壁に近いものは？（ひとつ）")
                let barrierColumns = [GridItem(.adaptive(minimum: 100), spacing: 10)]
                LazyVGrid(columns: barrierColumns, alignment: .leading, spacing: 10) {
                    ForEach(ContinuityBarrier.allCases) { barrier in
                        selectableChip(title: barrier.displayName, isSelected: selectedBarrier == barrier) {
                            selectedBarrier = barrier
                        }
                    }
                }
                questionTitle("順位やランキングは？")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(LeaderboardComfort.allCases) { comfort in
                        selectableChip(title: comfort.displayName, isSelected: selectedLeaderboardComfort == comfort) {
                            selectedLeaderboardComfort = comfort
                        }
                    }
                }
                Text("後から Me タブでも変更できます。")
                    .font(.footnote)
                    .foregroundColor(.gray)
            case 11:
                questionTitle("ウェアラブルデバイスを接続しますか？")
                VStack(alignment: .leading, spacing: 16) {
                    Text("後から設定可能です。連携するサービスを選んでアプリを開き、Appleヘルス同期を有効にしてください。")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(availableDeviceSources) { source in
                            Button {
                                toggleDeviceSource(source)
                                openCompanionAppForRegistration(source)
                            } label: {
                                Text(source.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(selectedDeviceSources.contains(source) ? .white : Color(hex: "0F1A2E"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selectedDeviceSources.contains(source) ? Color(hex: "0F1A2E") : Color.gray.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let integrationNotice {
                        Text(integrationNotice)
                            .font(.footnote)
                            .foregroundColor(Color(hex: "2E5CFF"))
                    }
                }
            default:
                EmptyView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        )
    }
    
    private var profilePhotoPicker: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let profileImage = profileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(hex: "0F1A2E"), lineWidth: 3))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(Color(hex: "0F1A2E").opacity(0.3))
                        Text("タップして写真を選択")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(width: 200, height: 200)
                    .background(Circle().fill(Color.gray.opacity(0.1)))
                    .overlay(
                        Circle()
                            .stroke(Color(hex: "0F1A2E").opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    )
                }
            }
        }
        .onChange(of: selectedPhoto) { oldValue, newValue in
            Task {
                if let newValue = newValue {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            self.profileImage = image
                        }
                    }
                }
            }
        }
    }
    
    private var termsAndPrivacyView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text("TASUKI（タスキ）利用規約")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(hex: "0F1A2E"))

                ScrollView {
                    Text(LegalTexts.termsOfServiceText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.gray)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }

            // 利用規約同意
            agreementRow(
                agreed: $termsAgreed,
                title: "TASUKI利用規約に同意する"
            )

            // プライバシーポリシー同意
            VStack(alignment: .leading, spacing: 8) {
                agreementRow(
                    agreed: $privacyPolicyAgreed,
                    title: "プライバシーポリシーに同意する"
                )
                Button {
                    showPrivacyPolicy = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text("プライバシーポリシーを読む")
                            .font(.footnote)
                    }
                    .foregroundColor(Color(hex: "2E5CFF"))
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }

    private func agreementRow(agreed: Binding<Bool>, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: agreed.wrappedValue ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundColor(agreed.wrappedValue ? Color(hex: "0F1A2E") : .gray)
                .onTapGesture {
                    agreed.wrappedValue.toggle()
                }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "0F1A2E"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture {
                    agreed.wrappedValue.toggle()
                }

            Spacer()
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func questionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(Color(hex: "0F1A2E"))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func selectableChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .white : Color(hex: "0F1A2E"))
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(hex: "0F1A2E") : Color.gray.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
    
    /// 「よく走るエリア」の文字列に対して、候補スポットをトグル追加・削除する
    private func toggleActivityArea(spot: String) {
        var items = activityArea
            .split(separator: "、")
            .map { String($0) }
        
        if let index = items.firstIndex(of: spot) {
            // すでに含まれていれば削除
            items.remove(at: index)
        } else {
            // 含まれていなければ追加
            items.append(spot)
        }
        
        activityArea = items.joined(separator: "、")
    }
    
    /// ランニング目的の複数選択トグル
    private func togglePurpose(_ purpose: String) {
        if let index = selectedPurposes.firstIndex(of: purpose) {
            selectedPurposes.remove(at: index)
        } else {
            selectedPurposes.append(purpose)
        }
    }

    private func toggleDeviceSource(_ source: RunningDataSource) {
        if selectedDeviceSources.contains(source) {
            selectedDeviceSources.remove(source)
        } else {
            selectedDeviceSources.insert(source)
        }
    }

    private func openCompanionAppForRegistration(_ source: RunningDataSource) {
        if source == .appleHealth {
            DispatchQueue.main.async {
                integrationNotice = "Apple Health を接続対象に追加しました"
            }
            return
        }
        let links = source.deepLinks
        guard !links.isEmpty else {
            DispatchQueue.main.async {
                integrationNotice = "\(source.displayName) の起動リンクが未設定です"
            }
            return
        }

        func tryOpen(_ index: Int) {
            if index >= links.count {
                DispatchQueue.main.async {
                    if let appStore = source.appStoreURL {
                        openURL(appStore)
                        integrationNotice = "\(source.displayName) アプリが未インストールのためApp Storeを開きました"
                    } else {
                        integrationNotice = "\(source.displayName) を開けませんでした"
                    }
                }
                return
            }
            openURL(links[index]) { accepted in
                DispatchQueue.main.async {
                    if accepted {
                        integrationNotice = "\(source.displayName) を開きました"
                    } else {
                        tryOpen(index + 1)
                    }
                }
            }
        }
        tryOpen(0)
    }
    
    /// 登録タイムからランク（S,A,B,C,D,E）を算出
    ///
    /// ランク基準は「TASUKI ユーザーランク・タイム基準表」に合わせている。
    /// ビギナー or 分未入力の場合は最下位ランク（E）を付与する。
    private func computeRank(category: String?, minutes: Int?) -> String {
        guard let cat = category else { return "Rank E" }
        // ビギナー or 分未入力 → Rank E
        guard cat != "ビギナー",
              let min = minutes,
              min > 0 else {
            return "Rank E"
        }
        
        switch cat {
        case "5k":
            // 5km: S/A/B/C/D/E
            // S: 17:00未満
            if min < 17 { return "Rank S" }
            // A: 17:00〜21:30未満（≒22分未満で丸め）
            if min < 22 { return "Rank A" }
            // B: 21:30〜25:00未満
            if min < 25 { return "Rank B" }
            // C: 25:00〜30:00未満
            if min < 30 { return "Rank C" }
            // D: 30:00〜35:00未満
            if min < 35 { return "Rank D" }
            // E: 35:00以上
            return "Rank E"
            
        case "10k":
            // 10km
            // S: 35:30未満（≒36分未満）
            if min < 36 { return "Rank S" }
            // A: 35:30〜45:00未満
            if min < 45 { return "Rank A" }
            // B: 45:00〜52:00未満
            if min < 52 { return "Rank B" }
            // C: 52:00〜60:00未満
            if min < 60 { return "Rank C" }
            // D: 60:00〜70:00未満
            if min < 70 { return "Rank D" }
            // E: 70:00以上
            return "Rank E"
            
        case "ハーフ":
            // ハーフ（21.0975km）
            // S: 1:18:00未満（78分未満）
            if min < 78 { return "Rank S" }
            // A: 1:18:00〜1:40:00未満（100分未満）
            if min < 100 { return "Rank A" }
            // B: 1:40:00〜1:55:00未満（115分未満）
            if min < 115 { return "Rank B" }
            // C: 1:55:00〜2:15:00未満（135分未満）
            if min < 135 { return "Rank C" }
            // D: 2:15:00〜2:30:00未満（150分未満）
            if min < 150 { return "Rank D" }
            // E: 2:30:00以上
            return "Rank E"
            
        case "フル":
            // フル（42.195km）
            // S: 2:45:00未満（165分未満）
            if min < 165 { return "Rank S" }
            // A: 2:45:00〜3:30:00未満（210分未満）
            if min < 210 { return "Rank A" }
            // B: 3:30:00〜4:00:00未満（240分未満）
            if min < 240 { return "Rank B" }
            // C: 4:00:00〜4:30:00未満（270分未満）
            if min < 270 { return "Rank C" }
            // D: 4:30:00〜5:00:00未満（300分未満）
            if min < 300 { return "Rank D" }
            // E: 5:00:00以上
            return "Rank E"
            
        default:
            return "Rank E"
        }
    }
    
    /// 分を "3:30:00" / "1:25:00" 形式のラベルに変換
    private func formatMinutesToTimeLabel(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return String(format: "%d:%02d:00", h, m)
        }
        return String(format: "%d:00", m)
    }
    
    /// 生年月日の選択可能範囲（18〜80歳）
    private var allowedBirthDateRange: ClosedRange<Date> {
        let now = Date()
        let calendar = Calendar.current
        let maxDate = calendar.date(byAdding: .year, value: -18, to: now) ?? now
        let minDate = calendar.date(byAdding: .year, value: -80, to: now) ?? now
        return minDate...maxDate
    }

    // 生年月日を日本語表記で返す（例: 1998年1月1日）
    private var birthDateFormatted: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyy年MM月dd日"
        return df.string(from: birthDate)
    }
    
    private func handleNext() {
        guard isCurrentStepValid else { return }
        
        if isLastStep {
            saveProfile()
        } else {
            withAnimation {
                if currentStep == 7, skipsTimeStep {
                    currentStep = 9  // ビギナー選択時はタイム入力をスキップして目的へ
                } else {
                    currentStep = min(currentStep + 1, totalSteps - 1)
                }
            }
        }
    }
    
    private func persistEngagementPreferences() {
        if let b = selectedBarrier {
            UserDefaults.standard.set(b.rawValue, forKey: "tasuki.continuityBarrier")
        }
        if let c = selectedLeaderboardComfort {
            UserDefaults.standard.set(c.rawValue, forKey: "tasuki.leaderboardComfort")
            UserDefaults.standard.set(c == .prefersSoft, forKey: "reduceRankingPressure")
        }
    }

    private func saveProfile() {
        guard let profileImage = profileImage else {
            saveErrorMessage = "プロフィール写真を選択してください。"
            return
        }
        persistEngagementPreferences()
        persistSelectedDevices()
        
        isSaving = true
        saveErrorMessage = nil
        
        Task {
            // 1. ログインユーザーを確保（いなければ匿名ログイン）
            let firebaseUser: FirebaseAuth.User
            if let current = Auth.auth().currentUser {
                firebaseUser = current
            } else {
                do {
                    let result = try await Auth.auth().signInAnonymously()
                    firebaseUser = result.user
                } catch {
                    // Firebase 未設定やネットワーク不通などで匿名ログインに失敗した場合は
                    // ローカルのみでプロフィール情報を保存してモックフローとして完了させる
                    let gender = selectedGender ?? "無回答"
                    let purpose = selectedPurposes.isEmpty ? "その他" : selectedPurposes.joined(separator: ", ")
                    
                    // 生年月日から年齢を計算
                    let calendar = Calendar.current
                    let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
                    let computedAge = ageComponents.year ?? 0
                    
                    let runMinutesInt = Int(runMinutes.trimmingCharacters(in: .whitespaces))
                    let computedRank = computeRank(category: selectedRunCategory, minutes: runMinutesInt)
                    
                    // ランク情報をローカルに保持（検索・マッチング用）
                    UserDefaults.standard.set(computedRank, forKey: "myRank")
                    if selectedRunCategory == "フル", let min = runMinutesInt {
                        UserDefaults.standard.set(formatMinutesToTimeLabel(min), forKey: "myBestFull")
                    }
                    if selectedRunCategory == "ハーフ", let min = runMinutesInt {
                        UserDefaults.standard.set(formatMinutesToTimeLabel(min), forKey: "myBestHalf")
                    }
                    // 表示用の基本プロフィールもローカルに保存
                    UserDefaults.standard.set(username, forKey: "myName")
                    UserDefaults.standard.set(selectedPrefecture + " " + activityArea, forKey: "myArea")
                    
                    await MainActor.run {
                        self.isSaving = false
                        self.skipProfileRegistration = false
                        EngagementSignals.touchSignificantInteraction()
                        // Firebase には保存せず、モック完了としてホームへ遷移
                        self.onComplete?()
                    }
                    return
                }
            }
            
            // 2. 画像アップロードを最大15秒でタイムアウト（それ以上待たず登録を続行）
            var imageUrl: String? = nil
            await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    try? await StorageManager.shared.uploadProfileImage(profileImage, uid: firebaseUser.uid)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                imageUrl = first ?? nil
            }
            
            // 3. プロフィール情報を保存（画像URLは取得できた場合のみ設定）
            let gender = selectedGender ?? "無回答"
            let purpose = selectedPurposes.isEmpty ? "その他" : selectedPurposes.joined(separator: ", ")
            
            // 生年月日から年齢を計算
            let calendar = Calendar.current
            let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
            let computedAge = ageComponents.year ?? 0
            
            let runMinutesInt = Int(runMinutes.trimmingCharacters(in: .whitespaces))
            let computedRank = computeRank(category: selectedRunCategory, minutes: runMinutesInt)
            
            // 登録タイムをフィルター用に保存（ベストフル/ハーフ）
            UserDefaults.standard.set(computedRank, forKey: "myRank")
            if selectedRunCategory == "フル", let min = runMinutesInt {
                UserDefaults.standard.set(formatMinutesToTimeLabel(min), forKey: "myBestFull")
            }
            if selectedRunCategory == "ハーフ", let min = runMinutesInt {
                UserDefaults.standard.set(formatMinutesToTimeLabel(min), forKey: "myBestHalf")
            }
            
            let user = User(
                id: UUID(),
                name: username,
                profileImage: "runner",
                profileImageUrl: imageUrl,
                bio: "",
                rank: computedRank,
                age: computedAge,
                gender: gender,
                purpose: purpose,
                prefecture: selectedPrefecture,
                area: activityArea,
                pace: "",
                runningFrequency: "",
                personalBest: "",
                schedule: "",
                nextRace: "",
                targetTime: "",
                monthlyDistance: 0,
                monthlyTarget: 0,
                avgPace: "",
                totalPoints: 0,
                monthlyPoints: 0,
                matchRate: 0,
                lastLogin: Date(),
                spotName: activityArea,
                latitude: 0,
                longitude: 0,
                distanceFromUserMock: 0
            )
            
            await MainActor.run {
                userManager.saveUserProfile(user: user) { result in
                    DispatchQueue.main.async {
                        self.isSaving = false
                        switch result {
                        case .success:
                            EngagementSignals.touchSignificantInteraction()
                            self.onComplete?()
                        case .failure(let error):
                            self.saveErrorMessage = "保存に失敗しました。時間をおいて再度お試しください。（\(error.localizedDescription)）"
                        }
                    }
                }
            }
        }
    }

    private func persistSelectedDevices() {
        let sorted = selectedDeviceSources
            .filter { $0 != .all }
            .sorted { $0.rawValue < $1.rawValue }
        connectedRunningDevicesRaw = sorted.map(\.rawValue).joined(separator: ",")
        if let current = RunningDataSource(rawValue: runningDataSourceRaw), sorted.contains(current) {
            runningDataSourceRaw = current.rawValue
        } else if let first = sorted.first {
            runningDataSourceRaw = first.rawValue
        } else {
            runningDataSourceRaw = RunningDataSource.all.rawValue
        }
    }
}

// MARK: - Keyboard Dismiss Helper
private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

#Preview {
    ProfileRegistrationView()
        .environmentObject(AuthManager())
        .environmentObject(UserManager())
}

