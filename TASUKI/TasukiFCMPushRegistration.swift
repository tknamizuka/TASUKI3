//
//  TasukiFCMPushRegistration.swift
//  TASUKI
//
//  FCM トークン取得と users/{uid} への保存（受信側の静音時間・タイムゾーンは Cloud Functions が参照）。
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

enum TasukiFCMPushRegistration {

    private static let quietStartKey = "pushQuietStartHour"
    private static let quietEndKey = "pushQuietEndHour"

    static func configureMessagingDelegate(_ delegate: MessagingDelegate) {
        Messaging.messaging().delegate = delegate
    }

    static func registerForRemoteNotifications(_ application: UIApplication) {
        application.registerForRemoteNotifications()
    }

    static func setApnsDeviceToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    static func handleRegistrationToken(_ fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        FirebaseBootstrap.configureIfNeeded()
        let db = Firestore.firestore()
        let tz = TimeZone.current.identifier
        let qs = (UserDefaults.standard.object(forKey: quietStartKey) as? Int) ?? 22
        let qe = (UserDefaults.standard.object(forKey: quietEndKey) as? Int) ?? 7
        db.collection("users").document(uid).setData(
            [
                "fcmToken": fcmToken,
                "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
                "pushTimeZone": tz,
                "pushQuietStartHour": qs,
                "pushQuietEndHour": qe
            ],
            merge: true
        ) { error in
            if let error {
                print("TasukiFCMPushRegistration: failed to save token: \(error.localizedDescription)")
            }
        }
    }

    /// 静音時間を変えたあと Firestore に反映したいとき
    static func syncQuietHoursToFirestoreIfLoggedIn() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        FirebaseBootstrap.configureIfNeeded()
        let qs = (UserDefaults.standard.object(forKey: quietStartKey) as? Int) ?? 22
        let qe = (UserDefaults.standard.object(forKey: quietEndKey) as? Int) ?? 7
        Firestore.firestore().collection("users").document(uid).setData(
            [
                "pushQuietStartHour": qs,
                "pushQuietEndHour": qe,
                "pushTimeZone": TimeZone.current.identifier
            ],
            merge: true
        )
    }
}
