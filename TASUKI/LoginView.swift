import SwiftUI

enum LoginSheetItem: Identifiable {
    case menu
    case terms
    case privacy
    var id: Int {
        switch self {
        case .menu: return 0
        case .terms: return 1
        case .privacy: return 2
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    @State private var sheetItem: LoginSheetItem? = nil
    @State private var showAccountInfoAlert: Bool = false

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // ロゴ / タイトル
                VStack(spacing: 8) {
                    Text("TASUKI")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundColor(Color.tasukiPrimary)
                        .tracking(6)
                    
                    Text("ログインして、仲間と走ろう")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.top, 40)
                
                // 入力フォーム
                VStack(spacing: 16) {
                    TextField("メールアドレス", text: $email)
                        .tasukiCredentialInputTypography()
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled(true)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.tasukiDarkCardSecondary)
                        )
                    
                    SecureField("パスワード", text: $password)
                        .tasukiCredentialInputTypography()
                        .textInputAutocapitalization(.never)
                        .textContentType(.password)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.tasukiDarkCardSecondary)
                        )
                }
                .padding(.horizontal, 24)
                
                // ボタン
                VStack(spacing: 12) {
                    Button(action: {
                        handleSignIn()
                    }) {
                        Text("ログイン")
                            .font(TasukiUI.credentialInputFont)
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.tasukiPrimaryButtonFill)
                            .cornerRadius(24)
                    }
                    .disabled(authManager.isLoading)
                    
                    Button(action: {
                        handleSignUp()
                    }) {
                        Text("新規登録")
                            .font(TasukiUI.credentialInputFont)
                            .foregroundColor(Color.tasukiPrimary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color.tasukiPrimary, lineWidth: 1)
                            )
                    }
                    .disabled(authManager.isLoading)
                }
                .padding(.horizontal, 24)

                socialLoginSection
                    .padding(.horizontal, 24)
                
                Spacer()
            }
            
            // ローディング表示
            if authManager.isLoading {
                Color.black.opacity(0.1)
                    .ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                sheetItem = .menu
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.tasukiSurface))
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .sheet(item: $sheetItem) { item in
            switch item {
            case .menu:
                LoginMenuSheet(onSelect: { action in
                    switch action {
                    case .terms:
                        sheetItem = .terms
                    case .privacy:
                        sheetItem = .privacy
                    case .contact:
                        openInquiryMailto()
                    case .account:
                        showAccountInfoAlert = true
                    }
                })
                .presentationDetents([.height(340)])
                .presentationBackground(.ultraThinMaterial)
            case .terms:
                TermsOfUseView()
            case .privacy:
                PrivacyPolicyView()
            }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("アカウント管理", isPresented: $showAccountInfoAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("メールアドレス・パスワードの変更や退会は、ログイン後に Me タブのプロフィール編集から行えます。")
        }
    }

    private func openInquiryMailto() {
        guard let url = URL(string: LegalTexts.supportInquiryMailto) else {
            errorMessage = "お問い合わせ用の設定がありません。"
            showError = true
            return
        }
        UIApplication.shared.open(url)
    }
    
    private func handleSignIn() {
        let normalizedEmail = normalizeEmailForAuth(email)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "メールアドレスとパスワードを入力してください。"
            showError = true
            return
        }
        email = normalizedEmail
        authManager.signIn(email: normalizedEmail, password: password) { result in
            switch result {
            case .success:
                break
            case .failure:
                errorMessage = authManager.errorMessage
                showError = true
            }
        }
    }

    private func normalizeEmailForAuth(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? trimmed
    }
    
    private func handleSignUp() {
        let normalizedEmail = normalizeEmailForAuth(email)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "メールアドレスとパスワードを入力してください。"
            showError = true
            return
        }
        email = normalizedEmail
        authManager.signUp(email: normalizedEmail, password: password) { result in
            switch result {
            case .success:
                break
            case .failure:
                errorMessage = authManager.errorMessage
                showError = true
            }
        }
    }

    private var socialLoginSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
                Text("または")
                    .font(.caption)
                    .foregroundColor(.gray)
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
            }

            socialButton(provider: .apple, icon: "apple.logo")
            socialButton(provider: .line, icon: "message.fill")
            socialButton(provider: .google, icon: "globe")
            socialButton(provider: .facebook, icon: "person.crop.square.fill")
        }
    }

    private func socialButton(provider: SocialAuthProvider, icon: String) -> some View {
        Button {
            handleSocialSignIn(provider)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 20)
                Text(provider.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .foregroundColor(Color.tasukiPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tasukiDarkCardSecondary)
            )
        }
        .disabled(authManager.isLoading)
    }

    private func handleSocialSignIn(_ provider: SocialAuthProvider) {
        authManager.signIn(with: provider) { result in
            switch result {
            case .success:
                break
            case .failure:
                errorMessage = authManager.errorMessage
                showError = true
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

