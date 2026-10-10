// Local DRY RUN of functions/monthlyRetention.js. Reads only; it has no apply path.
//
//   node tools/run_monthly_retention.js                       -> as of now
//   node tools/run_monthly_retention.js --now=2026-11-01T03:00:00+05:30
//
// Uses the same firebase-admin and the same runMonthlyRetention() the deployed
// function runs. Credentials as in backfill_gender.js (SERVICE_ACCOUNT or the
// Guide app's gitignored service-account.json); nothing is stored in this repo.

const path = require('path');

const functionsDir = path.resolve(__dirname, '../../../functions');
const { initializeApp, cert } = require(require.resolve('firebase-admin/app', { paths: [functionsDir] }));
const keyPath = process.env.SERVICE_ACCOUNT ||
  path.resolve(__dirname, '../../../Guides/Sadhana-App-for-Admin/credentials/service-account.json');
initializeApp({ credential: cert(require(keyPath)) });

const { runMonthlyRetention } = require(path.join(functionsDir, 'monthlyRetention.js'));

const nowArg = process.argv.find((a) => a.startsWith('--now='));
const now = nowArg ? new Date(nowArg.slice('--now='.length)) : new Date();

(async () => {
  const s = await runMonthlyRetention({ now, dryRun: true });
  console.log(`DRY RUN as of ${now.toISOString()}  (IST year/month ${s.nowIst.year}-${s.nowIst.month})`);
  console.log(`keeps months >= ${s.keepFromMonth} (current + previous); deletes anything older`);
  console.log(`users with a name: ${s.usersWithName}, skipped (empty name): ${s.usersSkippedEmptyName}`);
  for (const [collection, st] of Object.entries(s.sadhana)) {
    console.log(`\n[${collection}]`);
    const months = Object.keys(st.deletedByMonth).sort((a, b) =>
      a.split('-').reverse().join('').localeCompare(b.split('-').reverse().join('')));
    if (months.length === 0) console.log('  would delete: nothing');
    for (const m of months) console.log(`  would delete ${String(st.deletedByMonth[m]).padStart(5)} date docs from ${m}`);
    console.log(`  would delete total: ${st.deleted}`);
    console.log(`  kept (current + previous month): ${st.kept}`);
  }
  console.log(`\nunparseable date ids skipped (never deleted): ${s.skippedUnparseable.length}`);
  for (const u of s.skippedUnparseable) console.log(`  ${u.collection}/${u.name}/dates/${JSON.stringify(u.id)}`);
  console.log(`\nlisting errors: ${s.errors.length}`);
  for (const e of s.errors) console.log(`  ${e.collection}/${e.name}: ${e.message}`);
  console.log('\nscorecard:', JSON.stringify(s.scorecard, null, 2));
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
