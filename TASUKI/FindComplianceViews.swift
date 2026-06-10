import SwiftUI
import FirebaseAuth

/// FIND タブ全体を本人確認・同意でガードするラッパー。
struct FindComplianceGate<Content: View>: View {
    @ObservedObject private var complianceService = FindComplianceService.shared
    @State private var showConsentSheet = false
    @State private var isSubmittingVerification = false
    @State private var verificationMessage: String?
    let content: () -> Content

    var body: some View {
        Group {
            if complianceService.canAccessFindFeatures {
                VStack(spacing: 0) {
                    FindLegalDisclosureBanner(legal: complianceService.legal)
                    content()
                }
            } else {
                FindComplianceBlockedView(
                    compliance: complianceService.compliance,
                    legal: complianceService.legal,
                    isSubmitting: isSubmittingVerification,
                    verificationMessage: verificationMessage,
                    onRefresh: { Task { await complianceService.refresh() } },
                    onRequestVerification: { Task { await submitVerification() } },
                    onShowConsent: { showConsentSheet = true }
                )
            }
        }
        .task {
            await complianceService.refresh()
            if complianceService.compliance.isVerifiedForFind && !complianceService.hasAcceptedFindConsent {
                showConsentSheet = true
            }
        }
        .sheet(isPresented: $showConsentSheet) {
            FindIntroductionConsentSheet(legal: complianceService.legal) {
                complianceService.markFindConsentAccepted()
                showConsentSheet = false
            }
        }
    }

    private func submitVerification() async {
        isSubmittingVerification = true
        verificationMessage = nil
        defer { isSubmittingVerification = false }
        do {
            try await complianceService.submitIdentityVerification()
            verificationMessage = complianceService.lastErrorMessage ?? "本人確認を申請しました"
            if complianceService.compliance.isVerifiedForFind && !complianceService.hasAcceptedFindConsent {
                showConsentSheet = true
            }
        } catch {
            verificationMessage = error.localizedDescription
        }
    }
}

private struct FindLegalDisclosureBanner: View {
    let legal: FindComplianceService.LegalDisclosure

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(legal.serviceLabel)
                .font(.system(size: 10, weight: .bold))
            Text("届出: \(legal.registrationNumber)（\(legal.registrationAuthority)）")
                .font(.system(size: 9))
            Text(legal.businessName)
                .font(.system(size: 9))
        }
        .foregroundColor(Color.tasukiMutedText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.tasukiDarkBackground.opacity(0.95))
    }
}

private struct FindComplianceBlockedView: View {
    let compliance: FindComplianceService.ComplianceState
    let legal: FindComplianceService.LegalDisclosure
    let isSubmitting: Bool
    let verificationMessage: String?
    let onRefresh: () -> Void
    let onRequestVerification: () -> Void
    let onShowConsent: () -> Void

    private var authUser: FirebaseAuth.User? { Auth.auth().currentUser }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("FIND パートナーマッチング")
                    .font(.title2.bold())
                Text("この機能は\(legal.serviceLabel)に該当します。18歳以上の本人確認とメール確認が必要です。")
                    .font(.subheadline)
                    .foregroundColor(Color.tasukiMutedText)

                checklistRow(
                    title: "メール確認",
                    done: authUser?.isEmailVerified == true && authUser?.isAnonymous == false,
                    detail: authUser?.isAnonymous == true ? "匿名アカウントでは利用できません" : "登録メールの確認を完了してください"
                )
                checklistRow(
                    title: "本人確認（18歳以上）",
                    done: compliance.isVerifiedForFind,
                    detail: statusLabel(compliance.identityVerificationStatus)
                )
                checklistRow(
                    title: "サービス同意",
                    done: FindComplianceService.shared.hasAcceptedFindConsent,
                    detail: "異性紹介事業に関する説明への同意"
                )

                if let verificationMessage, !verificationMessage.isEmpty {
                    Text(verificationMessage)
                        .font(.footnote)
                        .foregroundColor(.orange)
                }

                if compliance.isVerifiedForFind {
                    Button("同意画面を開く", action: onShowConsent)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(isSubmitting ? "処理中…" : "本人確認を申請する", action: onRequestVerification)
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting || authUser?.isAnonymous == true || authUser?.isEmailVerified != true)
                }

                Button("状態を更新", action: onRefresh)
                    .font(.footnote)
            }
            .padding(20)
        }
        .background(Color.tasukiDarkBackground.ignoresSafeArea())
    }

    private func checklistRow(title: String, done: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? .green : Color.tasukiMutedText)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundColor(Color.tasukiMutedText)
            }
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "verified": return "確認済み"
        case "pending": return "審査中"
        case "rejected": return "確認できませんでした。サポートへお問い合わせください"
        default: return "未確認"
        }
    }
}

struct FindIntroductionConsentSheet: View {
    let legal: FindComplianceService.LegalDisclosure
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("インターネット異性紹介事業に関するご案内")
                        .font(.headline)
                    Text("TASUKI の FIND 機能は、ランニングパートナーとしての異性の方を紹介するサービスです。出会い・交際を主目的とした利用は禁止されています。")
                    Text("事業者: \(legal.businessName)")
                    Text("届出番号: \(legal.registrationNumber)")
                    Text("届出公安委員会: \(legal.registrationAuthority)")
                    if !legal.contactEmail.isEmpty {
                        Text("お問い合わせ: \(legal.contactEmail)")
                    }
                    Text("18歳未満の方、および高校生の方はご利用いただけません。")
                        .font(.footnote)
                        .foregroundColor(Color.tasukiMutedText)
                }
                .padding()
            }
            .navigationTitle("ご確認")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("同意して続ける") {
                        onAccept()
                        dismiss()
                    }
                }
            }
        }
    }
}
