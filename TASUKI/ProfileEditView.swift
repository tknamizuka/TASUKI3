import SwiftUI

struct ProfileEditView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var userManager: UserManager

    // 永続化用ストレージ（Firestore と同期後もローカルキャッシュとして更新）
    @AppStorage("myName") private var storedName: String = "Hiro"
    @AppStorage("myAge") private var storedAge: String = "29"
    @AppStorage("myArea") private var storedArea: String = "Tokyo, Setagaya"
    @AppStorage("myRank") private var storedRank: String = "Rank A"
    @AppStorage("myGender") private var storedGender: String = "male"
    
    // Running Style
    @AppStorage("myPurpose") private var storedPurpose: String = "サブ3, 健康維持"
    @AppStorage("myRunningSpots") private var storedRunningSpots: String = "皇居, 代々木公園"
    @AppStorage("mySchedule") private var storedSchedule: String = "平日夜, 土日午前"
    
    // Records & Goals
    @AppStorage("myPersonalBest") private var storedPersonalBest: String = "Full 3:10:00"
    @AppStorage("myTargetTime") private var storedTargetTime: String = "Full 2:59:00"
    @AppStorage("myNextRace") private var storedNextRace: String = "東京マラソン2026"
    
    // Stats
    @AppStorage("myAvgPace") private var storedAvgPace: String = "5:30/km"
    @AppStorage("myMonthlyDist") private var storedMonthlyDist: String = "150km"
    
    // Bio
    @AppStorage("myBio") private var storedBio: String = "平日は仕事終わりに5-10km走ってます！週末は距離走やりたいです。"
    @AppStorage("realityMiningConsentEnabled") private var realityMiningConsentEnabled: Bool = false
    @AppStorage("runningDataSource") private var runningDataSourceRaw: String = RunningDataSource.all.rawValue
    
    // 編集用の一時状態
    @State private var name: String = ""
    @State private var age: String = ""
    @State private var area: String = ""
    @State private var rank: String = "Rank A"
    @State private var gender: String = "male"
    
    @State private var purpose: String = ""
    @State private var runningSpots: String = ""
    @State private var schedule: String = ""
    
    @State private var personalBest: String = ""
    @State private var targetTime: String = ""
    @State private var nextRace: String = ""
    
    @State private var avgPace: String = ""
    @State private var monthlyDist: String = ""
    
    @State private var bio: String = ""
    
    // 初期値スナップショット（変更検知用）
    @State private var initialSnapshot: ProfileSnapshot?
    @State private var showDiscardAlert = false
    @State private var integrationNotice: String?
    @State private var lastLoadedUser: User?
    @State private var isLoadingProfile = true
    @State private var isDeviceLinking = false
    @State private var saveErrorMessage: String?
    @State private var showSaveError = false

    #if DEBUG
    @State private var debugCoachCertified: Bool = false
    @State private var debugCoachProfileName: String = ""
    #endif

    private var selectedRunningDataSource: RunningDataSource {
        RunningDataSource(rawValue: runningDataSourceRaw) ?? .all
    }

    private var companionSources: [RunningDataSource] {
        RunningDataSource.allCases.filter { $0 != .all }
    }
    
    private var hasChanges: Bool {
        guard let snapshot = initialSnapshot else { return false }
        let current = ProfileSnapshot(
            name: name,
            age: age,
            area: area,
            rank: rank,
            gender: gender,
            purpose: purpose,
            runningSpots: runningSpots,
            schedule: schedule,
            personalBest: personalBest,
            targetTime: targetTime,
            nextRace: nextRace,
            avgPace: avgPace,
            monthlyDist: monthlyDist,
            bio: bio
        )
        return current != snapshot
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Form {
                // Section 1: Basic Info
                Section(header: Text("Basic Info")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("ニックネーム", text: $name, prompt: Text("例: けんじ, RunLover"))
                        Text("※本名は公開されません。ニックネームで登録してください。")
                            .font(.caption)
                            .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                    }
                    TextField("年齢", text: $age)
                        .keyboardType(.numberPad)
                    TextField("エリア/都道府県", text: $area)
                    Picker("性別", selection: $gender) {
                        ForEach(Gender.allCases, id: \.self) { genderOption in
                            Text(genderOption.displayName).tag(genderOption.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("Rank")
                        Spacer()
                        Text(rank)
                            .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                    }
                    Text("※ランクは登録時のタイムに基づいて決まります。変更するにはプロフィール登録し直してください。")
                        .font(.caption)
                        .foregroundColor(Color.tasukiPrimary.opacity(0.5))
                }
                
                // Section 2: Running Style
                Section(header: Text("Running Style")) {
                    TextField("目的", text: $purpose, prompt: Text("例: サブ3目標, 健康維持 (カンマ区切り)"))
                    TextField("ランニングスポット", text: $runningSpots, prompt: Text("例: 皇居, 駒沢公園 (カンマ区切り)"))
                    TextField("スケジュール", text: $schedule, prompt: Text("例: 平日朝, 土日祝 (カンマ区切り)"))
                }
                
                // Section 3: Records & Goals
                Section(header: Text("Records & Goals")) {
                    TextField("Personal Best", text: $personalBest, prompt: Text("例: Full 3:10:00"))
                    TextField("Target Time", text: $targetTime, prompt: Text("例: Full 2:59:00"))
                    TextField("次回のレース", text: $nextRace)
                }
                
                // Section 4: Stats
                Section(header: Text("Stats")) {
                    TextField("Avg Pace", text: $avgPace, prompt: Text("例: 5:30/km"))
                    TextField("Monthly Distance", text: $monthlyDist, prompt: Text("例: 150km"))
                }
                
                // Section 5: Bio
                Section(header: Text("Bio")) {
                    TextEditor(text: $bio)
                        .frame(height: 100)
                }

                Section(header: Text("Reality Mining")) {
                    Toggle(isOn: $realityMiningConsentEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("行動データ収集を許可")
                                .font(.system(size: 15, weight: .semibold))
                            Text("推奨精度向上のために、画面利用やランニング関連イベントを収集します。")
                                .font(.system(size: 12))
                                .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                        }
                    }
                    .tint(Color.tasukiAccent)
                }

                Section(header: Text("デバイス連携")) {
                    Picker("取得元", selection: Binding(
                        get: { selectedRunningDataSource },
                        set: { newValue in
                            runningDataSourceRaw = newValue.rawValue
                            RealityMiningManager.shared.trackEvent(
                                name: "running_data_source_changed",
                                properties: ["source": newValue.rawValue]
                            )
                        })
                    ) {
                        ForEach(RunningDataSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    Text("「すべて／Apple Health」はヘルスケアの記録を利用します。Garmin 等を選ぶとヘルスケアは使わず、TASUKI内の該当デバイス由来の記録のみ使います。")
                        .font(.caption)
                        .foregroundColor(Color.tasukiPrimary.opacity(0.6))

                    ForEach(companionSources) { source in
                        Button {
                            runningDataSourceRaw = source.rawValue
                            RealityMiningManager.shared.trackEvent(
                                name: "running_data_source_connect_attempt",
                                properties: ["source": source.rawValue]
                            )
                            openCompanionApp(for: source)
                        } label: {
                            HStack {
                                Text(source.displayName)
                                    .foregroundColor(Color.tasukiPrimary)
                                Spacer()
                                if selectedRunningDataSource == source {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color.tasukiAccent)
                                }
                            }
                        }
                        .disabled(isDeviceLinking)
                    }

                    if let integrationNotice {
                        Text(integrationNotice)
                            .font(.caption)
                            .foregroundColor(Color.tasukiAccent)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        authManager.signOut { result in
                            if case let .failure(error) = result {
                                print("Sign out failed: \(error.localizedDescription)")
                            }
                        }
                    } label: {
                        Text("ログアウト")
                    }
                }

                #if DEBUG
                Section(header: Text("開発者（コーチ認定のシミュレート）")) {
                    Toggle("コーチ認定済みとして扱う", isOn: $debugCoachCertified)
                        .onChange(of: debugCoachCertified) { newValue in
                            UserDefaults.standard.set(newValue, forKey: CoachCertificationManager.debugCoachCertifiedKey)
                            CoachCertificationManager.shared.refreshDebugCoachOverride()
                        }
                    TextField("coachProfileName（カタログキー）", text: $debugCoachProfileName)
                        .onChange(of: debugCoachProfileName) { newValue in
                            UserDefaults.standard.set(newValue, forKey: CoachCertificationManager.debugCoachProfileNameKey)
                            if debugCoachCertified {
                                CoachCertificationManager.shared.refreshDebugCoachOverride()
                            }
                        }
                    Text("本番では Firestore の users/{uid} に coachCertified / coachProfileName を設定してください。")
                        .font(.caption)
                        .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                }
                #endif
            }
            .disabled(isLoadingProfile || isDeviceLinking)
            if isLoadingProfile {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                ProgressView()
            } else if isDeviceLinking {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                ProgressView("連携を確認しています…")
            }
        }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("プロフィール編集")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if hasChanges {
                            showDiscardAlert = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveProfile()
                    }
                    .disabled(!hasChanges || isLoadingProfile || isDeviceLinking)
                }
            }
            .onChange(of: realityMiningConsentEnabled) { newValue in
                RealityMiningManager.shared.updateConsent(enabled: newValue)
            }
            .task {
                await loadProfileFromFirestore()
            }
            .onAppear {
                #if DEBUG
                debugCoachCertified = UserDefaults.standard.bool(forKey: CoachCertificationManager.debugCoachCertifiedKey)
                debugCoachProfileName = UserDefaults.standard.string(forKey: CoachCertificationManager.debugCoachProfileNameKey) ?? "廣 佳樹"
                #endif
            }
            .alert("保存に失敗しました", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .alert("変更を保存せずに戻りますか？", isPresented: $showDiscardAlert) {
                Button("キャンセル", role: .cancel) {}
                Button("保存せずに戻る", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("編集したプロフィールは保存されません。よろしいですか？")
            }
        }
    }
}

