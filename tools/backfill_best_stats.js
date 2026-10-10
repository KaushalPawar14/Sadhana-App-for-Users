// One-off, re-runnable backfill of users.bestChantRounds / users.bestReadingMinutes
// (the Profile "personal best" tiles). Each student's best is the highest chantRounds /
// bookReading in ANY report still retained, in BOTH sadhana-reports/{name}/dates and
// hostel-sadhana/{name}/dates. The trigger updateBestStatsOn* keeps them current after
// this.
//
// Additive only: a field is written only when it is absent or LOWER than the computed
// value, so a best is never lowered and no other field is touched. Re-running changes
// nothing once it is done. Values above a day's capacity (more than 250 rounds or 1,440
// reading minutes) are typos and are ignored, as in functions/bestStats.js.
//
// A name shared by several users is attributed to the FIRST user document by id, the
// same match functions/shared.js studentByName makes.
//
//   node tools/backfill_best_stats.js            -> DRY RUN (reads only, writes nothing)
//   node tools/backfill_best_stats.js --apply    -> performs the writes
//
// Needs firebase-admin (./node_modules or ../../functions/node_modules) and a service
// account key: SERVICE_ACCOUNT, or the Guide app's gitignored credentials/service-account.json.
// No credential is stored in this repo.

const path = require('path');

function loadAdmin(sub) {
  const candidates = [
    `firebase-admin/${sub}`,
    path.resolve(__dirname, `../../../functions/node_modules/firebase-admin/lib/${sub}`),
  ];
  for (const c of candidates) {
    try { return require(c); } catch (_) { /* try next */ }
  }
  throw new Error('firebase-admin not found; run npm install in functions/');
}

const { initializeApp, cert } = loadAdmin('app');
const { getFirestore } = loadAdmin('firestore');
const keyPath = process.env.SERVICE_ACCOUNT ||
  path.resolve(__dirname, '../../../Guides/Sadhana-App-for-Admin/credentials/service-account.json');
initializeApp({ credential: cert(require(keyPath)) });
const db = getFirestore();

const APPLY = process.argv.includes('--apply');
const MAX_CHANT = 250;
const MAX_READING = 1440;

const usable = (v, max) =>
  typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= max ? Math.floor(v) : null;

async function maxOf(collection, name) {
  const snap = await db.collection(collection).doc(name).collection('dates').get();
  let chant = null;
  let reading = null;
  let reports = 0;
  let ignored = 0;
  for (const d of snap.docs) {
    const data = d.data();
    reports++;
    for (const [field, max, set] of [
      ['chantRounds', MAX_CHANT, (v) => { if (chant === null || v > chant) chant = v; }],
      ['bookReading', MAX_READING, (v) => { if (reading === null || v > reading) reading = v; }],
    ]) {
      if (!(field in data)) continue;
      const v = usable(data[field], max);
      if (v === null) { ignored++; continue; }
      set(v);
    }
  }
  return { chant, reading, reports, ignored };
}

(async () => {
  const users = (await db.collection('users').get()).docs
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const firstByName = new Map();
  const dupNames = new Set();
  let placeholders = 0;
  for (const u of users) {
    const name = String(u.get('name') ?? '');
    if (name.trim() === '') { placeholders++; continue; }
    if (firstByName.has(name)) dupNames.add(name); else firstByName.set(name, u);
  }

  const plan = [];
  let noReports = 0;
  let ignoredValues = 0;
  let alreadyOk = 0;
  for (const [name, u] of firstByName) {
    const a = await maxOf('sadhana-reports', name);
    const b = await maxOf('hostel-sadhana', name);
    ignoredValues += a.ignored + b.ignored;
    const chant = [a.chant, b.chant].filter((x) => x !== null).reduce((m, x) => Math.max(m, x), -1);
    const reading = [a.reading, b.reading].filter((x) => x !== null).reduce((m, x) => Math.max(m, x), -1);
    if (a.reports + b.reports === 0 || (chant < 0 && reading < 0)) { noReports++; continue; }
    const cur = u.data();
    const patch = {};
    if (chant >= 0 && !(typeof cur.bestChantRounds === 'number' && cur.bestChantRounds >= chant)) {
      patch.bestChantRounds = chant;
    }
    if (reading >= 0 && !(typeof cur.bestReadingMinutes === 'number' && cur.bestReadingMinutes >= reading)) {
      patch.bestReadingMinutes = reading;
    }
    if (Object.keys(patch).length === 0) { alreadyOk++; continue; }
    plan.push({ uid: u.id, name, patch, reports: a.reports + b.reports });
  }

  console.log(`mode: ${APPLY ? 'APPLY' : 'DRY RUN (no writes)'}`);
  console.log(`users: ${users.length}  with a name: ${firstByName.size}  placeholders skipped: ${placeholders}`);
  console.log(`names shared by several users (first user id gets them): ${dupNames.size}`);
  console.log(`students with no usable retained report (left untouched): ${noReports}`);
  console.log(`values ignored as impossible: ${ignoredValues}`);
  console.log(`already up to date: ${alreadyOk}`);
  console.log(`WOULD ${APPLY ? 'WRITE' : 'WRITE (dry run)'} ${plan.length} user(s)`);
  for (const p of plan.slice(0, 5)) {
    console.log(`  sample: users/${p.uid}  (${p.name.slice(0, 1)}***, ${p.reports} reports)  ${JSON.stringify(p.patch)}`);
  }

  if (!APPLY) return;
  let written = 0;
  for (let i = 0; i < plan.length; i += 400) {
    const batch = db.batch();
    for (const p of plan.slice(i, i + 400)) {
      batch.update(db.collection('users').doc(p.uid), p.patch);
    }
    await batch.commit();
    written += Math.min(400, plan.length - i);
  }
  console.log(`written: ${written}`);
})().catch((e) => { console.error(e); process.exit(1); });
