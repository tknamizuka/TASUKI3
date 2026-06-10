import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// FIND（インターネット異性紹介事業）向けコンプライアンス状態と Callable API。
@MainActor
final class FindComplianceService: ObservableObject {
    static let shared = FindComplianceService()

    struct ComplianceState: Equatable {
        var identityVerificationStatus: String = "unverified"
        var emailVerified: Bool = false
        var findFeatureEnabled: Bool = false
        var accountStatus: String = "active"
        var genderVerified: String = "other"

        var isVerifiedForFind: Bool {
            identityVerificationStatus == "verified"
                && findFeatureEnabled
                && accountStatus == "active"
        }
    }

    struct LegalDisclosure: Equatable {
        var businessName: String = "TASUKI"
        var registrationNumber: String = "届出番号（準備中）"
        var registrationAuthority: String = "届出公安委員会（準備中）"
        var address: String = ""
        var contactEmail: String = ""
        var serviceLabel: String = "インターネット異性紹介業"
    }

    @Published private(set) var compliance = ComplianceState()
    @Published private(set) var legal = LegalDisclosure()
    @Published private(set) var isLoading = false
    @Published var lastErrorMessage: String?

    private let findConsentKey = "tasuki.find.introductionServiceConsent.v1"
    private lazy var db = Firestore.firestore()
    private lazy var functions = Functions.functions(region: "asia-northeast1")

    private init() {}

    var hasAcceptedFindConsent: Bool {
        UserDefaults.standard.bool(forKey: findConsentKey)
    }

    func markFindConsentAccepted() {
        UserDefaults.standard.set(true, forKey: findConsentKey)
    }

    var canAccessFindFeatures: Bool {
        compliance.isVerifiedForFind
            && Auth.auth().currentUser?.isEmailVerified == true
            && Auth.auth().currentUser?.isAnonymous == false
            && hasAcceptedFindConsent
    }

    func refresh() async {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            compliance = ComplianceState()
            return
        }
        isLoading = true
        defer { isLoading = false }
        lastErrorMessage = nil

        do {
            _ = try await callDictionary("ensureUserComplianceDefaults", data: [:])
            let snap = try await db.collection("users").document(user.uid).getDocument()
            if let data = snap.data() {
                applyUserCompliance(data, emailVerified: user.isEmailVerified)
            }
            await loadLegalConfig()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func submitIdentityVerification() async throws {
        let result = try await callDictionary("submitIdentityVerification", data: [:])
        if let status = result["status"] as? String {
            compliance.identityVerificationStatus = status
        }
        if let enabled = result["findFeatureEnabled"] as? Bool {
            compliance.findFeatureEnabled = enabled
        }
        await refresh()
    }

    func sendMatchRequest(
        toUid: String,
        payload: MatchInvitePayload,
        sourceScreen: String = "UserProfileDetailView"
    ) async throws -> String {
        var data: [String: Any] = [
            "toUid": toUid,
            "message": payload.message,
            "location": payload.location,
            "isWeeklyRecurring": payload.weeklyRepeat,
            "proposedStart": ISO8601DateFormatter().string(from: payload.runDate),
            "sourceScreen": sourceScreen,
        ]
        if let weekday = payload.recurrenceWeekday {
            data["recurrenceWeekday"] = weekday
        }
        let result = try await callDictionary("sendMatchRequest", data: data)
        guard let requestId = result["requestId"] as? String else {
            throw FindComplianceError.invalidResponse
        }
        return requestId
    }

    func acceptMatchRequest(requestId: String) async throws -> String {
        let result = try await callDictionary("acceptMatchRequest", data: ["requestId": requestId])
        guard let conversationId = result["conversationId"] as? String else {
            throw FindComplianceError.invalidResponse
        }
        return conversationId
    }

    func declineMatchRequest(requestId: String) async throws {
        _ = try await callDictionary("declineMatchRequest", data: ["requestId": requestId])
    }

    func blockUser(blockedUid: String) async throws {
        _ = try await callDictionary("blockUser", data: ["blockedUid": blockedUid])
    }

    func logProfileView(targetUid: String, sourceScreen: String) async {
        _ = try? await callDictionary("logProfileView", data: [
            "targetUid": targetUid,
            "sourceScreen": sourceScreen,
        ])
    }

    func isOppositeSex(with otherGender: String) -> Bool {
        let mine = compliance.genderVerified
        let other = Self.normalizeGender(otherGender)
        return (mine == "male" && other == "female") || (mine == "female" && other == "male")
    }

    static func normalizeGender(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "男性", "male": return "male"
        case "女性", "female": return "female"
        default: return "other"
        }
    }

    private func applyUserCompliance(_ data: [String: Any], emailVerified: Bool) {
        let c = data["compliance"] as? [String: Any] ?? [:]
        compliance = ComplianceState(
            identityVerificationStatus: c["identityVerificationStatus"] as? String ?? "unverified",
            emailVerified: emailVerified,
            findFeatureEnabled: c["findFeatureEnabled"] as? Bool ?? false,
            accountStatus: c["accountStatus"] as? String ?? "active",
            genderVerified: (data["genderVerified"] as? String) ?? Self.normalizeGender(data["gender"] as? String ?? "")
        )
    }

    private func loadLegalConfig() async {
        do {
            let snap = try await db.collection("app_config").document("legal").getDocument()
            guard let data = snap.data() else { return }
            legal = LegalDisclosure(
                businessName: data["businessName"] as? String ?? legal.businessName,
                registrationNumber: data["registrationNumber"] as? String ?? legal.registrationNumber,
                registrationAuthority: data["registrationAuthority"] as? String ?? legal.registrationAuthority,
                address: data["address"] as? String ?? "",
                contactEmail: data["contactEmail"] as? String ?? "",
                serviceLabel: data["serviceLabel"] as? String ?? legal.serviceLabel
            )
        } catch {
            // Remote Config 未投入時はデフォルト表示
        }
    }

    private func callDictionary(_ name: String, data: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            functions.httpsCallable(name).call(data) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let dict = result?.data as? [String: Any] {
                    continuation.resume(returning: dict)
                } else {
                    continuation.resume(returning: [:])
                }
            }
        }
    }
}

enum FindComplianceError: LocalizedError {
    case invalidResponse
    case notEligible

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "サーバー応答が不正です"
        case .notEligible: return "FIND 機能を利用する条件を満たしていません"
        }
    }
}
