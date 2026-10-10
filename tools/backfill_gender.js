// One-off, re-runnable backfill: sets users.gender = "male" ONLY on user documents
// that have no gender field AND a non-empty name. Placeholder docs (no name yet) are
// permanently skipped: the registration screen saves gender only when none is saved,
// so a pre-filled value would stop those people recording their own answer.
// Touches no other field, never overwrites a gender.
//
//   node tools/backfill_gender.js            -> DRY RUN (reads only, writes nothing)
//   node tools/backfill_gender.js --apply    -> performs the writes
//
// Needs firebase-admin (resolved from ./node_modules or ../../functions/node_modules)
// and a service-account key: set SERVICE_ACCOUNT, or the Guide app's gitignored
// credentials/service-account.json is used. No credential is stored in this repo.

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
const PATCH = { gender: 'male' };

function kindOf(d) {
  if (d.isManualEntry === true) return 'manual-entry (guide-recorded)';
  if (d.createdBy === 'admin') return 'admin-created';
  if (!d.name) return 'placeholder (no name yet)';
  return 'self-registered';
}

function tally(map, key) { map[key] = (map[key] || 0) + 1; }

function isPlaceholder(d) {
  return String(d.name === undefined || d.name === null ? '' : d.name).trim() === '';
}

(async () => {
  const snap = await db.collection('users').get();
  const missing = [];
  const skippedPlaceholders = [];
  let hasGender = 0;
  const byRole = {};
  const byManual = {};
  const byCreatedBy = {};
  const byKind = {};
  const genderValues = {};
  const show = (v) => (v === undefined ? '(absent)' : JSON.stringify(v));

  for (const doc of snap.docs) {
    const d = doc.data();
    if (Object.prototype.hasOwnProperty.call(d, 'gender')) {
      hasGender++;
      tally(genderValues, JSON.stringify(d.gender));
      continue;
    }
    if (isPlaceholder(d)) {
      skippedPlaceholders.push(doc);
      continue;
    }
    missing.push(doc);
    tally(byRole, show(d.role));
    tally(byManual, show(d.isManualEntry));
    tally(byCreatedBy, `createdBy=${show(d.createdBy)} createdByAdmin=${show(d.createdByAdmin)}`);
    tally(byKind, kindOf(d));
  }

  console.log(`mode: ${APPLY ? 'APPLY' : 'DRY RUN (no writes)'}`);
  console.log(`total users documents: ${snap.size}`);
  console.log(`already have gender: ${hasGender}`, genderValues);
  console.log(`would be written (missing gender, has name): ${missing.length}`);
  console.log(`skipped as placeholders (no name): ${skippedPlaceholders.length}`, skippedPlaceholders.map((x) => x.id));
  console.log('by isManualEntry:', byManual);
  console.log('by createdBy / createdByAdmin:', byCreatedBy);
  console.log('by role (residence):', byRole);
  console.log('by derived kind:', byKind);
  console.log('sample writes (exact):');
  for (const doc of missing.slice(0, 5)) {
    console.log(`  users/${doc.id}  ->  update(${JSON.stringify(PATCH)})   [${kindOf(doc.data())}]`);
  }

  if (!APPLY) return;

  let written = 0, skipped = 0, errors = 0;
  for (const doc of missing) {
    try {
      await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists || isPlaceholder(fresh.data()) ||
            Object.prototype.hasOwnProperty.call(fresh.data(), 'gender')) {
          skipped++;
          return;
        }
        tx.update(doc.ref, PATCH);
        written++;
      });
    } catch (e) {
      errors++;
      console.error(`ERROR users/${doc.id}: ${e.message}`);
    }
  }
  console.log(`written: ${written}, skipped (already had gender / placeholder / vanished): ${skipped}, errors: ${errors}`);

  const after = await db.collection('users').get();
  const stillMissing = after.docs.filter((x) =>
    !isPlaceholder(x.data()) && !Object.prototype.hasOwnProperty.call(x.data(), 'gender')).length;
  const placeholders = after.docs.filter((x) => isPlaceholder(x.data())).length;
  console.log(`re-query: non-placeholder docs still missing gender = ${stillMissing}`);
  console.log(`re-query: placeholder docs (untouched) = ${placeholders}, of which with gender = ` +
    after.docs.filter((x) => isPlaceholder(x.data()) && 'gender' in x.data()).length);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
