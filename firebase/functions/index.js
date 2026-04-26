"use strict";

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const { DateTime } = require("luxon");

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

const DEFAULT_TZ = "Asia/Tokyo";
const DEFAULT_QUIET_START = 22;
const DEFAULT_QUIET_END = 7;

/**
 * @param {string} timeZone IANA
 * @param {number} quietStart inclusive (e.g. 22)
 * @param {number} quietEnd exclusive end of morning window (e.g. 7 → quiet if hour < 7 or hour >= 22)
 */
function isInQuietHours(timeZone, quietStart, quietEnd) {
  const dt = DateTime.now().setZone(timeZone);
  const h = dt.hour;
  if (quietStart > quietEnd) {
    return h >= quietStart || h < quietEnd;
  }
  return h >= quietStart && h < quietEnd;
}

/**
 * Next occurrence of quietEnd hour (e.g. 7:00) in timeZone, strictly after `now` in that zone.
 */
function nextQuietEndDate(timeZone, quietEnd) {
  const dt = DateTime.now().setZone(timeZone);
  let target = dt.startOf("day").set({ hour: quietEnd, minute: 0, second: 0, millisecond: 0 });
  if (dt >= target) {
    target = target.plus({ days: 1 });
  }
  return target.toJSDate();
}

exports.onPartnerMatchNotifyOutbox = onDocumentCreated(
  {
    document: "partnerMatchNotifyOutbox/{docId}",
    region: "asia-northeast1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const { recipientUid, senderName, requestId } = snap.data();
    if (!recipientUid || !requestId) return;

    const userRef = db.doc(`users/${recipientUid}`);
    const userSnap = await userRef.get();
    const token = userSnap.get("fcmToken");
    if (!token) {
      console.log("No FCM token for recipient", recipientUid);
      return;
    }

    const tz = userSnap.get("pushTimeZone") || DEFAULT_TZ;
    const quietStart = Number.isInteger(userSnap.get("pushQuietStartHour"))
      ? userSnap.get("pushQuietStartHour")
      : DEFAULT_QUIET_START;
    const quietEnd = Number.isInteger(userSnap.get("pushQuietEndHour"))
      ? userSnap.get("pushQuietEndHour")
      : DEFAULT_QUIET_END;

    const title = "パートナーマッチング";
    const body = `${senderName || "ユーザー"}さんからマッチングリクエストが届きました。`;
    const data = { kind: "partner_match", requestId: String(requestId) };

    if (isInQuietHours(tz, quietStart, quietEnd)) {
      const deliverAt = admin.firestore.Timestamp.fromDate(nextQuietEndDate(tz, quietEnd));
      await db.collection("partnerMatchPushQueue").add({
        token,
        title,
        body,
        data,
        deliverAt,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    try {
      await messaging.send({
        token,
        notification: { title, body },
        data,
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      });
    } catch (e) {
      console.error("FCM send failed", e);
    }
  }
);

exports.processPartnerMatchPushQueue = onSchedule(
  {
    schedule: "every 15 minutes",
    region: "asia-northeast1",
    timeZone: "Asia/Tokyo",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();
    const q = await db
      .collection("partnerMatchPushQueue")
      .where("deliverAt", "<=", now)
      .limit(100)
      .get();

    for (const doc of q.docs) {
      const { token, title, body, data } = doc.data();
      try {
        await messaging.send({
          token,
          notification: { title, body },
          data: data || {},
          apns: {
            payload: {
              aps: { sound: "default" },
            },
          },
        });
        await doc.ref.delete();
      } catch (e) {
        console.error("Queue FCM failed", doc.id, e);
        await doc.ref.delete();
      }
    }
  }
);