// 編集状態の比較用モデル
private struct ProfileSnapshot: Equatable {
    var name: String
    var age: String
    var area: String
    var rank: String
    var gender: String
    var purpose: String
    var runningSpots: String
    var schedule: String
    var personalBest: String
    var targetTime: String
    var nextRace: String
    var avgPace: String
    var monthlyDist: String
    var bio: String
}

private extension ProfileEditView {
    @MainActor
    func loadProfileFromFirestore() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            let user = try await userManager.fetchCurrentUserProfile()
            applyFormFrom(user)
            user.syncLocalProfileStorage()
            lastLoadedUser = user
            initialSnapshot = snapshotFromForm()
        } catch {
            loadFormFromAppStorage()
            lastLoadedUser = nil
            initialSnapshot = snapshotFromForm()
        }
    }

    func applyFormFrom(_ user: User) {
        name = user.name
        age = user.age > 0 ? String(user.age) : ""
        area = user.prefecture
        runningSpots = user.area.replacingOccurrences(of: "、", with: ", ")
        rank = user.rank
        gender = genderPickerRaw(fromFirestoreGender: user.gender)
        purpose = user.purpose
        schedule = user.schedule
        personalBest = user.personalBest
        targetTime = user.targetTime
        nextRace = user.nextRace
        avgPace = user.avgPace
        monthlyDist = user.editingMonthlyDistLabel
        bio = user.bio
    }

    func loadFormFromAppStorage() {
        name = storedName
        age = storedAge
        area = storedArea
        rank = storedRank
        gender = storedGender
        purpose = storedPurpose
        runningSpots = storedRunningSpots
        schedule = storedSchedule
        personalBest = storedPersonalBest
        targetTime = storedTargetTime
        nextRace = storedNextRace
        avgPace = storedAvgPace
        monthlyDist = storedMonthlyDist
        bio = storedBio
    }

    func snapshotFromForm() -> ProfileSnapshot {
        ProfileSnapshot(
            name: name,
            age: age,
            area: area,
            rank: rank,
            gender: gender,
            purpose: purpose,
            runningSpots: runningSpots,
            schedule: schedule,
            personalBest: personalBest,
            targetTime: targetTime,
            nextRace: nextRace,
            avgPace: avgPace,
            monthlyDist: monthlyDist,
            bio: bio
        )
    }

    func genderPickerRaw(fromFirestoreGender: String) -> String {
        switch fromFirestoreGender {
        case "男性": return Gender.male.rawValue
        case "女性": return Gender.female.rawValue
        default: return Gender.other.rawValue
        }
    }

    func genderFirestoreLabel(fromPicker raw: String) -> String {
        guard let g = Gender(rawValue: raw) else { return "無回答" }
        switch g {
        case .male: return "男性"
        case .female: return "女性"
        case .other: return "無回答"
        }
    }

    func parseMonthlyKm(_ raw: String) -> Double? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        let numeral = s.filter { $0.isNumber || $0 == "." }
        return Double(numeral)
    }

    func buildUserFromForm(base: User) -> User {
        let ageValue = Int(age.trimmingCharacters(in: .whitespaces)) ?? base.age
        let monthlyFromForm = parseMonthlyKm(monthlyDist)
        let newTarget = monthlyFromForm ?? base.monthlyTarget
        return User(
            id: base.id,
            name: name,
            profileImage: base.profileImage,
            profileImageUrl: base.profileImageUrl,
            bio: bio,
            rank: base.rank,
            age: max(0, ageValue),
            gender: genderFirestoreLabel(fromPicker: gender),
            purpose: purpose,
            prefecture: area,
            area: runningSpots,
            pace: base.pace,
            runningFrequency: base.runningFrequency,
            personalBest: personalBest,
            schedule: schedule,
            nextRace: nextRace,
            targetTime: targetTime,
            monthlyDistance: base.monthlyDistance,
            monthlyTarget: newTarget,
            avgPace: avgPace,
            totalPoints: base.totalPoints,
            monthlyPoints: base.monthlyPoints,
            matchRate: base.matchRate,
            lastLogin: base.lastLogin,
            spotName: runningSpots,
            latitude: base.latitude,
            longitude: base.longitude,
            distanceFromUserMock: base.distanceFromUserMock,
            monthlyGpsActivityCount: base.monthlyGpsActivityCount
        )
    }

    /// フォーム内容を @AppStorage に反映（保存成功時・ローカルのみ退避時）
    func syncStoredFromForm() {
        storedName = name
        storedAge = age
        storedArea = area
        storedRank = rank
        storedGender = gender
        storedPurpose = purpose
        storedRunningSpots = runningSpots
        storedSchedule = schedule
        storedPersonalBest = personalBest
        storedTargetTime = targetTime
        storedNextRace = nextRace
        storedAvgPace = avgPace
        storedMonthlyDist = monthlyDist
        storedBio = bio
    }

    func saveProfile() {
        Task { @MainActor in
            let base: User
            do {
                if let loaded = lastLoadedUser {
                    base = loaded
                } else {
                    base = try await userManager.fetchCurrentUserProfile()
                }
            } catch {
                syncStoredFromForm()
                initialSnapshot = snapshotFromForm()
                dismiss()
                return
            }

            let merged = buildUserFromForm(base: base)
            userManager.saveUserProfile(user: merged) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        merged.syncLocalProfileStorage()
                        self.syncStoredFromForm()
                        self.lastLoadedUser = merged
                        self.initialSnapshot = self.snapshotFromForm()
                        self.dismiss()
                    case .failure(let err):
                        self.saveErrorMessage = err.localizedDescription
                        self.showSaveError = true
                    }
                }
            }
        }
    }

    func openCompanionApp(for source: RunningDataSource) {
        integrationNotice = nil
        isDeviceLinking = true
        RunningDeviceIntegration.connect(source: source, openURL: openURL) { message in
            isDeviceLinking = false
            integrationNotice = message
        }
    }
}

#Preview {
    ProfileEditView()
        .environmentObject(AuthManager())
        .environmentObject(UserManager())
}