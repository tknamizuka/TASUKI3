//
//  CoachCertificationManager.swift
//  TASUKI
//
//  管理者が Firestore で付与するコーチ認定を反映する。
//  users/{uid} に coachCertified: true, coachProfileName: "廣 佳樹" 等を設定する。
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// 認定コーチかどうか・公開プロフィールのキー（CoachProfileCatalog / CoachProfileView と一致）
@MainActor
final class CoachCertificationManager: ObservableObject {
    static let shared = CoachCertificationManager()

    @Published private(set) var isCertifiedCoach: Bool = false
    /// `CoachProfileCatalog.profile(for:)` に渡す名前（Firestore `coachProfileName`）
    @Published private(set) var coachProfileName: String = ""

    private var listener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.attachUserDocumentListener(uid: user?.uid)
            }
        }
    }

    private func attachUserDocumentListener(uid: String?) {
        listener?.remove()
        listener = nil
        guard let uid else {
            isCertifiedCoach = false
            coachProfileName = ""
            return
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: CoachCertificationManager.debugCoachCertifiedKey) {
            isCertifiedCoach = true
            coachProfileName = UserDefaults.standard.string(forKey: CoachCertificationManager.debugCoachProfileNameKey) ?? "廣 佳樹"
            return
        }
        #endif

        let db = Firestore.firestore()
        listener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            Task { @MainActor in
                self.applyUserDocumentData(snapshot?.data())
            }
        }
    }

    private func applyUserDocumentData(_ data: [String: Any]?) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: CoachCertificationManager.debugCoachCertifiedKey) {
            isCertifiedCoach = true
            coachProfileName = UserDefaults.standard.string(forKey: CoachCertificationManager.debugCoachProfileNameKey) ?? "廣 佳樹"
            return
        }
        #endif

        let certified = data?["coachCertified"] as? Bool ?? false
        let name = (data?["coachProfileName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isCertifiedCoach = certified
        coachProfileName = name
    }

    #if DEBUG
    static let debugCoachCertifiedKey = "tasuki.debug.coachCertified"
    static let debugCoachProfileNameKey = "tasuki.debug.coachProfileName"

    /// デバッグ用: UserDefaults を更新したあと呼び出す
    func refreshDebugCoachOverride() {
        attachUserDocumentListener(uid: Auth.auth().currentUser?.uid)
    }
    #endif
}
