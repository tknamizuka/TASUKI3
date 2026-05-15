import SwiftUI
import UIKit
import AVFoundation // 追加
import FirebaseCore
import FirebaseAuth
import Combine

// MARK: - App State
enum AppState {
    case loading      // 起動時のチェック中
    case login        // 未ログイン
    case profileRegistration  // ログイン済みだがプロフィール未登録
    case main        // ログイン済みかつプロフィール登録済み
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // #region agent log
        DebugSession658Log.log(
            location: "AppDelegate.didFinishLaunching",
            message: "entry",
            hypothesisId: "H2",
            data: [:]
        )
        // #endregion
        FirebaseBootstrap.configureIfNeeded()
        configureTabBarAppearance()
        TasukiHandoffNotifier.requestAuthorizationIfNeeded()
        PointService.shared.resetMonthlyIfNeeded()
        // #region agent log
        DebugSession658Log.log(
            location: "AppDelegate.didFinishLaunching",
            message: "exit_ok",
            hypothesisId: "H2",
            data: [:]
        )
        // #endregion
        return true
    }
    
    /// タブバーの見た目を統一（MainTabView の init で行うとクラッシュするためここで実行）
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.white
        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor.secondaryLabel
        itemAppearance.selected.iconColor = .tasukiTabSelectedPurple
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.tasukiTabSelectedPurple]
        appearance.stackedLayoutAppearance = itemAppearance
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

@main
struct TASUKIApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authManager = AuthManager()
    @StateObject private var userManager = UserManager()
    @StateObject private var joinedPracticesStore = JoinedPracticesStore()
    @StateObject private var tabBarVisibility = TabBarVisibility()
    @State private var appState: AppState = .loading
    @State private var hasCompletedInitialCheck = false // 初回起動チェック完了フラグ
    private var cancellables = Set<AnyCancellable>()
    
    // アプリ起動時に一度だけ実行される初期化処理
    init() {
        // #region agent log
        DebugSession658Log.log(
            location: "TASUKIApp.init",
            message: "entry",
            hypothesisId: "H1",
            data: [:]
        )
        // #endregion
        // オーディオセッションを「Ambient」に設定
        // これにより、動画再生時の「ザー」というノイズ（オーディオエンジンの起動音）を抑制します
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio Session settings failed: \(error)")
        }
        // #region agent log
        DebugSession658Log.log(
            location: "TASUKIApp.init",
            message: "after_audio_session",
            hypothesisId: "H1",
            data: [:]
        )
        // #endregion
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.tasukiDarkBackground.ignoresSafeArea()
                switch appState {
                case .loading:
                    // スプラッシュ画面またはローディング表示
                    SplashView()
                        .environmentObject(authManager)
                        .environmentObject(userManager)
                case .login:
                    LoginView()
                        .environmentObject(authManager)
                        .environmentObject(userManager)
                case .profileRegistration:
                    ProfileRegistrationView(
                        onComplete: {
                            Task {
                                await updateAppState()
                            }
                        },
                        onReturnToLogin: {
                            authManager.signOut { _ in
                                Task { @MainActor in
                                    await updateAppState()
                                }
                            }
                        }
                    )
                    .environmentObject(authManager)
                    .environmentObject(userManager)
                case .main:
                    MainTabView()
                        .environmentObject(authManager)
                        .environmentObject(userManager)
                        .environmentObject(ConversationManager.shared)
                        .environmentObject(joinedPracticesStore)
                        .environmentObject(CoachCertificationManager.shared)
                        .environmentObject(tabBarVisibility)
                        .environmentObject(MatchInvitationStore.shared)
                        .environmentObject(RunProposalStore.shared)
                }
            }
            .onAppear {
                // #region agent log
                DebugSession658Log.log(
                    location: "TASUKIApp.WindowGroup_ZStack",
                    message: "root_onAppear",
                    hypothesisId: "H4",
                    data: ["appState": "\(appState)"]
                )
                // #endregion
            }
            .task {
                // 起動時に状態をチェック（きっかり2秒）
                await startApp()
            }
            .onReceive(authManager.$isUserLoggedIn) { _ in
                // ログイン状態が変わったら再チェック（待機時間なし）
                guard hasCompletedInitialCheck else { return } // 初回チェック完了後のみ
                Task {
                    await updateAppState()
                }
            }
            .onReceive(userManager.$hasProfile) { _ in
                // プロフィール状態が変わったら再チェック（待機時間なし）
                guard hasCompletedInitialCheck else { return } // 初回チェック完了後のみ
                Task {
                    await updateAppState()
                }
            }
            .onChange(of: scenePhase) { newPhase in
                switch newPhase {
                case .active:
                    RealityMiningManager.shared.trackEvent(name: "app_foreground")
                case .background:
                    RealityMiningManager.shared.trackEvent(name: "app_background")
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - State Management
    
    /// アプリ起動時の初期化処理（きっかり2秒で画面遷移）
    @MainActor
    private func startApp() async {
        // #region agent log
        DebugSession658Log.log(
            location: "TASUKIApp.startApp",
            message: "begin",
            hypothesisId: "H3",
            data: [:]
        )
        // #endregion
        RealityMiningManager.shared.trackEvent(name: "app_session_start")
        // 1. 現在時刻を記録
        let startTime = Date()
        
        // 2. ユーザーの状態チェック（非同期）
        let nextState = await checkUserStatus()
        
        // 3. 経過時間を計算
        let elapsedTime = Date().timeIntervalSince(startTime)
        let minDisplayTime: TimeInterval = 2.0 // 2秒固定
        
        // 4. 2秒に満たない場合、残りの時間だけ待機
        if elapsedTime < minDisplayTime {
            let remainingTime = minDisplayTime - elapsedTime
            do {
                try await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
            } catch {
                // キャンセルされた場合は待機をスキップ（通常は発生しない）
            }
        }
        
        // 5. 初回チェック完了フラグを設定
        hasCompletedInitialCheck = true
        
        // 6. メインスレッドで画面を切り替え
        withAnimation {
            self.appState = nextState
        }
        // #region agent log
        DebugSession658Log.log(
            location: "TASUKIApp.startApp",
            message: "state_applied",
            hypothesisId: "H3",
            data: ["nextState": "\(nextState)"]
        )
        // #endregion
        if nextState == .main {
            PointService.shared.syncFromRemoteIfNeeded()
        }
    }
    
    /// ユーザー状態判定ロジック（ヘルパー）
    @MainActor
    private func checkUserStatus() async -> AppState {
        // Firebase Authチェック
        guard let user = Auth.auth().currentUser else {
            return .login // 未ログイン
        }
        
        // プロフィール存在チェック (UserManagerを使用)
        let exists = await userManager.checkIfUserExists(uid: user.uid)
        
        // UserManagerのhasProfileも更新（後続の監視用）
        userManager.hasProfile = exists
        
        if exists {
            return .main // 登録済み -> メイン画面へ
        } else {
            return .profileRegistration // 未登録 -> プロフィール入力へ
        }
    }
    
    /// 初回起動後の状態更新（待機時間なし）
    @MainActor
    private func updateAppState() async {
        let nextState = await checkUserStatus()
        withAnimation {
            self.appState = nextState
        }
        if nextState == .main {
            PointService.shared.syncFromRemoteIfNeeded()
        }
    }
}
