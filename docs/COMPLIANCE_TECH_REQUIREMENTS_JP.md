# TASUKI コンプライアンス技術要件書（日本法対応）

> **位置づけ:** エンジニア向けの技術仕様・実装指針。法的助言ではない。届出要否・条文解釈は弁護士・所轄公安委員会等に確認すること。
>
> **前提（事業者の法的判断）:** FIND タブのパートナーマッチング機能（ユーザー発見・マッチングリクエスト・マッチ成立後の 1 対 1 チャット）は **インターネット異性紹介事業**（風営法）に該当する。本書はこの前提で技術要件を定義する。
>
> **対象外（本書の主眼外）:** 練習会チャット、チームチャット、駅伝、走行記録は別枠。ただし §4 の電気通信事業要件はメッセージ全般に適用。

---

## 目次

1. [適用範囲と判定ツリー](#1-適用範囲と判定ツリー)
2. [FIND / パートナーマッチング — コードパスマップ](#2-find--パートナーマッチング--コードパスマップ)
3. [インターネット異性紹介事業 — 技術要件（FIND 対象）](#3-インターネット異性紹介事業--技術要件find-対象)
4. [メッセージ機能 — 電気通信事業・プロバイダ責任](#4-メッセージ機能--電気通信事業プロバイダ責任)
5. [Firestore データモデル & Security Rules スケッチ](#5-firestore-データモデル--security-rules-スケッチ)
6. [Cloud Functions スケッチ](#6-cloud-functions-スケッチ)
7. [ギャップ分析（現状 TASUKI vs 要件）](#7-ギャップ分析現状-tasuki-vs-要件)
8. [フェーズ別実装ロードマップ（FIND 優先）](#8-フェーズ別実装ロードマップfind-優先)
9. [参考ファイル一覧](#9-参考ファイル一覧)

---

## 1. 適用範囲と判定ツリー

### 1.1 機能別の規制マッピング

```
TASUKI アプリ
├── FIND タブ（FindView）
│   ├── Runners 一覧 → UserProfileDetailView → マッチング招待
│   ├── Practices 検索 → PartnerDetailView → パートナー申請
│   └── FindMatchScore による「マッチ度」表示
├── メッセージ Hub（MessageListView）
│   ├── チャット（ConversationManager / ChatView）
│   ├── マッチングリクエスト（MatchInvitationStore / match_requests）
│   └── 承諾 → 1 対 1 チャット
├── チームチャット（TeamView → teams/{id}/teamChat）     … 異性紹介対象外想定
└── 練習会チャット（ConversationManager practiceId）   … 異性紹介対象外想定
```

### 1.2 判定ツリー（エンジニア向け）

```
Q1: 当該機能は異性との出会い・交際を目的とした紹介か？
  └─ FIND パートナーマッチング → YES（事業者判断で確定）
       → §3 全要件 + §4 メッセージ要件を適用

Q2: ユーザー間のテキスト送信を提供しているか？
  └─ 1 対 1 DM / マッチリクエスト本文 → YES
       → §4 を適用（異性紹介 DM は §3 のゲート通過後のみ）

Q3: 練習会・チームのみの利用か？
  └─ YES → §3 の eKYC ゲートは FIND 入口に限定（機能フラグ分離）
```

---

## 2. FIND / パートナーマッチング — コードパスマップ

### 2.1 ユーザー発見（異性紹介の「提示」）

| ステップ | ファイル | 処理内容 | 規制上の意味 |
|---------|----------|----------|--------------|
| FIND タブ表示 | `MainTabView.swift` → `FindView.swift` | タブ index 2 付近 | 異性紹介 UI の入口 |
| 候補取得 | `UserManager.fetchDiscoverUsers()` | `public_profiles` を limit 80 で全件取得（自分除外のみ） | **異性の提示**。性別・年齢・本人確認フィルタなし |
| スコアリング | `FindView.refreshMatchingUsers()` / `FindMatchScore` | ペース・エリア・スケジュール等で `matchRate` 算出 | 紹介アルゴリズム |
| 一覧表示 | `FindView.displayedRunnerUsers` | おすすめ上位 5 件 or 検索結果 | 異性含む候補の一覧提示 |
| プロフィール | `UserProfileDetailView.swift` | 性別・年齢表示（`UserPublicProfileScrollContent`） | 紹介対象の詳細提示 |

**Firestore:** `public_profiles/{uid}` — `firestore.rules` L117–124: 認証ユーザーなら誰でも `read` 可。

### 2.2 マッチングリクエスト（異性紹介の「申込み」）

| ステップ | ファイル | 処理内容 | 現状の問題 |
|---------|----------|----------|------------|
| 招待 UI | `UserProfileDetailView` → `MatchInviteComposerSheet` | 日時・場所・メッセージ入力 | **`onSubmit` はアラート表示のみ。Firestore 未送信** |
| パートナー申請 | `PartnerDetailView.swift` | `ConnectionStatus` を `.requested` に変更 | **ローカル UI のみ。サーバー永続化なし** |
| リクエスト保存 | `MatchInvitationStore.upsertRemote()` | `match_requests/{id}` へ merge | **`fromUid` 未設定、`toUid` が送信者 uid になるバグ疑い**。受信同期のみ本番相当 |
| リクエスト一覧 | `MessageListView` / `MatchInvitationStore.syncFromRemoteIfPossible()` | `toUid == 自分` かつ `status == open` | 受信側のみ |
| 承諾 | `MessageListView.RequestDetailView.acceptMatch()` | `JoinedPracticesStore` 追加 + `matchInvitationStore.remove` | **マッチ成立ログ・introduction 記録なし**。チャット ID は `match-{requestId}` のダミー |

**モデル:**

- `Models.ConnectionStatus` — `.none | .requested | .received | .matched`（UI 状態、`PartnerDetailView` ローカルのみ）
- `MessageListView.MatchRequestSummary` / `MatchRequestType.partner`
- `Models.Gender` — `male | female | other`（Firestore 上は `User.gender` 文字列「男性」「女性」等）

**Firestore Rules (`match_requests`):** L344–353

- `create`: `fromUid == auth.uid`, `toUid` 文字列, `status == 'open'`
- `read`: 当事者（`fromUid` or `toUid`）のみ
- `update`: 当事者、限定フィールドのみ

### 2.3 マッチ成立後 DM（異性紹介の「連絡」）

| ステップ | ファイル | 処理内容 |
|---------|----------|----------|
| チャット画面 | `ChatView.swift` | `conversationId` でメッセージ表示・送信 |
| 送信 | `ConversationManager.sendMessage()` | `conversations/{id}/messages` に `text`, `senderId`, `timestamp` |
| 会話作成 | `ConversationManager.createConversation()` | `participantIds: [myUid, partnerUid]` |
| 通報 | `ConversationManager.submitConversationReport()` | `reports` コレクション、`kind: conversation` |

**Firestore Rules (`conversations/messages`):** L297–310 — 参加者のみ read/create。メッセージ更新・削除不可（運営削除不可）。

### 2.4 関連だが FIND 外のコード

| ファイル | 備考 |
|----------|------|
| `PartnerView.swift` | 旧 Partner UI。Real モード同性限定 / Online 性別フィルタ。**FindView が主経路** |
| `ProfileRegistrationView.swift` | 性別・生年月日から年齢算出。**eKYC なし**。匿名ログイン fallback あり |
| `LegalTexts.swift` | 18 歳以上・出会い目的禁止の規約文言。**届出標識・異性紹介明示なし** |

---

## 3. インターネット異性紹介事業 — 技術要件（FIND 対象）

風営法・インターネット異性紹介業関連規則に基づく**システム実装**の要点。条文番号は実装時に法務と照合。

### 3.1 本人確認（eKYC）— 必須ゲート

**原則:** 異性への紹介（プロフィール閲覧・一覧表示・マッチリクエスト送信・受信・DM）の**いずれより前**に、インターネット異性紹介業で求められる本人確認を完了させる。

| 項目 | 技術要件 |
|------|----------|
| 確認手段 | eKYC ベンダー（TRUSTDOCK / Liquid / Polarify 等）API 連携。運転免許・マイナンバーカード等 |
| 確認内容 | 18 歳以上、本人同一性、性別（公的書類と整合） |
| 状態管理 | `users/{uid}.compliance.identityVerificationStatus`: `unverified \| pending \| verified \| rejected \| expired` |
| ゲート | `verified` 以外は FIND タブ・`public_profiles` 異性閲覧・`match_requests` create を **403** |
| 再確認 | 書類有効期限・疑義時の再 KYC フロー |
| 保存 | 確認日時・ベンダー transaction ID・結果コード（画像本体はベンダー側 or 暗号化ストレージ、保持期間は法務指示） |

**禁止:** 生年月日入力のみ、自己申告性別のみで紹介機能を解放すること。

### 3.2 メールアドレス確認

| 項目 | 技術要件 |
|------|----------|
| 実装 | Firebase Auth `emailVerified == true` 必須 |
| 匿名認証 | FIND / 異性紹介機能では **禁止**（`ProfileRegistrationView` の `signInAnonymously` fallback を FIND 前に排除） |
| ゲート | Cloud Functions / Rules で `request.auth.token.email_verified` を検証 |

### 3.3 18 歳以上 — サーバー側ゲート

| レイヤ | 要件 |
|--------|------|
| 登録 | 生年月日から 18 歳未満は `users` 作成不可（Functions） |
| eKYC | 書類ベースで 18 歳以上を確認（自己申告と不一致時は reject） |
| 高校生除外 | 学年・在籍確認は法務判断。最低限 eKYC 生年月日で判定 |
| 継続 | 確認失効ユーザーは FIND 機能を即停止 |

現状: `LegalTexts.swift` L22–40 に規約記載、`ProfileRegistrationView` で年齢計算。**サーバー強制なし**。

### 3.4 異性紹介ログ（誰を誰に、いつ）

**法定保存・監査対応のため、サーバー側で append-only に記録。**

```
introduction_events/{eventId}
  eventType: "profile_view" | "candidate_list_impression" | "match_request_sent"
           | "match_request_accepted" | "match_established" | "dm_first_message"
  actorUid: string
  targetUid: string
  actorGender: string          // verified 性別スナップショット
  targetGender: string
  isOppositeSexPair: bool     // サーバー計算（verified 性別ベース）
  matchRequestId?: string
  conversationId?: string
  sourceScreen: "FindView" | "UserProfileDetailView" | ...
  clientAppVersion: string
  createdAt: timestamp         // serverTimestamp
  ipHash?: string              // 法務指示に応じて
```

| イベント | トリガー（推奨） |
|----------|------------------|
| `profile_view` | `UserProfileDetailView` 表示 — Cloud Functions callable or サーバー API |
| `match_request_sent` | `match_requests` 作成時 — **Functions のみ**で create |
| `match_established` | 承諾時 — status を `accepted` に更新する Functions |
| `dm_first_message` | 初回 DM — `onCreate messages` trigger |

**注意:** クライアント直接書き込みは改ざん可能なため、**introduction_events の create は Admin SDK / Functions のみ**。

### 3.5 届出標識の表示（アプリ内）

インターネット異性紹介業の届出を行った後、**常時閲覧可能**な場所に表示。

| 表示項目（法務確定後に埋める） | UI 配置案 |
|-------------------------------|-----------|
| 届出番号 | FIND タブ上部フッター、設定 > 法的情報 |
| 届出公安委員会名 | 同上 |
| 事業者名称 | 同上 + 利用規約 |
| 所在地 | 同上 |
| 連絡先（メール・電話） | 同上 |
| 「インターネット異性紹介業」の明示 | FIND 初回表示モーダル + 設定 |

**技術:** `AppConfig` / Remote Config / Firestore `app_config/legal` で文言を配信し、App Store 審査なしで届出番号更新可能に。

### 3.6 禁止コンテンツフィルタ

| 対象 | 要件 |
|------|------|
| プロフィール | bio, purpose, statusMessage — NG ワード + ML モデレーション |
| マッチリクエスト | `message`, `location` — 送信前 Functions で検査 |
| DM | `messages.text` — 送信前検査 + 事後スキャン |
| 禁止例 | 売春・援助交際の勧誘、連絡先外部誘導、性的明示、金銭要求 |

**実装:** Cloud Functions `moderateText()` → `approved | flagged | rejected`。`rejected` は保存せずクライアントにエラー。

### 3.7 運営モデレーション（マッチリクエスト & DM）

| 機能 | 要件 |
|------|------|
| 管理画面 | 通報キュー、マッチリクエスト一覧、DM 参照（権限者のみ） |
| 措置 | アカウント停止、`match_requests` 取消、メッセージ非表示、マッチ解除 |
| SLA | 通報受付から初動までの目標時間（運用ポリシー、技術は通知 + ダッシュボード） |
| 監査 | 運営者操作を `admin_audit_log` に記録 |

現状: `ChatView` → `reports` 作成のみ。**read/update 不可（Rules L326）= 運営ツール未接続**。

### 3.8 FIND 機能のサーバー側統合（現状バラバラな経路の統一）

**必須リファクタ方針:**

1. マッチリクエスト送信は **Callable Function `sendMatchRequest(toUid, payload)`** に一本化
2. 承諾は **`acceptMatchRequest(requestId)`** のみ
3. `UserProfileDetailView` / `PartnerDetailView` のローカル状態を廃止し、`match_requests` + `connections` を正とする
4. 異性ペアのみマッチリクエスト可能（verified 性別ベース。`other` の扱いは法務指示）
5. 同性のみ表示モードは**異性紹介届出の範囲外**として feature flag 分離（届出内容と一致させる）

---

## 4. メッセージ機能 — 電気通信事業・プロバイダ責任

FIND 成立後 DM に加え、**練習会・チームチャット**にも共通適用。

### 4.1 利用者情報の外部送信

| 要件 | 実装 |
|------|------|
| 送信先開示 | Firebase/Google への送信を PP・設定画面で明示（`LegalTexts` / `DATA_INVENTORY` 整合） |
| オプトアウト不可の通信 | メッセージ配送に必要な処理である旨を説明 |

### 4.2 発信者特定

| フィールド | 用途 |
|-----------|------|
| `messages.senderUid` | 必須（現状 `senderId` ✅） |
| `messages.createdAt` | serverTimestamp 必須化 |
| `messages.clientMessageId` | 冪等性・重複検知 |
| 捜査照会 | `users/{uid}` + 本人確認 ID + Auth メール |

### 4.3 通報・削除・ブロック

| 機能 | 要件 | 現状 |
|------|------|------|
| 通報 | ユーザーから `reports` 作成 | ✅ `ChatView` / `ConversationManager` |
| ブロック | `blocks/{blockerUid}_{blockedUid}` | ❌ 未実装 |
| 削除 | 運営削除 + 送信者取り下げ（法務判断） | ❌ Rules で delete 不可 |
| 非表示 | `messages.moderationStatus = hidden` | ❌ 未実装 |

**ブロック時:** Functions が `match_requests` 取消、既存 `conversations` の送信を Rules で拒否。

### 4.4 レートリミット

| 対象 | 目安 |
|------|------|
| DM 送信 | 例: 30 通/分/ユーザー |
| マッチリクエスト | 例: 10 件/日/ユーザー |
| 新規会話作成 | 例: 20 件/日/ユーザー |

**実装:** Cloud Functions + Firestore `rate_limits/{uid}` or Redis（Firebase Extensions）。

### 4.5 メッセージ保存期間

- 法務・プライバシーポリシーで保持期間を定義
- 退会時: 匿名化 or 削除（`introduction_events` は法定保存期間中は保持の可能性 — 法務指示）

---

## 5. Firestore データモデル & Security Rules スケッチ

### 5.1 ユーザーコンプライアンスフィールド（`users/{uid}` 拡張）

```javascript
// users/{uid} — 本人のみ read、compliance.* はクライアント write 禁止
{
  email: string,
  birthDate: timestamp,              // 参考。eKYC が正
  genderSelfReport: string,          // 男性|女性|無回答（参考）
  genderVerified: string,            // eKYC 確定値。サーバー only write
  compliance: {
    identityVerificationStatus: "verified",
    identityVerifiedAt: timestamp,
    identityVerificationVendor: "trustdock",
    identityVerificationRef: "txn_xxx",
    emailVerified: true,
    findFeatureEnabled: true,        // サーバー only
    accountStatus: "active"          // active|suspended|banned
  }
}
```

### 5.2 マッチリクエスト（`match_requests/{id}` 改修）

```javascript
{
  fromUid: string,                   // 必須（現状 MatchInvitationStore で欠落）
  toUid: string,
  fromGenderVerified: string,        // Functions が snapshot
  toGenderVerified: string,
  isOppositeSexIntroduction: true,   // Functions が計算
  type: "partner",
  message: string,
  location: string,
  proposedStart: timestamp,
  status: "open|accepted|declined|dismissed|cancelled|moderation_rejected",
  createdAt: timestamp,
  updatedAt: timestamp,
  acceptedAt: timestamp | null,
  conversationId: string | null      // 承諾時に Functions が発行
}
```

### 5.3 マッチ成立（`connections/{id}` 新規）

```javascript
{
  participantUids: [uidA, uidB],     // sorted
  matchRequestId: string,
  conversationId: string,
  establishedAt: timestamp,
  source: "find_partner_match"
}
```

### 5.4 ブロック（`blocks/{blockerUid}_{blockedUid}` 新規）

```javascript
{
  blockerUid: string,
  blockedUid: string,
  createdAt: timestamp
}
```

### 5.5 Security Rules スケッチ（疑似コード）

```javascript
function isVerifiedForFind() {
  let u = get(/databases/$(database)/documents/users/$(request.auth.uid));
  return signedIn()
    && request.auth.token.email_verified == true
    && u.data.compliance.identityVerificationStatus == 'verified'
    && u.data.compliance.accountStatus == 'active'
    && u.data.compliance.findFeatureEnabled == true;
}

function isOppositeSexVerified(viewerUid, targetUid) {
  let viewer = get(/databases/$(database)/documents/users/$(viewerUid));
  let target = get(/databases/$(database)/documents/users/$(targetUid));
  return viewer.data.genderVerified != target.data.genderVerified
    && viewer.data.genderVerified in ['male', 'female']
    && target.data.genderVerified in ['male', 'female'];
}

// public_profiles: FIND 経由の異性プロフィール閲覧
match /public_profiles/{targetUid} {
  allow read: if signedIn() && (
    request.auth.uid == targetUid  // 自分
    || (isVerifiedForFind() && isOppositeSexVerified(request.auth.uid, targetUid))
    // 同性・練習会等は別コレクション or 別 Rules 分支（feature flag）
  );
}

// match_requests: クライアント create 禁止 → Functions のみ
match /match_requests/{requestId} {
  allow read: if signedIn() && (
    resource.data.fromUid == request.auth.uid
    || resource.data.toUid == request.auth.uid
  );
  allow create, update, delete: if false;
}

// messages: ブロックチェックは Functions 経由推奨。Rules だけなら:
function notBlocked(sender, recipient) {
  return !exists(/databases/$(database)/documents/blocks/$(recipient + '_' + sender));
}

match /conversations/{cid}/messages/{mid} {
  allow create: if isConversationParticipant(cid)
    && isVerifiedForFind()  // FIND 由来 DM の場合
    && request.resource.data.senderId == request.auth.uid
    && request.resource.data.text.size() <= 4000;
  allow update: if false;  // 運営削除は Admin SDK
  allow delete: if false;
}

match /introduction_events/{eid} {
  allow read, write: if false;  // Functions / Admin only
}

match /reports/{reportId} {
  allow create: if signedIn() && request.resource.data.reporterUid == request.auth.uid;
  allow read, update: if false;  // 管理画面は Admin SDK
}
```

---

## 6. Cloud Functions スケッチ

```typescript
// --- FIND / 異性紹介 ---

export const sendMatchRequest = onCall(async (request) => {
  assertVerifiedForFind(request.auth);
  const { toUid, message, location, proposedStart, ... } = request.data;
  assertOppositeSex(request.auth.uid, toUid);
  await moderateText(message);
  await moderateText(location);
  await checkRateLimit(request.auth.uid, 'match_request', 10, 'day');
  const ref = await db.collection('match_requests').add({ ... });
  await logIntroductionEvent('match_request_sent', request.auth.uid, toUid, ref.id);
  return { requestId: ref.id };
});

export const acceptMatchRequest = onCall(async (request) => {
  // 当事者確認、status: open -> accepted
  // conversation 作成、connections 作成
  // introduction_events: match_established
});

export const onMessageCreate = onDocumentCreated(
  'conversations/{cid}/messages/{mid}',
  async (event) => {
    await moderateTextAsync(event.data.text);  // 事後フラグ
    await checkRateLimit(senderUid, 'message', 30, 'minute');
    await logIfFirstDm(...);
  }
);

export const onReportCreate = onDocumentCreated('reports/{id}', async (event) => {
  await notifyModerators(event.data);
  // 重大案件: 自動アカウント一時停止フラグ
});

// --- eKYC Webhook ---

export const ekycWebhook = onRequest(async (req, res) => {
  // ベンダー署名検証
  // users/{uid}.compliance.identityVerificationStatus 更新
  // genderVerified 設定
});
```

---

## 7. ギャップ分析（現状 TASUKI vs 要件）

### 7.1 FIND / 異性紹介 — 致命的ギャップ

| 要件 | 現状 | ギャップ |
|------|------|----------|
| eKYC | なし | ❌ 未実装 |
| メール確認必須 | 匿名ログイン可（`ProfileRegistrationView` L908） | ❌ |
| 18 歳サーバーゲート | 規約 + UI 年齢のみ | ❌ |
| 異性紹介前 verified ゲート | `public_profiles` は signedIn なら全閲覧 | ❌ |
| マッチリクエスト API | UI のみ / `MatchInvitationStore` 不完全 | ❌ |
| fromUid / toUid 整合 | `upsertRemote` が fromUid 欠落 | ❌ バグ |
| 承諾フロー | ローカル `JoinedPracticesStore` | ❌ サーバー未連携 |
| introduction ログ | なし | ❌ |
| 届出標識 | なし | ❌ |
| コンテンツフィルタ | なし | ❌ |
| 運営モデレーション UI | なし | ❌ |
| 異性判定（verified） | 性別は自己申告文字列 | ❌ |

### 7.2 メッセージ / 電気通信 — ギャップ

| 要件 | 現状 | ギャップ |
|------|------|----------|
| 通報 | `reports` create ✅ | 運営 read/update ❌ |
| ブロック | なし | ❌ |
| メッセージ削除 | Rules で禁止 | 運営削除手段 ❌ |
| serverTimestamp | クライアント `Timestamp(date: Date())` | △ 改ざん余地 |
| レートリミット | なし | ❌ |
| 外部送信開示 | PP に一部 | FIND 向け UI 不足 △ |

### 7.3 実装済み・活用可能

| 項目 | ファイル |
|------|----------|
| 1 対 1 メッセージ基盤 | `ConversationManager`, `ChatView` |
| 通報保存 | `ConversationManager.submitConversationReport`, `firestore.rules` L313–327 |
| 参加者限定 Rules | `isConversationParticipant`, `messageCreateAllowed` |
| マッチ度算法 | `FindMatchScore`（ログ連携待ち） |
| 規約 18 歳・出会い目的禁止 | `LegalTexts.swift` L22–44 |
| データインベントリ | `docs/DATA_INVENTORY_AND_TERMS_MATRIX.md` |

---

## 8. フェーズ別実装ロードマップ（FIND 優先）

### Phase 0 — 法務・事業（開発並行可）

- [ ] インターネット異性紹介業の届出（所轄公安委員会）
- [ ] eKYC ベンダー選定・DPA 締結
- [ ] 利用規約改定（異性紹介事業明示、禁止事項、保存期間）
- [ ] 届出番号確定 → `app_config/legal` 投入

### Phase 1 — FIND 准入制御（最優先）

**目標:** 未確認ユーザーが異性プロフィール・マッチ・DM に到達不能

1. `users.compliance.*` スキーマ追加
2. eKYC SDK + Webhook（`identityVerificationStatus`）
3. 匿名認証を FIND 利用不可に（Auth フロー改修）
4. `emailVerified` 強制
5. Cloud Functions: `sendMatchRequest`, `acceptMatchRequest`
6. `UserProfileDetailView` / `PartnerDetailView` を Functions 経由に接続
7. Security Rules: `public_profiles` read に `isVerifiedForFind` + 異性判定
8. FIND 入口に届出標識 + 初回同意モーダル

**完了判定:** 未 eKYC ユーザーが Firestore Rules で `public_profiles` 異性・`match_requests` に触れない

### Phase 2 — ログ・モデレーション

1. `introduction_events` + Functions ログ
2. `moderateText` 送信前検査
3. 管理画面 MVP（通報一覧、`reports` read、ユーザー停止）
4. `blocks` 実装
5. レートリミット

**完了判定:** マッチ送信〜承諾〜初回 DM の監査トレイルが追える

### Phase 3 — メッセージ完全準拠・運用

1. メッセージ serverTimestamp 化
2. 運営メッセージ非表示（Admin SDK）
3. 退会・法定保存期間の削除バッチ
4. 外部送信開示 UI
5. インシデント対応 Runbook + 警察照会フロー

**完了判定:** 通報〜措置〜監査ログの運用テスト完了

---

## 9. 参考ファイル一覧

| カテゴリ | パス |
|----------|------|
| FIND UI | `TASUKI/FindView.swift` |
| プロフィール → 招待 | `TASUKI/UserProfileDetailView.swift`, `TASUKI/MatchInviteComposerSheet.swift` |
| パートナー詳細 | `TASUKI/PartnerDetailView.swift` |
| リクエスト一覧 | `TASUKI/MessageListView.swift`, `TASUKI/MatchInvitationStore.swift` |
| チャット | `TASUKI/ChatView.swift`, `TASUKI/ConversationManager.swift` |
| モデル | `TASUKI/Models.swift`（`ConnectionStatus`, `Gender`, `User`） |
| ユーザー API | `TASUKI/UserManager.swift` |
| Rules | `firestore.rules` |
| 規約 | `TASUKI/LegalTexts.swift` |
| 登録 | `TASUKI/ProfileRegistrationView.swift` |
| 既存法務メモ | `docs/LEGAL_REVIEW_CHECKLIST.md`, `docs/DATA_INVENTORY_AND_TERMS_MATRIX.md` |

---

## 改訂履歴

| 日付 | 内容 |
|------|------|
| 2026-06-09 | 初版。FIND = 異性紹介前提、コードパスマップ・ギャップ・Rules スケッチ |
