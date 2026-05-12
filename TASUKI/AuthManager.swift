import Foundation
import FirebaseAuth
import FirebaseCore
import Combine

/// 一時的な Personal Team（無料）向けビルド: HealthKit / Sign in with Apple の entitlement を外している間は `true`。
/// 有料 Apple Developer Program で capability を戻したら `false` にする。
enum TemporaryPersonalTeamBuild {
    static let isActive = true
}

enum SocialAuthProvider: CaseIterable, Identifiable {
    case apple
    case line
    case google
    case facebook

    var id: String { providerID }

    var providerID: String {
        switch self {
        case .apple:
            return "apple.com"
        case .line:
            // Firebase Authentication の OIDC で LINE を設定した場合の一般的な provider ID
            return "oidc.line"
        case .google:
            return "google.com"
        case .facebook:
            return "facebook.com"
        }
    }

    var displayName: String {
        switch self {
        case .apple: return "Apple IDで続行"
        case .line: return "LINEで続行"
        case .google: return "Googleで続行"
        case .facebook: return "Facebookで続行"
        }
    }

    var scopes: [String] {
        switch self {
        case .apple:
            return ["email", "name"]
        default:
            return []
        }
    }

    /// ログイン画面に並べるソーシャル（一時ビルドでは Apple を除外）
    static func loginMenuProviders() -> [SocialAuthProvider] {
        if TemporaryPersonalTeamBuild.isActive {
            return allCases.filter { $0 != .apple }
        }
        return Array(allCases)
    }

    var loginSystemImageName: String {
        switch self {
        case .apple: return "apple.logo"
        case .line: return "message.fill"
        case .google: return "globe"
        case .facebook: return "person.crop.square.fill"
        }
    }
}

final class AuthManager: ObservableObject {
    @Published var isUserLoggedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    /// 本番用
    convenience init() {
        self.init(forPreview: false)
    }
    
    /// プレビュー用: forPreview == true のときは Firebase に触れずクラッシュを防ぐ
    init(forPreview: Bool) {
        if forPreview {
            isUserLoggedIn = false
            authStateListener = nil
            return
        }
        FirebaseBootstrap.configureIfNeeded()
        isUserLoggedIn = Auth.auth().currentUser != nil
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isUserLoggedIn = (user != nil)
            }
        }
    }
    
    deinit {
        if let handle = authStateListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Auth Actions
    
    func signUp(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        isLoading = true
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error as NSError? {
                    if let authError = AuthErrorCode(rawValue: error.code) {
                        switch authError.code {
                        case .invalidEmail:
                            self.errorMessage = "メールアドレスの形式が正しくありません。"
                        case .emailAlreadyInUse:
                            self.errorMessage = "このメールアドレスは既に登録されています。同じアドレスで「ログイン」をお試しください。新規に別アカウントを作る場合は、別のメールアドレスをご利用ください。"
                        case .weakPassword:
                            self.errorMessage = "パスワードは6文字以上にしてください。"
                        default:
                            self.errorMessage = "エラーが発生しました。もう一度お試しください。"
                        }
                    } else {
                        self.errorMessage = "エラーが発生しました。もう一度お試しください。"
                    }
                    completion(.failure(error))
                } else {
                    self.errorMessage = ""
                    completion(.success(()))
                }
            }
        }
    }
    
    func signIn(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        isLoading = true
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error as NSError? {
                    if let authError = AuthErrorCode(rawValue: error.code) {
                        switch authError.code {
                        case .invalidEmail:
                            self.errorMessage = "メールアドレスの形式が正しくありません。"
                        case .wrongPassword:
                            self.errorMessage = "パスワードが間違っています。"
                        case .userNotFound:
                            self.errorMessage = "このメールアドレスは登録されていません。"
                        default:
                            self.errorMessage = "エラーが発生しました。もう一度お試しください。"
                        }
                    } else {
                        self.errorMessage = "エラーが発生しました。もう一度お試しください。"
                    }
                    completion(.failure(error))
                } else {
                    self.errorMessage = ""
                    completion(.success(()))
                }
            }
        }
    }

    func signIn(with provider: SocialAuthProvider, completion: @escaping (Result<Void, Error>) -> Void) {
        if TemporaryPersonalTeamBuild.isActive, provider == .apple {
            errorMessage = "Apple ID ログインは一時的に無効です（無料署名ビルド）。"
            completion(.failure(NSError(
                domain: "AuthManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )))
            return
        }

        isLoading = true
        errorMessage = ""

        let oauthProvider = OAuthProvider(providerID: provider.providerID)
        if !provider.scopes.isEmpty {
            oauthProvider.scopes = provider.scopes
        }

        Auth.auth().signIn(with: oauthProvider, uiDelegate: AuthUIDelegateHelper.shared) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error as NSError? {
                    self.isLoading = false
                    self.errorMessage = self.socialAuthErrorMessage(error, provider: provider)
                    completion(.failure(error))
                } else {
                    self.isLoading = false
                    self.errorMessage = ""
                    completion(.success(()))
                }
            }
        }
    }
    
    func signOut(completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try Auth.auth().signOut()
            DispatchQueue.main.async {
                self.isUserLoggedIn = false
            }
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    private func socialAuthErrorMessage(_ error: NSError, provider: SocialAuthProvider) -> String {
        if let authError = AuthErrorCode(rawValue: error.code) {
            switch authError.code {
            case .operationNotAllowed:
                return "\(provider.displayName) は現在利用できません。Firebase Console の認証設定を確認してください。"
            case .webContextAlreadyPresented:
                return "別のログイン画面が開いています。閉じてから再度お試しください。"
            case .webContextCancelled:
                return "ログインがキャンセルされました。"
            case .webNetworkRequestFailed:
                return "ネットワークエラーが発生しました。通信環境を確認してください。"
            case .accountExistsWithDifferentCredential:
                return "別のログイン方法で登録済みのアカウントです。既存の方法でログインしてください。"
            default:
                return "\(provider.displayName) でログインできませんでした。設定または通信状況を確認してください。"
            }
        }
        return "\(provider.displayName) でログインできませんでした。"
    }
}

