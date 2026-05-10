//
//  RaceView.swift
//  TASUKI
//
//  距離別マッチング → 同時スタート → 走行タイムで競う
//

import SwiftUI
import Combine

// MARK: - Race Entry（カテゴリ選択 → マッチング）
struct RaceEntryView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var raceManager = RaceManager.shared
    @AppStorage("myName") private var myName = "Runner"
    @AppStorage("myRank") private var myRank = "Rank B"
    
    @State private var selectedCategory: LiveRaceCategory = .fiveK
    @State private var isMatching = false
    @State private var matchedRaceId: String?
    @State private var matchError: String?
    @State private var pendingCategory: LiveRaceCategory?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("LIVE RACE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(Color.tasukiMutedText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        
                        Text("対戦する距離を選んでください")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                        
                        VStack(spacing: 0) {
                            ForEach(LiveRaceCategory.allCases) { cat in
                                Button(action: {
                                    pendingCategory = cat
                                }) {
                                    TasukiFlatHubRow(
                                        title: raceHubTitle(cat),
                                        subtitle: "同時スタートでタイムを競う · 確認して参加",
                                        systemImage: "flag.checkered.2.crossed"
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isMatching)
                                .opacity(isMatching && selectedCategory != cat ? 0.5 : 1)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        if isMatching {
                            ProgressView("マッチング中...")
                                .padding(.top, 20)
                        }
                        if let err = matchError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(Color.tasukiDanger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
                        
                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("対戦")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.tasukiPrimary)
                }
            }
            .navigationDestination(item: $matchedRaceId) { rid in
                RaceLobbyView(raceId: rid, onDismissSheet: { dismiss() })
            }
        }
        .onAppear {
            matchError = nil
        }
        .confirmationDialog(
            "この距離でマッチングしますか？",
            isPresented: Binding(
                get: { pendingCategory != nil },
                set: { if !$0 { pendingCategory = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("マッチング開始") {
                guard let category = pendingCategory else { return }
                selectedCategory = category
                pendingCategory = nil
                startMatching()
            }
            Button("キャンセル", role: .cancel) {
                pendingCategory = nil
            }
        } message: {
            Text("参加後はロビーへ移動します。")
        }
    }
    
    private func raceHubTitle(_ cat: LiveRaceCategory) -> String {
        switch cat {
        case .fiveK: return "5KM"
        case .tenK: return "10KM"
        case .half: return "ハーフ"
        }
    }
    
    private func startMatching() {
        isMatching = true
        matchError = nil
        raceManager.matchOrCreate(category: selectedCategory, userName: myName, userRank: myRank) { result in
            isMatching = false
            switch result {
            case .success(let raceId):
                matchedRaceId = raceId
            case .failure(let e):
                matchError = e.localizedDescription
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Race Lobby（参加者表示・カウントダウン・スタート）
struct RaceLobbyView: View {
    let raceId: String
    var onDismissSheet: (() -> Void)?
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var raceManager = RaceManager.shared
    @State private var countdown: Int?
    @State private var hasNavigatedToRunning = false
    
    private var isHost: Bool {
        raceManager.currentRace?.hostUserId == raceManager.currentUserId
    }
    
    var body: some View {
        Group {
            if let race = raceManager.currentRace, let start = race.startTime {
                if Date() >= start || hasNavigatedToRunning {
                    RaceRunningView(raceId: raceId, startTime: start, onDismissSheet: onDismissSheet)
                } else if countdown != nil {
                    countdownView(until: start)
                } else {
                    lobbyContent(race: race)
                }
            } else {
                lobbyContent(race: raceManager.currentRace)
            }
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .onAppear {
            raceManager.startListening(raceId: raceId)
            if let start = raceManager.currentRace?.startTime, Date() >= start {
                hasNavigatedToRunning = true
            }
        }
        .onDisappear {
            if hasNavigatedToRunning { return }
            raceManager.stopListening()
        }
        .onChange(of: raceManager.currentRace?.startTime) { _, newStart in
            guard let start = newStart else { return }
            if Date() >= start {
                hasNavigatedToRunning = true
            } else {
                startCountdown(until: start)
            }
        }
    }
    
    private func lobbyContent(race: Race?) -> some View {
        VStack(spacing: 24) {
            if let race = race {
                Text(race.category?.displayName ?? race.distanceCategory)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Color.tasukiPrimary)
                Text("\(race.targetDistanceKm) km でタイムを競います")
                    .font(.subheadline)
                    .foregroundColor(Color.tasukiMutedText)
            }
            
            List(raceManager.participants) { p in
                HStack {
                    Text(p.name)
                        .foregroundColor(Color.tasukiPrimary)
                    if let r = p.rank, !r.isEmpty {
                        Text(r).font(.caption).foregroundColor(Color.tasukiMutedText)
                    }
                    Spacer()
                }
                .listRowBackground(Color.tasukiDarkCardSecondary.opacity(0.35))
            }
            .frame(maxHeight: 200)
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            if isHost && race?.status == .waiting {
                Button(action: {
                    raceManager.startRace(raceId: raceId, countdownSeconds: 5) { _ in }
                }) {
                    Text("スタート（5秒カウントダウン）")
                        .fontWeight(.semibold)
                        .foregroundColor(Color.tasukiOnBrandYellow)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.tasukiPrimaryButtonFill)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            
            if race?.status == .starting, race?.startTime != nil {
                Text("まもなくスタート...")
                    .foregroundColor(Color.tasukiMutedText)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ロビー")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("退出") {
                    raceManager.stopListening()
                    dismiss()
                }
                .foregroundColor(Color.tasukiDanger)
            }
        }
    }
    
    private func countdownView(until start: Date) -> some View {
        VStack(spacing: 24) {
            Text("スタートまで")
                .font(.headline)
                .foregroundColor(Color.tasukiMutedText)
            if let c = countdown, c > 0 {
                Text("\(c)")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(Color.tasukiAccent)
            } else {
                Text("Go!")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startCountdown(until: start) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("カウントダウン")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button("退出") {
                    raceManager.stopListening()
                    dismiss()
                }
                .foregroundColor(Color.tasukiDanger)
            }
        }
    }
    
    private func startCountdown(until start: Date) {
        if countdown != nil { return }
        countdown = max(0, Int(start.timeIntervalSince(Date())))
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            let sec = Int(start.timeIntervalSince(Date()))
            DispatchQueue.main.async {
                if sec <= 0 {
                    countdown = 0
                    t.invalidate()
                    raceManager.ensureRaceRunning(raceId: raceId, startTime: start)
                    hasNavigatedToRunning = true
                } else {
                    countdown = sec
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

// MARK: - Race Running（走行中・タイム・距離・ゴール）
struct RaceRunningView: View {
    let raceId: String
    let startTime: Date
    var onDismissSheet: (() -> Void)?
    @ObservedObject private var raceManager = RaceManager.shared
    @ObservedObject private var runTracker = RunTracker.shared
    @State private var elapsedTimer: Timer?
    @State private var updateDistanceTimer: Timer?
    @State private var elapsedSeconds: Double = 0
    @State private var hasSubmittedFinish = false
    @State private var showResults = false
    
    private var targetKm: Double {
        raceManager.currentRace?.targetDistanceKm ?? 5.0
    }
    
    var body: some View {
        VStack(spacing: 24) {
            if let race = raceManager.currentRace {
                if race.status == .finished || hasSubmittedFinish {
                    RaceResultsView(raceId: raceId, onDismissSheet: onDismissSheet)
                } else {
                    runningContent(race: race)
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
        .onAppear {
            raceManager.startListening(raceId: raceId)
            runTracker.start()
            startElapsedTimer()
            startDistanceUpdateTimer()
        }
        .onDisappear {
            elapsedTimer?.invalidate()
            updateDistanceTimer?.invalidate()
            if !hasSubmittedFinish {
                runTracker.stop()
            }
            if !showResults { raceManager.stopListening() }
        }
    }
    
    private func runningContent(race: Race) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Text(race.category?.displayName ?? race.distanceCategory)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.tasukiPrimary)
                
                Text(formatElapsed(elapsedSeconds))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.tasukiPrimary)
                
                HStack(spacing: 32) {
                    VStack {
                        Text(String(format: "%.2f", runTracker.distanceKm))
                            .font(.title2.bold())
                            .foregroundColor(Color.tasukiPrimary)
                        Text("km")
                            .font(.caption)
                            .foregroundColor(Color.tasukiMutedText)
                    }
                    Text("/")
                        .foregroundColor(Color.tasukiMutedText)
                    VStack {
                        Text(String(format: "%.1f", targetKm))
                            .font(.title2.bold())
                            .foregroundColor(Color.tasukiPrimary)
                        Text("km")
                            .font(.caption)
                            .foregroundColor(Color.tasukiMutedText)
                    }
                }
                
                if runTracker.distanceKm >= targetKm && !hasSubmittedFinish {
                    Button(action: submitFinish) {
                        Text("ゴールする")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.tasukiPrimaryButtonFill)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                } else {
                    Button(action: submitFinish) {
                        Text("ゴールする（距離に達していなくても記録）")
                            .font(.subheadline)
                            .foregroundColor(Color.tasukiAccent)
                    }
                }
                
                Divider()
                    .background(Color.tasukiDarkCardSecondary)
                Text("参加者")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(Color.tasukiMutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                List(raceManager.participants.sorted { ($0.finishTimeSeconds ?? .infinity) < ($1.finishTimeSeconds ?? .infinity) }) { p in
                    HStack {
                        Text(p.name)
                            .foregroundColor(Color.tasukiPrimary)
                        Spacer()
                        if let t = p.finishTimeSeconds {
                            Text(formatElapsed(t))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.green)
                        } else {
                            Text(String(format: "%.2f km", p.currentDistanceKm))
                                .font(.caption)
                                .foregroundColor(Color.tasukiMutedText)
                        }
                    }
                    .listRowBackground(Color.tasukiDarkCardSecondary.opacity(0.35))
                }
                .frame(minHeight: 120, maxHeight: 220)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("走行中")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
        }
    }
    
    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsedSeconds = Date().timeIntervalSince(startTime)
        }
        RunLoop.main.add(elapsedTimer!, forMode: .common)
    }
    
    private func startDistanceUpdateTimer() {
        updateDistanceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            raceManager.updateMyDistance(raceId: raceId, distanceKm: runTracker.distanceKm)
        }
        RunLoop.main.add(updateDistanceTimer!, forMode: .common)
    }
    
    private func submitFinish() {
        guard !hasSubmittedFinish else { return }
        hasSubmittedFinish = true
        runTracker.stop()
        raceManager.submitFinish(raceId: raceId, finishTimeSeconds: elapsedSeconds) { _ in }
        if raceManager.participants.allSatisfy({ $0.id == raceManager.currentUserId || $0.finishTimeSeconds != nil }) {
            raceManager.finishRace(raceId: raceId) { _ in }
        }
    }
    
    private func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}

// MARK: - Race Results（タイム順ランキング）
struct RaceResultsView: View {
    let raceId: String
    var onDismissSheet: (() -> Void)?
    @ObservedObject private var raceManager = RaceManager.shared
    
    private var ranked: [RaceParticipant] {
        raceManager.participants
            .filter { $0.finishTimeSeconds != nil }
            .sorted { ($0.finishTimeSeconds ?? 0) < ($1.finishTimeSeconds ?? 0) }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("RACE RESULT")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(Color.tasukiMutedText)
            
            Text("結果")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(Color.tasukiPrimary)
            
            List(Array(ranked.enumerated()), id: \.element.id) { index, p in
                HStack {
                    Text("\(index + 1)")
                        .font(.title2.bold())
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(width: 32)
                    Text(p.name)
                        .foregroundColor(Color.tasukiPrimary)
                    Spacer()
                    if let t = p.finishTimeSeconds {
                        Text(formatTime(t))
                            .font(.body.monospacedDigit())
                            .foregroundColor(Color.tasukiPrimary)
                    }
                }
                .listRowBackground(Color.tasukiDarkCardSecondary.opacity(0.35))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            Button(action: {
                raceManager.stopListening()
                onDismissSheet?()
            }) {
                Text("閉じる")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.tasukiPrimaryButtonFill)
                    .cornerRadius(12)
            }
            .padding()
        }
        .padding()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("結果")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
        }
        .onAppear {
            raceManager.startListening(raceId: raceId)
            let participants = ranked.map { (id: $0.id, name: $0.name) }
            PointService.shared.awardRacePointsIfNeeded(
                raceId: raceId,
                participants: participants,
                isSample: raceId.hasPrefix("sample_")
            )
        }
        .onDisappear {
            raceManager.stopListening()
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", m, s, ms)
    }
}

#Preview("対戦エントリ") {
    RaceEntryView()
}
