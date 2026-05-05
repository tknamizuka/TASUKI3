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
    static let skipFirestoreEkidenTabReads = true
}
