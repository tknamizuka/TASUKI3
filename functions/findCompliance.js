"use strict";

const admin = require("firebase-admin");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const crypto = require("crypto");

const REGION = "asia-northeast1";

const NG_WORDS = [
  "援助", "援交", "パパ活", "ママ活", "売春", "風俗", "即会い", "即日",
];

const MATCH_REQUEST_DAILY_LIMIT = 10;
const MESSAGE_PER_MINUTE_LIMIT = 30;

function genderToVerified(raw) {
  const g = typeof raw === "string" ? raw.trim() : "";
  if (g === "男性" || g === "male") return "male";
  if (g === "女性" || g === "female") return "female";
  return "other";
}

function isOppositeSex(genderA, genderB) {
  return genderA === "male" && genderB === "female" ||
    genderA === "female" && genderB === "male";
}

function moderateText(text) {
  const normalized = typeof text === "string" ? text.trim() : "";
  if (!normalized) return;
  const lower = normalized.toLowerCase();
  for (const word of NG_WORDS) {
    if (lower.includes(word.toLowerCase())) {
      throw new HttpsError("invalid-argument", "不適切な表現が含まれています");
    }
  }
}

async function getUserDoc(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "ユーザープロフィールが見つかりません");
  }
  return snap;
}

function assertVerifiedForFind(auth, userSnap) {
  if (!auth) {
    throw new HttpsError("unauthenticated", "ログインが必要です");
  }
  if (!auth.token?.email_verified) {
    throw new HttpsError("failed-precondition", "メールアドレスの確認が必要です");
  }
  if (auth.token?.firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError("failed-precondition", "FIND 機能では匿名アカウントは利用できません");
  }
  const compliance = userSnap.data()?.compliance || {};
  if (compliance.accountStatus && compliance.accountStatus !== "active") {
    throw new HttpsError("permission-denied", "アカウントが利用停止中です");
  }
  if (compliance.identityVerificationStatus !== "verified") {
    throw new HttpsError("failed-precondition", "本人確認が完了していません");
  }
  if (compliance.findFeatureEnabled === false) {
    throw new HttpsError("permission-denied", "FIND 機能が無効です");
  }
}

function verifiedGender(userSnap) {
  const data = userSnap.data() || {};
  const fromCompliance = data.genderVerified;
  if (fromCompliance === "male" || fromCompliance === "female") {
    return fromCompliance;
  }
  return genderToVerified(data.gender);
}

async function assertOppositeSexPair(fromUid, toUid) {
  const [fromSnap, toSnap] = await Promise.all([
    getUserDoc(fromUid),
    getUserDoc(toUid),
  ]);
  const fromGender = verifiedGender(fromSnap);
  const toGender = verifiedGender(toSnap);
  if (!isOppositeSex(fromGender, toGender)) {
    throw new HttpsError("failed-precondition", "異性のユーザーにのみリクエストできます");
  }
  return {fromGender, toGender, fromSnap, toSnap};
}

async function isBlocked(a, b) {
  const db = admin.firestore();
  const [ab, ba] = await Promise.all([
    db.collection("blocks").doc(`${a}_${b}`).get(),
    db.collection("blocks").doc(`${b}_${a}`).get(),
  ]);
  return ab.exists || ba.exists;
}

