//
//  EkidenDeviceSampleDataSeeder.swift
//  TASUKI
//
//  実機で EKIDEN の「チームを探す」「チームをつくる」「ランダム参加」を試すためのサンプル teams を Firestore に投入する（DEBUG のみ）。
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// 実機テスト用。App Store ビルドでは無効。
enum TasukiEkidenDeviceSampleConfig {
    /// `true` のとき、DEBUG ビルドかつログイン済みで初回のみ `teams` にデモデータを書き込む。
    /// 再投入したい場合は UserDefaults のキー `EkidenDeviceSampleDataSeeder.seedCompletedKey` を削除するか、アプリを削除して再インストール。
    static let seedSampleTeamsOnFirstLaunch = true
}

enum EkidenDeviceSampleDataSeeder {
    static let seedCompletedKey = "tasuki_ekiden_device_sample_teams_seeded_v1"

    /// `TeamView` などから呼ぶ。Release では空実装。
    static func seedIfNeeded() async {
        #if DEBUG
        guard TasukiEkidenDeviceSampleConfig.seedSampleTeamsOnFirstLaunch else { return }
        guard !TasukiDevelopmentFlags.skipFirestoreEkidenTabReads else { return }
        guard UserDefaults.standard.bool(forKey: seedCompletedKey) == false else { return }
        guard Auth.auth().currentUser != nil else { return }

        let db = Firestore.firestore()
        let batch = db.batch()
        let createdAt = Timestamp(date: Date())
        let demoOwner = "tasuki_seed_owner_demo"

        let entries: [(String, [String: Any])] = [
            // EKIDEN（real_ekiden）・承認不要・検索用プレフィックス「サンプルEKIDEN」
            ("tasuki_demo_real_open", [
                "name": "サンプルEKIDEN・芝ペース走",
                "createdAt": createdAt,
                "members": [] as [String],
                "inviteCode": "DEMOREAL",
                "requiresApproval": false,
                "maxMembers": 10,
                "ownerUid": demoOwner,
                "ekidenMode": EkidenJoinMode.realEkiden.firestoreValue
            ]),
            // EKIDEN・承認制・別コード
            ("tasuki_demo_real_approval", [
                "name": "サンプルEKIDEN・多摩川ロング",
                "createdAt": createdAt,
                "members": [] as [String],
                "inviteCode": "DEMORL02",
                "requiresApproval": true,
                "maxMembers": 10,
                "ownerUid": demoOwner,
                "ekidenMode": EkidenJoinMode.realEkiden.firestoreValue
            ]),
            // Distance Challenge（enjoy_ekiden）
            ("tasuki_demo_enjoy_open", [
                "name": "サンプルDistance・代々木ナイト",
                "createdAt": createdAt,
                "members": [] as [String],
                "inviteCode": "DEMOENJ1",
                "requiresApproval": false,
                "maxMembers": 10,
                "ownerUid": demoOwner,
                "ekidenMode": EkidenJoinMode.enjoyEkiden.firestoreValue
            ]),
            // Distance・移行前相当（ekidenMode なしでも Enjoy モードにマッチ）
            ("tasuki_demo_enjoy_legacy", [
                "name": "サンプルDistance・皇居ジョグ（レガシー）",
                "createdAt": createdAt,
                "members": [] as [String],
                "inviteCode": "DEMOENJ2",
                "requiresApproval": true,
                "maxMembers": 10,
                "ownerUid": demoOwner
            ])
        ]

        for (id, data) in entries {
            batch.setData(data, forDocument: db.collection("teams").document(id), merge: true)
        }

        do {
            try await commitBatch(batch)
            UserDefaults.standard.set(true, forKey: seedCompletedKey)
            print("[EkidenDeviceSampleDataSeeder] seeded \(entries.count) demo teams")
        } catch {
            print("[EkidenDeviceSampleDataSeeder] seed failed (Firestore ルールやオフラインを確認): \(error.localizedDescription)")
        }
        #endif
    }

    #if DEBUG
    private static func commitBatch(_ batch: WriteBatch) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            batch.commit { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }
    #endif
}
