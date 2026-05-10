/**
 * Firestore ルール回帰テスト（@firebase/rules-unit-testing）
 * 実行: cd functions && npm install && npm run test:rules
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import assert from "assert";
import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, collection, getDocs, limit, query } from "firebase/firestore";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rules = fs.readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8");

const projectId = "tasuki-emulator-rules";

async function run() {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: { rules },
  });

  try {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "teams", "teamA"), {
        ownerUid: "owner1",
        members: ["owner1"],
        name: "Team A",
      });
      await setDoc(doc(db, "users", "alice"), {
        id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        name: "Alice",
        teamId: "teamA",
      });
      await setDoc(doc(db, "public_profiles", "alice"), {
        id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        name: "Alice",
      });
    });

    const bob = testEnv.authenticatedContext("bob").firestore();
    await assertFails(getDoc(doc(bob, "users", "alice")));

    const alice = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(getDoc(doc(alice, "users", "alice")));

    await assertSucceeds(getDocs(query(collection(bob, "public_profiles"), limit(5))));

    await assertFails(
      updateDoc(doc(alice, "users", "alice"), { coachCertified: true }),
    );

    await assertFails(
      updateDoc(doc(alice, "public_profiles", "alice"), { totalPoints: 99999 }),
    );

    await assertFails(
      updateDoc(doc(bob, "teams", "teamA"), { name: "Hacked" }),
    );

    console.log("firestore rules tests: OK");
  } finally {
    await testEnv.cleanup();
  }
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
