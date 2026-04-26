# Firebase（マッチング Push）

## 概要

- アプリは `partnerMatchNotifyOutbox` にドキュメントを追加します。
- Cloud Functions が FCM で **受信者**に通知します。
- 受信者の `users/{uid}` に `pushTimeZone` / `pushQuietStartHour`（既定 22）/ `pushQuietEndHour`（既定 7）があり、**静音時間帯**なら `partnerMatchPushQueue` に積み、**翌（または当日）の終了時刻まで**遅延してから送ります。

## 前日・当日の練習リマインド

カレンダー由来のリマインドは **アプリ内のローカル通知**（`TasukiScheduleReminderScheduler`）のみです。ここでは Push しません。

## デプロイ

```bash
cd firebase/functions && npm install
cd ../..
firebase deploy --only functions --project YOUR_PROJECT_ID
```

初回は Blaze 課金の有効化が必要な場合があります。

## Firestore ルール（例）

```text
match /partnerMatchNotifyOutbox/{id} {
  allow create: if request.auth != null
    && request.resource.data.senderUid == request.auth.uid;
  allow read, update, delete: if false;
}
match /partnerMatchPushQueue/{id} {
  allow read, write: if false;
}
match /users/{userId} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

## 受信テスト

1. 受信側アカウントでアプリを起動しログイン（FCM トークンが `users/{uid}` に保存される）。
2. `User.firebaseUid` にその UID を設定できるプロフィール／Find のデータ経路を用意するか、Firestore で手動テスト用ユーザーを用意する。
3. 送信側からマッチングリクエストを送る。
