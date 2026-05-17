//
//  TasukiDevelopmentFlags.swift
//  TASUKI
//
//  Firestore API 無効時など、一時的に EKIDEN 周りのネットワークを切るためのフラグ。
//

import Foundation

enum TasukiDevelopmentFlags {
    /// `true` のとき、EKIDEN タブで `users/{uid}` の所属確認と観戦用一覧取得で Firestore を呼ばない（画面は参加ハブへ進む）。
    /// Cloud Firestore API を有効にしたら **必ず `false` に戻す**こと。
    /// 加えて `EkidenDataService` は API 未有効などの `PERMISSION_DENIED` を検知するとプロセス内で駅伝の Firestore 読み取りをモックへ切り替え、再接続ループによる重さを抑える。
    ///
    /// **コンソールについて**: `PerfPowerTelemetryClientRegistrationService` / `PPSClientDonation` / `SpringfieldUsage` はシミュレータの制限によるシステムログが多いです。
    /// `Failed to locate resource named "default.csv"` は MapKit 系の内部メッセージで出ることがあり、多くの場合アプリの不具合ではありません。
    /// Firestore の `WatchStream … API has not been used` は GCP で Firestore API を有効にするまで消えません（本フラグが `true` でも、他モジュールの購読が残ると出ます）。
    static let skipFirestoreEkidenTabReads = true

    /// `true` のとき、EKIDEN タブは **固定サンプル `example_owner`** のみで即表示し、`userTeamId` の往復や `refreshFirestoreTeamAssociations` の連鎖を避けてスクロール負荷を抑える（一時的なモック運用）。
    /// 本番で実データに戻すときは `false` に。
    static let useUltraLightEkidenTabMock = true
}
