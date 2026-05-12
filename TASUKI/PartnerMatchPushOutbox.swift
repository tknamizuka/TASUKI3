//
//  PartnerMatchPushOutbox.swift
//  TASUKI
//
//  マッチング送信時に Firestore に書き込み、Cloud Functions から FCM で相手に通知する。
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum PartnerMatchPushOutbox {

    /// 受信者の Firebase UID が分かっているときだけ Outbox に積む（未設定なら何もしない）。
    static func enqueue(recipientFirebaseUid: String?, senderDisplayName: String, requestId: String) {
        guard let recipientFirebaseUid, !recipientFirebaseUid.isEmpty else { return }
        guard let senderUid = Auth.auth().currentUser?.uid else { return }
        FirebaseBootstrap.configureIfNeeded()
        let db = Firestore.firestore()
        db.collection("partnerMatchNotifyOutbox").addDocument(data: [
            "recipientUid": recipientFirebaseUid,
            "senderUid": senderUid,
            "senderName": senderDisplayName,
            "requestId": requestId,
            "createdAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error {
                print("PartnerMatchPushOutbox: \(error.localizedDescription)")
            }
        }
    }
}
