# TASUKI Cloud Functions

Reality mining の日次集計ジョブをここで実行します。

## Callable（クライアントから HTTPS Callable）

- `grantActivityPoints` — アプリ内アクティビティ用ポイント付与（本人のみ・Firestore 直接加算の代替）
- `grantTeamActivityPoints` — チームポイント加算（チームメンバーのみ）
- `postSpectatorCheer` — 沿道応援（既存）
- `submitEkidenLeg` — 駅伝区間提出（既存）

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
