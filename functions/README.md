# TASUKI Cloud Functions

Reality mining の日次集計ジョブをここで実行します。

## Callable（クライアントから HTTPS Callable）

- `grantActivityPoints` — アプリ内アクティビティ用ポイント付与（本人のみ・Firestore 直接加算の代替）
- `grantTeamActivityPoints` — チームポイント加算（チームメンバーのみ）
- `postSpectatorCheer` — 沿道応援（既存）
- `submitEkidenLeg` — 駅伝区間提出（既存）
- `ensureUserComplianceDefaults` — FIND 用 `users.compliance` 初期化
- `submitIdentityVerification` — 本人確認申請（本番は eKYC Webhook と連携）
- `sendMatchRequest` / `acceptMatchRequest` / `declineMatchRequest` — マッチング（クライアント直書き禁止）
- `blockUser` / `logProfileView` — ブロック・紹介ログ

## ルール回帰テスト

```bash
cd functions
npm install
npm run test:rules
```

## 追加済みジョブ

- `aggregateBehaviorFeaturesDaily`
  - 実行時刻: 毎日 02:10 (Asia/Tokyo)
  - 入力: `users/{uid}/reality_events`
  - 出力: `users/{uid}/behavior_features/{yyyymmdd}`

## ローカル準備

1. Firebase CLI をインストール
2. このリポジトリのルートで Firebase プロジェクトを選択
3. 依存をインストール

```bash
cd functions
npm install
```

## デプロイ

```bash
cd ..
firebase deploy --only functions
```

## 補足

- `behavior_features` は `HomeView` で読み取って表示済みです。
- スコア正規化式（social/consistency）は `functions/index.js` で調整できます。
- FIND 開発用本人確認スタブ: デプロイ時に `ALLOW_DEV_IDENTITY_VERIFICATION=1` を設定。
- 届出標識は Firestore `app_config/legal` に投入（`docs/app_config_legal_seed.json` 参照）。