async function checkRateLimit(uid, action, maxCount, windowKey) {
  const ref = admin.firestore().collection("rate_limits").doc(`${uid}_${action}_${windowKey}`);
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? Number(snap.data()?.count || 0) : 0;
    if (!Number.isFinite(current) || current >= maxCount) {
      throw new HttpsError("resource-exhausted", "送信上限に達しました。時間をおいて再試行してください");
    }
    tx.set(ref, {
      uid,
      action,
      windowKey,
      count: current + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function logIntroductionEvent(eventType, actorUid, targetUid, extra = {}) {
  const db = admin.firestore();
  const [actorSnap, targetSnap] = await Promise.all([
    getUserDoc(actorUid),
    getUserDoc(targetUid),
  ]);
  const actorGender = verifiedGender(actorSnap);
  const targetGender = verifiedGender(targetSnap);
  await db.collection("introduction_events").add({
    eventType,
    actorUid,
    targetUid,
    actorGender,
    targetGender,
    isOppositeSexPair: isOppositeSex(actorGender, targetGender),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...extra,
  });
}

function yyyymmddUtc(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}${m}${d}`;
}

function yyyymmddhhUtc(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  const h = String(date.getUTCHours()).padStart(2, "0");
  return `${y}${m}${d}${h}`;
}

function ageFromBirthDate(birthDate) {
  const birth = birthDate instanceof Date ? birthDate : new Date(birthDate);
  if (Number.isNaN(birth.getTime())) return null;
  const now = new Date();
  let age = now.getFullYear() - birth.getFullYear();
  const m = now.getMonth() - birth.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < birth.getDate())) {
    age -= 1;
  }
  return age;
}

function defaultComplianceFields() {
  return {
    identityVerificationStatus: "unverified",
    emailVerified: false,
    findFeatureEnabled: false,
    accountStatus: "active",
  };
}

function registerFindComplianceExports() {
  const db = admin.firestore();

  const ensureUserComplianceDefaults = onCall({region: REGION}, async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const uid = request.auth.uid;
    const ref = db.collection("users").doc(uid);
    const snap = await ref.get();
    const existing = snap.exists ? (snap.data()?.compliance || {}) : {};
    const merged = {
      ...defaultComplianceFields(),
      ...existing,
      emailVerified: Boolean(request.auth.token?.email_verified),
    };
    if (merged.identityVerificationStatus === "verified") {
      merged.findFeatureEnabled = true;
    }
    await ref.set({
      compliance: merged,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return {compliance: merged};
  });

  const submitIdentityVerification = onCall({region: REGION}, async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    if (!request.auth.token?.email_verified) {
      throw new HttpsError("failed-precondition", "メールアドレスの確認が必要です");
    }
    if (request.auth.token?.firebase?.sign_in_provider === "anonymous") {
      throw new HttpsError("failed-precondition", "匿名アカウントでは本人確認できません");
    }

    const uid = request.auth.uid;
    const userRef = db.collection("users").doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "プロフィール登録が必要です");
    }
    const data = userSnap.data() || {};
    const age = typeof data.age === "number" ? data.age : Number(data.age);
    if (!Number.isFinite(age) || age < 18) {
      throw new HttpsError("failed-precondition", "18歳未満は利用できません");
    }

    const genderVerified = genderToVerified(data.gender);
    if (genderVerified !== "male" && genderVerified !== "female") {
      throw new HttpsError("failed-precondition", "本人確認には性別（男性/女性）の登録が必要です");
    }

    const allowDev = process.env.ALLOW_DEV_IDENTITY_VERIFICATION === "1";
    const nextStatus = allowDev ? "verified" : "pending";

    await userRef.set({
      genderVerified,
      compliance: {
        identityVerificationStatus: nextStatus,
        identityVerifiedAt: allowDev ?
          admin.firestore.FieldValue.serverTimestamp() : null,
        identityVerificationVendor: allowDev ? "dev_stub" : "pending_ekyc",
        emailVerified: true,
        findFeatureEnabled: allowDev,
        accountStatus: "active",
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      status: nextStatus,
      findFeatureEnabled: allowDev,
      message: allowDev ?
        "開発用スタブで本人確認が完了しました" :
        "本人確認を受け付けました。審査完了までお待ちください",
    };
  });

  const sendMatchRequest = onCall({region: REGION}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userSnap = await getUserDoc(uid);
    assertVerifiedForFind(request.auth, userSnap);

    const toUid = typeof request.data?.toUid === "string" ? request.data.toUid.trim() : "";
    if (!toUid || toUid === uid) {
      throw new HttpsError("invalid-argument", "送信先が不正です");
    }

    const message = typeof request.data?.message === "string" ?
      request.data.message.trim() : "";
    const location = typeof request.data?.location === "string" ?
      request.data.location.trim() : "";
    moderateText(message);
    moderateText(location);

    if (await isBlocked(uid, toUid)) {
      throw new HttpsError("permission-denied", "このユーザーには送信できません");
    }

    const {fromGender, toGender, toSnap} = await assertOppositeSexPair(uid, toUid);
    await checkRateLimit(uid, "match_request", MATCH_REQUEST_DAILY_LIMIT, yyyymmddUtc(new Date()));

    const fromName = userSnap.data()?.name || "ユーザー";
    const proposedStart = request.data?.proposedStart;
    let proposedTimestamp = null;
    if (proposedStart) {
      const d = new Date(proposedStart);
      if (!Number.isNaN(d.getTime())) {
        proposedTimestamp = admin.firestore.Timestamp.fromDate(d);
      }
    }

    const ref = db.collection("match_requests").doc();
    const payload = {
      fromUid: uid,
      toUid,
      fromName,
      fromGenderVerified: fromGender,
      toGenderVerified: toGender,
      isOppositeSexIntroduction: true,
      type: "partner",
      message,
      location,
      isWeeklyRecurring: Boolean(request.data?.isWeeklyRecurring),
      recurrenceWeekday: typeof request.data?.recurrenceWeekday === "number" ?
        request.data.recurrenceWeekday : null,
      status: "open",
      isNew: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (proposedTimestamp) {
      payload.proposedStart = proposedTimestamp;
    }
    await ref.set(payload);

    await logIntroductionEvent("match_request_sent", uid, toUid, {
      matchRequestId: ref.id,
      sourceScreen: request.data?.sourceScreen || "unknown",
      targetName: toSnap.data()?.name || "",
    });

    return {requestId: ref.id};
  });

  const acceptMatchRequest = onCall({region: REGION}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userSnap = await getUserDoc(uid);
    assertVerifiedForFind(request.auth, userSnap);

    const requestId = typeof request.data?.requestId === "string" ?
      request.data.requestId.trim() : "";
    if (!requestId) {
      throw new HttpsError("invalid-argument", "requestId が必要です");
    }

    const reqRef = db.collection("match_requests").doc(requestId);
    const reqSnap = await reqRef.get();
    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "リクエストが見つかりません");
    }
    const req = reqSnap.data() || {};
    if (req.toUid !== uid) {
      throw new HttpsError("permission-denied", "このリクエストを承諾できません");
    }
    if (req.status !== "open") {
      throw new HttpsError("failed-precondition", "このリクエストは既に処理済みです");
    }
    if (await isBlocked(uid, req.fromUid)) {
      throw new HttpsError("permission-denied", "このユーザーとはマッチできません");
    }

    const conversationRef = db.collection("conversations").doc();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const participantIds = [req.fromUid, uid].sort();

    await db.runTransaction(async (tx) => {
      tx.update(reqRef, {
        status: "accepted",
        acceptedAt: now,
        updatedAt: now,
        conversationId: conversationRef.id,
      });
      tx.set(conversationRef, {
        participantIds,
        partnerName: req.fromName || "パートナー",
        createdAt: now,
        lastMessageAt: now,
        lastReadAt: {
          [req.fromUid]: now,
          [uid]: now,
        },
        source: "find_partner_match",
        matchRequestId: requestId,
      });
      const connectionId = participantIds.join("_");
      tx.set(db.collection("connections").doc(connectionId), {
        participantUids: participantIds,
        matchRequestId: requestId,
        conversationId: conversationRef.id,
        establishedAt: now,
        source: "find_partner_match",
      });
    });

    await logIntroductionEvent("match_established", uid, req.fromUid, {
      matchRequestId: requestId,
      conversationId: conversationRef.id,
    });

    return {conversationId: conversationRef.id, matchRequestId: requestId};
  });

  const declineMatchRequest = onCall({region: REGION}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const requestId = typeof request.data?.requestId === "string" ?
      request.data.requestId.trim() : "";
    if (!requestId) {
      throw new HttpsError("invalid-argument", "requestId が必要です");
    }
    const reqRef = db.collection("match_requests").doc(requestId);
    const reqSnap = await reqRef.get();
    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "リクエストが見つかりません");
    }
    const req = reqSnap.data() || {};
    if (req.fromUid !== uid && req.toUid !== uid) {
      throw new HttpsError("permission-denied", "操作できません");
    }
    const status = req.toUid === uid ? "declined" : "cancelled";
    await reqRef.update({
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {success: true};
  });

  const blockUser = onCall({region: REGION}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const blockedUid = typeof request.data?.blockedUid === "string" ?
      request.data.blockedUid.trim() : "";
    if (!blockedUid || blockedUid === uid) {
      throw new HttpsError("invalid-argument", "blockedUid が不正です");
    }
    await db.collection("blocks").doc(`${uid}_${blockedUid}`).set({
      blockerUid: uid,
      blockedUid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {success: true};
  });

  const logProfileView = onCall({region: REGION}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const userSnap = await getUserDoc(uid);
    assertVerifiedForFind(request.auth, userSnap);

    const targetUid = typeof request.data?.targetUid === "string" ?
      request.data.targetUid.trim() : "";
    if (!targetUid || targetUid === uid) {
      throw new HttpsError("invalid-argument", "targetUid が不正です");
    }
    await assertOppositeSexPair(uid, targetUid);
    await logIntroductionEvent("profile_view", uid, targetUid, {
      sourceScreen: request.data?.sourceScreen || "UserProfileDetailView",
    });
    return {success: true};
  });

  return {
    ensureUserComplianceDefaults,
    submitIdentityVerification,
    sendMatchRequest,
    acceptMatchRequest,
    declineMatchRequest,
    blockUser,
    logProfileView,
  };
}

module.exports = {registerFindComplianceExports, genderToVerified, isOppositeSex};
