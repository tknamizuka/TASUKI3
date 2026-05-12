"use strict";

const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentUpdated, onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {logger} = require("firebase-functions");
const crypto = require("crypto");

admin.initializeApp();
const db = admin.firestore();

const EVENT_NAMES = {
  run: new Set(["run_tracking_start", "run_tracking_stop", "race_finish_submitted", "time_trial_submitted"]),
  social: new Set(["message_sent", "conversation_created", "practice_chat_participant_added"]),
};

function yyyymmdd(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}${m}${d}`;
}

function startOfUtcDay(date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 0, 0, 0));
}

function endOfUtcDay(date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate(), 23, 59, 59, 999));
}

function startOfUtcMinusDays(date, days) {
  const start = startOfUtcDay(date);
  return new Date(start.getTime() - days * 24 * 60 * 60 * 1000);
}

function normalizeHour(tsLike) {
  if (!tsLike) return null;
  if (typeof tsLike.toDate === "function") {
    return tsLike.toDate().getHours();
  }
  const d = new Date(tsLike);
  if (Number.isNaN(d.getTime())) return null;
  return d.getHours();
}

function topHourByHistogram(hist) {
  let bestHour = null;
  let bestCount = -1;
  for (let h = 0; h < 24; h += 1) {
    const count = hist[h] || 0;
    if (count > bestCount) {
      bestCount = count;
      bestHour = h;
    }
  }
  return bestHour;
}

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function median(numbers) {
  if (!numbers.length) return null;
  const sorted = numbers.slice().sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return sorted[mid];
}

const RACE_POSITION_POINTS = [500, 400, 320, 260, 212, 170, 136, 109, 87, 70];
const RACE_FINISH_BONUS = 100;
const RACE_PARTICIPATION_BONUS = 50;
const TIME_TRIAL_POINTS_TABLE = [
  100, 90, 81, 73, 66, 59, 53, 48, 43, 39,
  35, 31, 28, 25, 22, 20, 18, 16, 14, 12,
];

function racePointsByRank(rank) {
  const positionPoint = rank <= RACE_POSITION_POINTS.length ? RACE_POSITION_POINTS[rank - 1] : 0;
  return positionPoint + RACE_FINISH_BONUS + RACE_PARTICIPATION_BONUS;
}

function timeTrialPointsByRank(rank) {
  return rank <= TIME_TRIAL_POINTS_TABLE.length ? TIME_TRIAL_POINTS_TABLE[rank - 1] : 0;
}

async function awardRacePointsForParticipant({
  raceId,
  participantId,
  participantName,
  rank,
  amount,
}) {
  const awardRef = db
      .collection("races")
      .doc(raceId)
      .collection("awards")
      .doc(participantId);
  const userRef = db.collection("users").doc(participantId);

  return db.runTransaction(async (tx) => {
    const awardSnap = await tx.get(awardRef);
    if (awardSnap.exists) {
      return false;
    }

    tx.set(awardRef, {
      userId: participantId,
      userName: participantName,
      rank,
      points: amount,
      awardedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(userRef, {
      totalPoints: admin.firestore.FieldValue.increment(amount),
      monthlyPoints: admin.firestore.FieldValue.increment(amount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const userSnap = await tx.get(userRef);
    const teamId = userSnap.data()?.teamId;
    if (typeof teamId === "string" && teamId.length > 0) {
      const teamRef = db.collection("teams").doc(teamId);
      tx.set(teamRef, {
        teamTotalPoints: admin.firestore.FieldValue.increment(amount),
        teamMonthlyPoints: admin.firestore.FieldValue.increment(amount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    return true;
  });
}

exports.awardRacePointsOnFinish = onDocumentUpdated(
    {
      document: "races/{raceId}",
      region: "asia-northeast1",
      memory: "512MiB",
    },
    async (event) => {
      const before = event.data?.before?.data();
      const after = event.data?.after?.data();
      const raceId = event.params.raceId;
      if (!before || !after || !raceId) {
        return;
      }
      if (before.status === "finished" || after.status !== "finished") {
        return;
      }

      logger.info("race points awarding started", {raceId});

      const participantsSnap = await db
          .collection("races")
          .doc(raceId)
          .collection("participants")
          .get();
      const finishers = participantsSnap.docs
          .map((doc) => ({id: doc.id, ...doc.data()}))
          .filter((p) => typeof p.finishTimeSeconds === "number" && p.finishTimeSeconds > 0)
          .sort((a, b) => a.finishTimeSeconds - b.finishTimeSeconds);

      let awardedCount = 0;
      for (let i = 0; i < finishers.length; i += 1) {
        const rank = i + 1;
        const p = finishers[i];
        const amount = racePointsByRank(rank);
        const awarded = await awardRacePointsForParticipant({
          raceId,
          participantId: p.id,
          participantName: p.name || "Runner",
          rank,
          amount,
        });
        if (awarded) {
          awardedCount += 1;
        }
      }

      logger.info("race points awarding completed", {
        raceId,
        finishers: finishers.length,
        awardedCount,
      });
    },
);

async function awardTimeTrialPointsForParticipant({
  roomId,
  participantId,
  participantName,
  rank,
  amount,
}) {
  const awardRef = db
      .collection("time_trial_rooms")
      .doc(roomId)
      .collection("awards")
      .doc(participantId);
  const userRef = db.collection("users").doc(participantId);

  return db.runTransaction(async (tx) => {
    const awardSnap = await tx.get(awardRef);
    if (awardSnap.exists) {
      return false;
    }

    tx.set(awardRef, {
      userId: participantId,
      userName: participantName,
      rank,
      points: amount,
      awardedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(userRef, {
      totalPoints: admin.firestore.FieldValue.increment(amount),
      monthlyPoints: admin.firestore.FieldValue.increment(amount),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const userSnap = await tx.get(userRef);
    const teamId = userSnap.data()?.teamId;
    if (typeof teamId === "string" && teamId.length > 0) {
      const teamRef = db.collection("teams").doc(teamId);
      tx.set(teamRef, {
        teamTotalPoints: admin.firestore.FieldValue.increment(amount),
        teamMonthlyPoints: admin.firestore.FieldValue.increment(amount),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    return true;
  });
}

exports.settleTimeTrialRooms = onSchedule(
    {
      schedule: "every 30 minutes",
      timeZone: "Asia/Tokyo",
      region: "asia-northeast1",
      memory: "512MiB",
    },
    async () => {
      const now = admin.firestore.Timestamp.fromDate(new Date());
      const roomSnap = await db.collection("time_trial_rooms")
          .where("periodEnd", "<=", now)
          .limit(50)
          .get();
      if (roomSnap.empty) {
        return;
      }

      logger.info("time trial settlement started", {rooms: roomSnap.size});

      for (const roomDoc of roomSnap.docs) {
        const roomId = roomDoc.id;
        const roomData = roomDoc.data();
        if (roomData.settledAt) {
          continue;
        }
        try {
          const participantsSnap = await db.collection("time_trial_rooms")
              .doc(roomId)
              .collection("participants")
              .get();
          const finishers = participantsSnap.docs
              .map((doc) => ({id: doc.id, ...doc.data()}))
              .filter((p) => typeof p.submittedTimeSeconds === "number" && p.submittedTimeSeconds > 0)
              .sort((a, b) => a.submittedTimeSeconds - b.submittedTimeSeconds)
              .slice(0, 20);

          let awardedCount = 0;
          for (let i = 0; i < finishers.length; i += 1) {
            const rank = i + 1;
            const p = finishers[i];
            const amount = timeTrialPointsByRank(rank);
            const awarded = await awardTimeTrialPointsForParticipant({
              roomId,
              participantId: p.id,
              participantName: p.name || "Runner",
              rank,
              amount,
            });
            if (awarded) {
              awardedCount += 1;
            }
          }

          await db.collection("time_trial_rooms").doc(roomId).set({
            settledAt: admin.firestore.FieldValue.serverTimestamp(),
            settledParticipantCount: finishers.length,
            awardedCount,
          }, {merge: true});

          logger.info("time trial room settled", {
            roomId,
            finishers: finishers.length,
            awardedCount,
          });
        } catch (error) {
          logger.error("time trial settlement failed", {
            roomId,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
    },
);

exports.aggregateBehaviorFeaturesDaily = onSchedule(
    {
      schedule: "every day 02:10",
      timeZone: "Asia/Tokyo",
      region: "asia-northeast1",
      memory: "512MiB",
    },
    async () => {
      const now = new Date();
      const todayUtc = startOfUtcDay(now);
      const fourteenDaysAgoUtc = startOfUtcMinusDays(now, 13);
      const sevenDaysAgoUtc = startOfUtcMinusDays(now, 6);
      const targetDateKey = yyyymmdd(new Date(todayUtc.getTime() - 24 * 60 * 60 * 1000));

      logger.info("behavior aggregation started", {targetDateKey});

      const usersSnap = await db.collection("users").get();
      logger.info("users loaded", {count: usersSnap.size});

      for (const userDoc of usersSnap.docs) {
        const userId = userDoc.id;
        try {
          const eventsSnap = await db
              .collection("users")
              .doc(userId)
              .collection("reality_events")
              .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(fourteenDaysAgoUtc))
              .where("timestamp", "<=", admin.firestore.Timestamp.fromDate(endOfUtcDay(now)))
              .get();

          let weeklyRunCount = 0;
          let previousWeeklyRunCount = 0;
          let socialEventCount = 0;
          const activeDays = new Set();
          const hourHistogram = Array(24).fill(0);
          const weekdayHistogram = Array(7).fill(0); // Sun=0 ... Sat=6
          const messageTimestamps = [];
          const currentWeeklyDayCounts = Array(7).fill(0);

          for (const eventDoc of eventsSnap.docs) {
            const data = eventDoc.data();
            const eventName = data.event_name || "";
            const timestamp = data.timestamp;
            const eventDate = typeof timestamp?.toDate === "function" ? timestamp.toDate() : null;
            if (eventDate) {
              activeDays.add(yyyymmdd(eventDate));
              const weekday = eventDate.getDay();
              weekdayHistogram[weekday] += 1;
              if (eventDate >= sevenDaysAgoUtc) {
                currentWeeklyDayCounts[weekday] += 1;
              }
            }

            const hour = normalizeHour(timestamp);
            if (hour !== null && hour >= 0 && hour <= 23) {
              hourHistogram[hour] += 1;
            }

            if (EVENT_NAMES.run.has(eventName)) {
              if (eventDate && eventDate >= sevenDaysAgoUtc) {
                weeklyRunCount += 1;
              } else {
                previousWeeklyRunCount += 1;
              }
            }
            if (EVENT_NAMES.social.has(eventName)) {
              socialEventCount += 1;
            }
            if (eventName === "message_sent" && eventDate) {
              messageTimestamps.push(eventDate.getTime());
            }
          }

          const runTrendDelta = weeklyRunCount - previousWeeklyRunCount;
          const totalEvents = weekdayHistogram.reduce((sum, count) => sum + count, 0);
          const weekendEvents = weekdayHistogram[0] + weekdayHistogram[6];
          const weekendActivityRatio = totalEvents > 0 ? weekendEvents / totalEvents : 0;
          const activeWeekdayCount = currentWeeklyDayCounts.filter((count) => count > 0).length;
          const routineSpreadScore = clamp01(activeWeekdayCount / 7);
          const messageIntervalsSec = [];
          if (messageTimestamps.length > 1) {
            const sorted = messageTimestamps.slice().sort((a, b) => a - b);
            for (let i = 1; i < sorted.length; i += 1) {
              const sec = (sorted[i] - sorted[i - 1]) / 1000;
              if (sec > 0 && sec < 24 * 60 * 60) {
                messageIntervalsSec.push(sec);
              }
            }
          }
          const medianMessageIntervalSec = median(messageIntervalsSec);

          // 0..1 に正規化（上限クリップ）
          const consistencyScore = clamp01(activeDays.size / 7);
          const socialActivityScore = clamp01(socialEventCount / 30);
          const behaviorShiftScore = clamp01(Math.abs(runTrendDelta) / 10);
          const topActiveHour = topHourByHistogram(hourHistogram);

          const feature = {
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            weeklyRunCount,
            weeklyRunTrendDelta: runTrendDelta,
            socialActivityScore,
            consistencyScore,
            weekendActivityRatio,
            routineSpreadScore,
            behaviorShiftScore,
            medianMessageIntervalSec,
            topActiveHour,
            sourceEventCount: eventsSnap.size,
            windowDays: 14,
          };

          await db
              .collection("users")
              .doc(userId)
              .collection("behavior_features")
              .doc(targetDateKey)
              .set(feature, {merge: true});
        } catch (error) {
          logger.error("behavior aggregation failed for user", {
            userId,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }

      logger.info("behavior aggregation completed", {targetDateKey});
    },
);

// MARK: - Ekiden: 提出受理・重複防止・順位計算

const EKIDEN_LEG_STATUS = {
  AWAITING: "awaitingTasuki",
  READY: "ready",
  SUBMITTED: "submitted",
};

/**
 * 駅伝区間提出（Callable）: 期間内・担当者・TASUKI状態・重複防止を検証してから書き込み
 */
exports.submitEkidenLeg = onCall(
    {
      region: "asia-northeast1",
      memory: "512MiB",
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "ログインが必要です");
      }
      const uid = request.auth.uid;
      const data = request.data;
      if (!data || typeof data.entryId !== "string" || typeof data.legIndex !== "number") {
        throw new HttpsError("invalid-argument", "entryId, legIndex が必須です");
      }
      const {
        entryId,
        legIndex,
        actualDistanceKm,
        elapsedSeconds,
        isUnderTarget,
        splitAtTargetSeconds,
        source = "manual",
        runActivityId,
      } = data;

      if (typeof actualDistanceKm !== "number" || typeof elapsedSeconds !== "number" ||
          typeof isUnderTarget !== "boolean") {
        throw new HttpsError("invalid-argument", "actualDistanceKm, elapsedSeconds, isUnderTarget が必須です");
      }

      const entryRef = db.collection("ekiden_entries").doc(entryId);
      const entrySnap = await entryRef.get();
      if (!entrySnap.exists) {
        throw new HttpsError("not-found", "エントリーが見つかりません");
      }
      const entryData = entrySnap.data();
      const eventId = entryData.eventId;
      const teamId = entryData.teamId;
      const eventRef = db.collection("ekiden_events").doc(eventId);
      const eventSnap = await eventRef.get();
      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "イベントが見つかりません");
      }
      const eventData = eventSnap.data();
      const now = new Date();
      const startAt = eventData.startAt?.toDate?.() ?? new Date(0);
      const endAt = eventData.endAt?.toDate?.() ?? new Date(9999, 11, 31);
      if (now < startAt || now > endAt) {
        throw new HttpsError("failed-precondition", "イベント期間外です");
      }

      const legRef = entryRef.collection("legs").doc(String(legIndex));
      const legSnap = await legRef.get();
      if (!legSnap.exists) {
        throw new HttpsError("not-found", "区間が見つかりません");
      }
      const legData = legSnap.data();
      if (legData.status === EKIDEN_LEG_STATUS.SUBMITTED) {
        throw new HttpsError("failed-precondition", "既に提出済みです（重複提出防止）");
      }
      if (legData.status !== EKIDEN_LEG_STATUS.READY) {
        throw new HttpsError("failed-precondition", "TASUKIが渡っていません。前区間の提出を待ってください");
      }
      const assignedUid = legData.assignedUid;
      if (assignedUid && assignedUid !== uid) {
        throw new HttpsError("permission-denied", "この区間の担当者ではありません");
      }

      const legsRef = entryRef.collection("legs");
      const submissionRef = entryRef.collection("submissions").doc();
      const nextLegRef = legsRef.doc(String(legIndex + 1));

      const ts = admin.firestore.Timestamp.fromDate(now);
      const legUpdate = {
        status: EKIDEN_LEG_STATUS.SUBMITTED,
        submittedAt: ts,
        actualDistanceKm,
        elapsedSeconds,
        isUnderTarget,
      };
      if (typeof splitAtTargetSeconds === "number") legUpdate.splitAtTargetSeconds = splitAtTargetSeconds;

      const subData = {
        legIndex,
        submittedByUid: uid,
        submittedAt: ts,
        source: source || "manual",
        actualDistanceKm,
        elapsedSeconds,
        isUnderTarget,
      };
      if (splitAtTargetSeconds != null) subData.splitAtTargetSeconds = splitAtTargetSeconds;
      if (runActivityId) subData.runActivityId = runActivityId;

      await db.runTransaction(async (tx) => {
        tx.update(legRef, legUpdate);

        const nextSnap = await tx.get(nextLegRef);
        if (nextSnap.exists) {
          tx.update(nextLegRef, {status: EKIDEN_LEG_STATUS.READY});
        }

        const nextIndex = legIndex + 1;
        const totalLegCount = Math.max(Number(eventData.legCount || 0), 1);
        const tasukiState = nextIndex < totalLegCount ? "ready" : "finished";
        tx.update(entryRef, {
          currentLegIndex: Math.min(nextIndex, totalLegCount - 1),
          tasukiState,
          updatedAt: ts,
        });

        tx.set(submissionRef, subData);
      });

      logger.info("ekiden leg submitted", {
        entryId,
        legIndex,
        uid,
        actualDistanceKm,
        elapsedSeconds,
      });

      return {success: true};
    },
);

/**
 * 駅伝提出時に順位を再計算
 */
async function recalcEkidenRanking(entryId) {
  const entryRef = db.collection("ekiden_entries").doc(entryId);
  const entrySnap = await entryRef.get();
  if (!entrySnap.exists) return;
  const entryData = entrySnap.data();
  const eventId = entryData.eventId;
  const teamId = entryData.teamId;

  const legsSnap = await entryRef.collection("legs").get();
  let totalElapsedSeconds = 0;
  for (const legDoc of legsSnap.docs) {
    const d = legDoc.data();
    if (d.status !== EKIDEN_LEG_STATUS.SUBMITTED) continue;
    const sec = d.splitAtTargetSeconds ?? d.elapsedSeconds;
    if (typeof sec === "number") totalElapsedSeconds += sec;
  }

  const rankingRef = db.collection("ekiden_events").doc(eventId)
      .collection("rankings").doc(entryId);
  await rankingRef.set({
    teamId,
    entryId,
    totalElapsedSeconds,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

const LEG_RANKING_TOP_N = 100;

/**
 * 同一イベント・同一区間の走者タイムでランキングを再計算し leg_rankings に保存する
 * @param {string} eventId
 * @param {number} legIndex
 */
async function recalcEkidenLegRankings(eventId, legIndex) {
  if (typeof legIndex !== "number" || legIndex < 0) return;

  const entriesSnap = await db.collection("ekiden_entries")
      .where("eventId", "==", eventId)
      .get();

  const rows = [];
  for (const entryDoc of entriesSnap.docs) {
    const entryIdRow = entryDoc.id;
    const teamIdRow = entryDoc.data().teamId;
    const legSnap = await entryDoc.ref.collection("legs").doc(String(legIndex)).get();
    if (!legSnap.exists) continue;
    const d = legSnap.data();
    if (d.status !== EKIDEN_LEG_STATUS.SUBMITTED) continue;
    if (d.isPass === true) continue;
    const sec = typeof d.splitAtTargetSeconds === "number" ?
      d.splitAtTargetSeconds : d.elapsedSeconds;
    if (typeof sec !== "number") continue;
    const runnerUid = d.assignedUid || d.submittedByUid || "";
    if (!runnerUid) continue;
    rows.push({
      entryId: entryIdRow,
      teamId: teamIdRow,
      runnerUid,
      elapsedSeconds: sec,
    });
  }

  rows.sort((a, b) => {
    if (a.elapsedSeconds !== b.elapsedSeconds) {
      return a.elapsedSeconds - b.elapsedSeconds;
    }
    return a.entryId.localeCompare(b.entryId);
  });

  const uids = [...new Set(rows.map((r) => r.runnerUid))];
  const nameByUid = {};
  const chunkSize = 30;
  for (let i = 0; i < uids.length; i += chunkSize) {
    const slice = uids.slice(i, i + chunkSize);
    const refs = slice.map((uid) => db.collection("users").doc(uid));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      const nm = s.exists && s.data()?.name;
      nameByUid[s.id] = typeof nm === "string" && nm.length ? nm : s.id;
    }
  }

  const ranksByEntryId = {};
  rows.forEach((r, idx) => {
    ranksByEntryId[r.entryId] = idx + 1;
  });

  const top = rows.slice(0, LEG_RANKING_TOP_N).map((r, idx) => ({
    rank: idx + 1,
    entryId: r.entryId,
    teamId: r.teamId,
    runnerUid: r.runnerUid,
    elapsedSeconds: r.elapsedSeconds,
    displayName: nameByUid[r.runnerUid] || r.runnerUid,
  }));

  const legRankingRef = db.collection("ekiden_events").doc(eventId)
      .collection("leg_rankings").doc(String(legIndex));
  await legRankingRef.set({
    legIndex,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    totalFinishers: rows.length,
    top,
    ranksByEntryId,
  }, {merge: true});
}

/**
 * 区間完了時にチームチャットへ自動通知
 */
async function notifyTeamChatOnLegSubmit(teamId, entryId, legIndex, submittedByUid, elapsedSeconds, isUnderTarget) {
  const userSnap = await db.collection("users").doc(submittedByUid).get();
  const runnerName = userSnap.exists && userSnap.data()?.name ?
      userSnap.data().name : "メンバー";

  const m = Math.floor(elapsedSeconds / 60);
  const s = Math.floor(elapsedSeconds % 60);
  const timeStr = `${m}:${String(s).padStart(2, "0")}`;
  const underText = isUnderTarget ? "（未達）" : "";
  const content = `${legIndex + 1}区 完了！${runnerName}さん ${timeStr}${underText}`;

  await db.collection("teams").doc(teamId).collection("teamChat").add({
    senderId: "system",
    senderName: "駅伝",
    content,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    isSystem: true,
    ekidenEntryId: entryId,
    legIndex,
  });
}

exports.onEkidenSubmissionCreated = onDocumentCreated(
    {
      document: "ekiden_entries/{entryId}/submissions/{submissionId}",
      region: "asia-northeast1",
      memory: "256MiB",
    },
    async (event) => {
      const entryId = event.params.entryId;
      if (!entryId) return;

      const snap = event.data;
      if (!snap || !snap.data) return;
      const subData = snap.data();
      const legIndex = subData.legIndex ?? -1;
      const submittedByUid = subData.submittedByUid ?? "";
      const elapsedSeconds = subData.elapsedSeconds ?? 0;
      const isUnderTarget = subData.isUnderTarget ?? false;

      try {
        const entrySnap = await db.collection("ekiden_entries").doc(entryId).get();
        const eventId = entrySnap.exists ? entrySnap.data()?.eventId : null;

        await recalcEkidenRanking(entryId);
        logger.info("ekiden ranking recalculated", {entryId});

        if (eventId && legIndex >= 0) {
          await recalcEkidenLegRankings(eventId, legIndex);
          logger.info("ekiden leg ranking recalculated", {eventId, legIndex});
        }

        if (entrySnap.exists) {
          const teamId = entrySnap.data()?.teamId;
          if (teamId) {
            await notifyTeamChatOnLegSubmit(
                teamId,
                entryId,
                legIndex,
                submittedByUid,
                elapsedSeconds,
                isUnderTarget,
            );
          }
        }
      } catch (err) {
        logger.error("ekiden submission handler failed", {
          entryId,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    },
);

const SPECTATOR_CHEER_MAX_PER_HOUR = 20;
const SPECTATOR_MESSAGE_MAX = 200;
const SPECTATOR_NICKNAME_MAX = 40;

/**
 * @param {string} limitKey
 */
async function checkSpectatorCheerRateLimit(limitKey) {
  const ref = db.collection("spectator_cheer_limits").doc(limitKey);
  const hourMs = 60 * 60 * 1000;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    let count = 0;
    let windowStartTs = admin.firestore.Timestamp.fromMillis(now);
    if (snap.exists) {
      const d = snap.data();
      const ws = d.windowStart?.toMillis?.() ?? 0;
      if (now - ws < hourMs) {
        count = Number(d.count || 0);
        windowStartTs = d.windowStart;
      }
    }
    if (count >= SPECTATOR_CHEER_MAX_PER_HOUR) {
      throw new HttpsError(
          "resource-exhausted",
          "投稿上限に達しました。1時間後に再度お試しください",
      );
    }
    tx.set(ref, {
      count: count + 1,
      windowStart: windowStartTs,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

/**
 * 沿道・観客からの応援（Callable）。Firestore 直書きは禁止し本関数経由のみ。
 * 未ログインでも clientInstanceId によりレート制限する。
 */
exports.postSpectatorCheer = onCall(
    {
      region: "asia-northeast1",
      memory: "256MiB",
      cors: true,
    },
    async (request) => {
      const data = request.data || {};
      const eventId = typeof data.eventId === "string" ? data.eventId.trim() : "";
      const teamId = typeof data.teamId === "string" ? data.teamId.trim() : "";
      let message = typeof data.message === "string" ? data.message.trim() : "";
      const nicknameRaw = typeof data.nickname === "string" ? data.nickname.trim() : "";
      const clientInstanceId = typeof data.clientInstanceId === "string" ?
        data.clientInstanceId.trim().slice(0, 128) : "";

      if (!eventId || !teamId) {
        throw new HttpsError("invalid-argument", "eventId と teamId が必要です");
      }
      if (message.length < 1) {
        throw new HttpsError("invalid-argument", "メッセージを入力してください");
      }
      if (message.length > SPECTATOR_MESSAGE_MAX) {
        message = message.slice(0, SPECTATOR_MESSAGE_MAX);
      }
      const nickname = nicknameRaw.length ?
        nicknameRaw.slice(0, SPECTATOR_NICKNAME_MAX) : "沿道から";

      const authUid = request.auth?.uid || "";
      if (!authUid && !clientInstanceId) {
        throw new HttpsError(
            "invalid-argument",
            "未ログインの場合は clientInstanceId（端末識別用のUUID）が必要です",
        );
      }

      const limitRaw = `${eventId}|${teamId}|${authUid || "anon"}|${clientInstanceId || authUid}`;
      const limitKey = crypto.createHash("sha256").update(limitRaw).digest("hex").slice(0, 48);
      await checkSpectatorCheerRateLimit(limitKey);

      const eventRef = db.collection("ekiden_events").doc(eventId);
      const eventSnap = await eventRef.get();
      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "イベントが見つかりません");
      }
      const ev = eventSnap.data();
      const now = new Date();
      const startAt = ev.startAt?.toDate?.() ?? new Date(0);
      const endAt = ev.endAt?.toDate?.() ?? new Date(9999, 11, 31);
      if (now < startAt || now > endAt) {
        throw new HttpsError("failed-precondition", "イベント期間外です");
      }

      const entrySnap = await db.collection("ekiden_entries")
          .where("eventId", "==", eventId)
          .where("teamId", "==", teamId)
          .limit(1)
          .get();
      if (entrySnap.empty) {
        throw new HttpsError("not-found", "このチームはこのイベントに参加していません");
      }

      await db.collection("teams").doc(teamId).collection("spectator_cheers").add({
        eventId,
        teamId,
        message,
        nickname,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        posterUid: authUid || null,
        latitude: typeof data.latitude === "number" ? data.latitude : null,
        longitude: typeof data.longitude === "number" ? data.longitude : null,
      });

      return {success: true};
    },
);
