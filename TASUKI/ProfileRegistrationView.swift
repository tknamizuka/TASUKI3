import SwiftUI
import Combine
import FirebaseAuth
import PhotosUI
import MapKit
import CoreLocation

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
    /// 検索キーワード（MapKit 補完用）
    @State private var activityAreaQuery: String = ""
    /// 選択済みエリア（「、」区切り）
    @State private var activityArea: String = ""
    /// 走る目的の検索キーワード（`purposes` をローカルフィルタ）
    @State private var purposeQuery: String = ""
    /// 選択済み目的（表示順・保存時は `", "` で連結して `myPurpose` / `User.purpose` に合わせる）
    @State private var selectedPurposes: [String] = []
    /// 連携するデータソースは1つのみ。`nil` は「連携しない」。
    @State private var selectedDevice: RunningDataSource? = nil
    @State private var integrationNotice: String?
    @State private var isDeviceLinking = false
    
    @StateObject private var areaSearchCompleter = ActivityAreaSearchCompleter()
    @State private var areaSearchDebounceTask: Task<Void, Never>?
    
    // ステップ管理
    @State private var currentStep: Int = 0
    
    // 利用規約・プライバシーポリシー同意（本文末尾までスクロール後に同意可能）
    @State private var termsAgreed: Bool = false
    @State private var privacyPolicyAgreed: Bool = false
    @State private var termsReadToEnd: Bool = false
    @State private var privacyReadToEnd: Bool = false
    
    // 保存状態
    @State private var isSaving: Bool = false
    @State private var saveErrorMessage: String?
    @State private var showSkipAlert: Bool = false
    
    private let genders = ["男性", "女性", "無回答"]
    
    private var totalSteps: Int { 10 }
    private var progress: CGFloat {
        CGFloat(currentStep + 1) / CGFloat(totalSteps)
    }

    private var availableDeviceSources: [RunningDataSource] {
        RunningDataSource.allCases.filter { $0 != .all }
    }
    
    /// 選択済みスポット名の一覧（表示用）
    private var selectedAreaSpots: [String] {
        activityArea
            .split(separator: "、")
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    
    /// 登録保存・AppStorage 用（ProfileEdit / MyProfile のカンマ区切りに合わせる）
    private var joinedPurposeString: String {
        selectedPurposes.joined(separator: ", ")
    }
    
    private var filteredRegistrationPurposes: [String] {
        let q = purposeQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return purposes }
        return purposes.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground.ignoresSafeArea()
                
                VStack(spacing: 32) {
                    progressBar
                        .padding(.top, 24)
                        .padding(.horizontal, 20)
                    
                    Spacer()
                    
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
                    
                    Button(action: {
                        handleNext()
                    }) {
                        Text(isSaving ? "保存中..." : (isLastStep ? "はじめる" : "次へ"))
                            .font(.headline)
                            .foregroundColor(isCurrentStepValid ? Color.tasukiOnBrandYellow : Color.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isCurrentStepValid ? Color.tasukiPrimaryButtonFill : Color.gray.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .disabled(!isCurrentStepValid || isSaving || isDeviceLinking)
                }
                
                if isDeviceLinking {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    ProgressView("連携を確認しています…")
                        .tint(Color.tasukiPrimary)
                }
            }
            .navigationTitle("プロフィール登録")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("閉じる") {
                        hideKeyboard()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if currentStep == 0 {
                            showSkipAlert = true
                        } else {
                            withAnimation {
                                currentStep = max(currentStep - 1, 0)
                            }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if currentStep == totalSteps - 1 {
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
                if let r = RunningDataSource(rawValue: runningDataSourceRaw), r != .all {
                    selectedDevice = r
                } else if let firstRaw = connectedRunningDevicesRaw.split(separator: ",").first.map(String.init),
                          let s = RunningDataSource(rawValue: firstRaw), s != .all {
                    selectedDevice = s
                } else {
                    selectedDevice = nil
                }
                areaSearchCompleter.updateRegion(forPrefecture: selectedPrefecture)
            }
            .onChange(of: selectedPrefecture) { _, newPref in
                areaSearchCompleter.updateRegion(forPrefecture: newPref)
                if !activityAreaQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    areaSearchCompleter.setQuery(activityAreaQuery)
                }
            }
            .onChange(of: currentStep) { _, step in
                if step == 7 {
                    areaSearchCompleter.updateRegion(forPrefecture: selectedPrefecture)
                    if !activityAreaQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        areaSearchCompleter.setQuery(activityAreaQuery)
                    }
                }
            }
            .onChange(of: activityAreaQuery) { _, newValue in
                areaSearchDebounceTask?.cancel()
                areaSearchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        areaSearchCompleter.setQuery(newValue)
                    }
                }
            }
            .onDisappear {
                areaSearchDebounceTask?.cancel()
            }
        }
    }
    
    // MARK: - Subviews / Logic
    
    private var isLastStep: Bool {
        currentStep == totalSteps - 1
    }
    
    private var isCurrentStepValid: Bool {
        switch currentStep {
        case 0:
            return termsAgreed
        case 1:
            return privacyPolicyAgreed
        case 2:
            return profileImage != nil
        case 3:
            return !username.trimmingCharacters(in: .whitespaces).isEmpty
        case 4:
            return selectedGender != nil
        case 5:
            let now = Date()
            let calendar = Calendar.current
            guard let minDate = calendar.date(byAdding: .year, value: -80, to: now),
                  let maxDate = calendar.date(byAdding: .year, value: -18, to: now) else {
                return true
            }
            return (minDate...maxDate).contains(birthDate)
        case 6:
            return !selectedPrefecture.isEmpty
        case 7:
            return !activityArea.trimmingCharacters(in: .whitespaces).isEmpty
        case 8:
            return !selectedPurposes.isEmpty
        case 9:
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
                    .fill(Color.tasukiPrimaryButtonFill)
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
                termsAgreementStep
            case 1:
                privacyAgreementStep
            case 2:
                questionTitle("プロフィール写真を選択してください")
                profilePhotoPicker
            case 3:
                questionTitle("お名前を教えてください")
                TextField("例）Hiro", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .textContentType(.name)
            case 4:
                questionTitle("性別を教えてください")
                HStack(spacing: 12) {
                    ForEach(genders, id: \.self) { gender in
                        selectableChip(title: gender, isSelected: selectedGender == gender) {
                            selectedGender = gender
                        }
                    }
                }
            case 5:
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
            case 6:
                questionTitle("お住まいの都道府県を教えてください")
                Picker("都道府県", selection: $selectedPrefecture) {
                    ForEach(allPrefectures, id: \.self) { prefecture in
                        Text(prefecture).tag(prefecture)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 180)
            case 7:
                activityAreaSearchStep
            case 8:
                purposeSearchStep
            case 9:
                wearableDeviceStep
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
    
    private var activityAreaSearchStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            questionTitle("よく走るエリアを教えてください")
            Text("キーワードで検索し、候補をタップして追加できます（複数選択可）")
                .font(.subheadline)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("例）皇居、代々木公園", text: $activityAreaQuery)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
            
            if !selectedAreaSpots.isEmpty {
                Text("選択中")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.tasukiPrimary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedAreaSpots, id: \.self) { spot in
                        selectedActivityAreaRow(storedLabel: spot) {
                            toggleActivityArea(spot: spot)
                        }
                    }
                }
            }
            
            Text("検索候補")
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if activityAreaQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("キーワードを入力すると地図から候補が表示されます")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                    } else if areaSearchCompleter.completions.isEmpty {
                        Text("候補が見つかりませんでした")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(areaSearchCompleter.completions.enumerated()), id: \.offset) { _, completion in
                            let label = Self.displayLabel(for: completion)
                            Button {
                                toggleActivityArea(spot: label)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(completion.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(Color.tasukiPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }
    
    private var purposeSearchStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            questionTitle("走る目的を教えてください")
            Text("キーワードで絞り込み、候補をタップして追加できます（複数選択可）")
                .font(.subheadline)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            TextField("例）サブ3、健康", text: $purposeQuery)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.none)
                .disableAutocorrection(true)
            
            if !selectedPurposes.isEmpty {
                Text("選択中")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.tasukiPrimary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedPurposes, id: \.self) { purpose in
                        selectedActivityAreaRow(storedLabel: purpose) {
                            togglePurpose(purpose)
                        }
                    }
                }
            }
            
            Text("候補")
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredRegistrationPurposes.isEmpty {
                        Text("候補が見つかりませんでした")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filteredRegistrationPurposes, id: \.self) { item in
                            Button {
                                togglePurpose(item)
                            } label: {
                                Text(item)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(Color.tasukiPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }
    
    private var wearableDeviceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            questionTitle("ウェアラブルデバイスを接続しますか？")
            Text("後から設定可能です。各サービスを選ぶと公式アプリが開きます。取得元に応じた走行は TASUKI に取り込まれた記録から集計され、Appleヘルスを経由しません。")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Button {
                selectedDevice = nil
                integrationNotice = "連携せずに進みます（後から設定できます）"
            } label: {
                HStack {
                    Image(systemName: selectedDevice == nil ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedDevice == nil ? Color.tasukiPrimary : .gray)
                    Text("連携しない")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedDevice == nil ? Color.tasukiPrimary.opacity(0.12) : Color.gray.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeviceLinking)
            
            let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(availableDeviceSources) { source in
                    Button {
                        integrationNotice = nil
                        selectRunningDevice(source)
                        guard selectedDevice == source else {
                            integrationNotice = "連携を解除しました"
                            return
                        }
                        isDeviceLinking = true
                        RunningDeviceIntegration.connect(source: source, openURL: openURL) { message in
                            isDeviceLinking = false
                            integrationNotice = message
                        }
                    } label: {
                        Text(source.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(selectedDevice == source ? Color.tasukiOnBrandYellow : Color.tasukiPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedDevice == source ? Color.tasukiPrimaryButtonFill : Color.gray.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeviceLinking)
                }
            }
            if let integrationNotice {
                Text(integrationNotice)
                    .font(.footnote)
                    .foregroundColor(Color.tasukiAccent)
            }
        }
    }
    
    private static func displayLabel(for completion: MKLocalSearchCompletion) -> String {
        if completion.subtitle.isEmpty {
            return completion.title
        }
        return "\(completion.title)（\(completion.subtitle)）"
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
                        .overlay(Circle().stroke(Color.tasukiPrimary, lineWidth: 3))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(Color.tasukiPrimary.opacity(0.3))
                        Text("タップして写真を選択")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(width: 200, height: 200)
                    .background(Circle().fill(Color.gray.opacity(0.1)))
                    .overlay(
                        Circle()
                            .stroke(Color.tasukiPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
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
    
    private var termsAgreementStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TASUKI（タスキ）利用規約")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(LegalTextAttributed.termsOfService(bodySize: 12))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            termsReadToEnd = true
                        }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            .frame(height: 220)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            if !termsReadToEnd {
                Text("本文を最後までスクロールすると同意できます")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            agreementRow(
                agreed: $termsAgreed,
                title: "TASUKI利用規約に同意する",
                isInteractive: termsReadToEnd
            )
        }
    }
    
    private var privacyAgreementStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("プライバシーポリシー")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(LegalTextAttributed.privacyPolicy(bodySize: 12))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            privacyReadToEnd = true
                        }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            .frame(height: 220)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            if !privacyReadToEnd {
                Text("本文を最後までスクロールすると同意できます")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            agreementRow(
                agreed: $privacyPolicyAgreed,
                title: "プライバシーポリシーに同意する",
                isInteractive: privacyReadToEnd
            )
        }
    }

    private func agreementRow(agreed: Binding<Bool>, title: String, isInteractive: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: agreed.wrappedValue ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundColor(agreed.wrappedValue ? Color.tasukiPrimary : .gray)
                .onTapGesture {
                    guard isInteractive else { return }
                    agreed.wrappedValue.toggle()
                }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture {
                    guard isInteractive else { return }
                    agreed.wrappedValue.toggle()
                }

            Spacer()
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .opacity(isInteractive ? 1 : 0.45)
        .allowsHitTesting(isInteractive)
    }
    
    private func questionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(Color.tasukiPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// 候補の `title（subtitle）` 形式を保存していても、表示は地名（タイトル）部分のみ
    private func shortPlaceDisplayName(_ stored: String) -> String {
        if let idx = stored.firstIndex(of: "（"), idx > stored.startIndex {
            return String(stored[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        return stored
    }
    
    private func selectedActivityAreaRow(storedLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.tasukiOnBrandYellow)
                Text(shortPlaceDisplayName(storedLabel))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.tasukiPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func selectableChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? Color.tasukiOnBrandYellow : Color.tasukiPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.tasukiPrimaryButtonFill : Color.gray.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
    
    private func toggleActivityArea(spot: String) {
        let trimmed = spot.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var items = activityArea
            .split(separator: "、")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        if let index = items.firstIndex(of: trimmed) {
            items.remove(at: index)
        } else {
            items.append(trimmed)
        }
        
        activityArea = items.joined(separator: "、")
    }
    
    private func togglePurpose(_ purpose: String) {
        let trimmed = purpose.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var next = selectedPurposes
        if let i = next.firstIndex(of: trimmed) {
            next.remove(at: i)
        } else {
            next.append(trimmed)
        }
        selectedPurposes = next
    }

    private func selectRunningDevice(_ source: RunningDataSource) {
        if selectedDevice == source {
            selectedDevice = nil
        } else {
            selectedDevice = source
        }
    }

    /// 生年月日の選択可能範囲（18〜80歳）
    private var allowedBirthDateRange: ClosedRange<Date> {
        let now = Date()
        let calendar = Calendar.current
        let maxDate = calendar.date(byAdding: .year, value: -18, to: now) ?? now
        let minDate = calendar.date(byAdding: .year, value: -80, to: now) ?? now
        return minDate...maxDate
    }
    
    private func handleNext() {
        guard isCurrentStepValid else { return }
        
        if isLastStep {
            saveProfile()
        } else {
            withAnimation {
                currentStep = min(currentStep + 1, totalSteps - 1)
            }
        }
    }

    private func saveProfile() {
        guard let profileImage = profileImage else {
            saveErrorMessage = "プロフィール写真を選択してください。"
            return
        }
        persistSelectedDevices()
        
        isSaving = true
        saveErrorMessage = nil
        
        let defaultRank = "Rank E"
        let purposeForSave = joinedPurposeString
        
        Task {
            let firebaseUser: FirebaseAuth.User
            if let current = Auth.auth().currentUser {
                firebaseUser = current
            } else {
                do {
                    let result = try await Auth.auth().signInAnonymously()
                    firebaseUser = result.user
                } catch {
                    let gender = selectedGender ?? "無回答"
                    let calendar = Calendar.current
                    let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
                    let computedAge = ageComponents.year ?? 0
                    
                    await MainActor.run {
                        UserDefaults.standard.set(username, forKey: "myName")
                        UserDefaults.standard.set(selectedPrefecture + " " + activityArea, forKey: "myArea")
                        UserDefaults.standard.set(purposeForSave, forKey: "myPurpose")
                        self.isSaving = false
                        self.skipProfileRegistration = false
                        EngagementSignals.touchSignificantInteraction()
                        self.onComplete?()
                    }
                    return
                }
            }
            
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
            
            let gender = selectedGender ?? "無回答"
            let calendar = Calendar.current
            let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
            let computedAge = ageComponents.year ?? 0
            
            let user = User(
                id: UUID(),
                name: username,
                profileImage: "runner",
                profileImageUrl: imageUrl,
                bio: "",
                rank: defaultRank,
                age: computedAge,
                gender: gender,
                purpose: purposeForSave,
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
                distanceFromUserMock: 0,
                monthlyGpsActivityCount: nil
            )
            
            await MainActor.run {
                userManager.saveUserProfile(user: user) { result in
                    DispatchQueue.main.async {
                        self.isSaving = false
                        switch result {
                        case .success:
                            user.syncLocalProfileStorage()
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
        guard let one = selectedDevice, one != .all else {
            connectedRunningDevicesRaw = ""
            runningDataSourceRaw = RunningDataSource.all.rawValue
            return
        }
        connectedRunningDevicesRaw = one.rawValue
        runningDataSourceRaw = one.rawValue
    }
}

// MARK: - エリア検索候補の加工（住宅系の除外・駅・公園等の優先）

private enum ActivityAreaCompletionFilter {
    static let maxResults = 20

    private static let residentialMarkers: [String] = [
        "丁目", "番地", "号室", "マンション", "アパート", "レジデンス", "コーポ", "ハイツ"
    ]

    private static let priorityKeywords: [String] = [
        "公園", "緑地", "河川敷", "駅", "グラウンド", "陸上", "スタジアム", "ドーム", "JR", "新幹線",
        "トラック", "広場", "城", "海浜", "林道", "遊歩道"
    ]

    static func shouldExclude(_ completion: MKLocalSearchCompletion) -> Bool {
        let t = completion.title + completion.subtitle
        return residentialMarkers.contains { t.contains($0) }
    }

    static func priorityScore(_ completion: MKLocalSearchCompletion) -> Int {
        let t = completion.title + completion.subtitle
        return priorityKeywords.reduce(0) { partial, keyword in
            partial + (t.contains(keyword) ? 2 : 0)
        }
    }

    static func process(_ raw: [MKLocalSearchCompletion]) -> [MKLocalSearchCompletion] {
        let filtered = raw.filter { !shouldExclude($0) }
        let sorted = filtered.sorted { priorityScore($0) > priorityScore($1) }
        return Array(sorted.prefix(maxResults))
    }
}

// MARK: - MapKit search (activity area)

@MainActor
final class ActivityAreaSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    
    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = [.pointOfInterest]
        c.region = PrefectureMapRegions.japanWide
        return c
    }()
    
    override init() {
        super.init()
        completer.delegate = self
        updateRegion(forPrefecture: "東京都")
    }
    
    /// プロフィールの「お住まいの都道府県」に合わせて検索バイアスを更新する。
    func updateRegion(forPrefecture name: String) {
        if let region = PrefectureMapRegions.region(for: name) {
            completer.region = region
        } else {
            completer.region = PrefectureMapRegions.japanWide
        }
    }
    
    func setQuery(_ fragment: String) {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        completer.queryFragment = trimmed
        if trimmed.isEmpty {
            completions = []
        }
    }
    
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.completions = ActivityAreaCompletionFilter.process(completer.results)
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.completions = []
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
