// Carriers are ranked on what they actually did, and dispatch uses the ranking.
//
//   node infra/smoke-test-delivery-score.js
//
// Until this existed "the platform chooses" meant "whoever is first in the list". That is fine with
// one carrier and indefensible with several — a marketplace that cannot tell a good carrier from a
// bad one is just a list of names.
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const back = token('backoffice');
const merchant = token('merchant');

const call = (m, p, body, tok = back) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, t) => JSON.parse(split(call('GET', p, null, t)).body);
const send = (m, p, b, t) => split(call(m, p, b, t));

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 56).padEnd(56) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 56).padEnd(56) + (detail ?? '')); }
};

console.log('--- every carrier has a score ---');
const scores = get('/api/delivery-providers/scores');
check('the register is scored', Array.isArray(scores) && scores.length > 0, `${scores.length} carriers`);
check('scores are on a 0-100 scale',
  scores.every(s => s.score >= 0 && s.score <= 100),
  `${Math.min(...scores.map(s => s.score))}..${Math.max(...scores.map(s => s.score))}`);
check('and are returned best first',
  scores.every((s, i) => i === 0 || scores[i - 1].score >= s.score), 'descending');

console.log('\n--- the components come back with the number ---');
// A carrier told only that they scored 61 cannot act on it. The parts are what they can fix.
const withHistory = scores.find(s => s.orders > 0);
check('at least one carrier has a real record', !!withHistory,
  withHistory ? `${withHistory.name}: ${withHistory.orders} orders` : 'none yet');
if (withHistory) {
  check('completion rate is reported', typeof withHistory.completionRate === 'number',
    `${(withHistory.completionRate * 100).toFixed(0)}% delivered`);
  check('and the score reflects it',
    withHistory.completionRate < 1 ? withHistory.score < 100 : withHistory.score > 0,
    `score ${withHistory.score}`);
}

console.log('\n--- a carrier nobody has used yet ---');
// The trap this avoids: scoring an unknown carrier at zero means it never gets work, and never
// getting work means it never earns a record. The ranking could then never learn anything new.
const tag = Date.now().toString(36).slice(-5);
const fresh = send('POST', '/api/delivery-providers', {
  slug: `scored-${tag}`, name: `Scored Test ${tag}`, accountRef: 'ACC-CARRIER',
});
check('a new carrier registers', fresh.code === '201', `HTTP ${fresh.code}`);
const freshId = fresh.code === '201' ? JSON.parse(fresh.body).id : null;

const afterScores = get('/api/delivery-providers/scores');
const freshScore = afterScores.find(s => s.providerId === freshId);
check('it is scored, not omitted', !!freshScore, freshScore ? `score ${freshScore.score}` : 'missing');
check('at a neutral score rather than zero', freshScore && freshScore.score === 70,
  `${freshScore?.score}`);
check('and flagged provisional', freshScore?.provisional === true, `${freshScore?.provisional}`);
check('with no orders behind it', freshScore?.orders === 0, `${freshScore?.orders}`);

console.log('\n--- what dispatch would actually pick ---');
const ranked = get('/api/delivery-providers/ranked', merchant);
check('a merchant can see the ranking', Array.isArray(ranked) && ranked.length > 0,
  `${ranked.length} carriers`);
check('best first', ranked.every((s, i) => i === 0 || ranked[i - 1].score >= s.score), 'descending');
// "The platform chooses" is only reasonable to accept if you can see what it would choose.
check('and it names them', ranked.every(s => typeof s.name === 'string' && s.name.length > 0));

console.log('\n--- who may see it ---');
const merchantOnScores = send('GET', '/api/delivery-providers/scores', null, merchant);
check('a merchant cannot read the whole register\'s scores',
  merchantOnScores.code === '403', `HTTP ${merchantOnScores.code}`);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
