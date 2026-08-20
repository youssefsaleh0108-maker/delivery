// A delivery company can finally see and run its own operation.
//
//   node infra/smoke-test-carrier-portal.js
//
// The supply side of this marketplace had no surface at all: no CARRIER role existed, and every
// provider endpoint was BACKOFFICE- or MERCHANT-gated. A carrier could not check its own riders,
// take itself out of rotation for the night, or find out why it was being sent no work.
//
// The checks that matter most here are the negative ones. Everything a carrier can reach is scoped
// through "my company", so the interesting question is not whether they can see their own — it is
// whether they can reach anybody else's.
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u, p) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${p ?? u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const back = token('backoffice');
const carrier = token('carrier');
const merchant = token('merchant');
const carrierSub = JSON.parse(Buffer.from(carrier.split('.')[1], 'base64url').toString()).sub;

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
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

const tag = Date.now().toString(36).slice(-5);

// What this account really belongs to, so the suite can put it back. The seeded stack attaches it
// to a demo company precisely so somebody opening the app sees jobs rather than an empty state, and
// a test that left it detached would quietly undo that for every later reader.
const originalCompany = (() => {
  const r = send('GET', '/api/delivery-providers/my-company', null, carrier);
  return r.code === '200' ? JSON.parse(r.body).id : null;
})();

console.log('--- before they are attached to anything ---');
// Detached first, rather than assuming the demo account happens to be. It is attached to a company
// in the seeded stack so the app is usable the moment somebody opens it, and a test that depended
// on it being orphaned would fail for anybody who had.
send('DELETE', `/api/delivery-providers/staff/${carrierSub}`, null);
const orphan = send('GET', '/api/delivery-providers/my-company', null, carrier);
// 404, not 403: whether this account belongs to a delivery company is not worth confirming.
check('a carrier with no company gets nothing', orphan.code === '404', `HTTP ${orphan.code}`);

console.log('\n--- the platform onboards them ---');
const registered = send('POST', '/api/delivery-providers', {
  slug: `portal-${tag}`, name: `Portal Couriers ${tag}`,
  contactName: 'Cara', contactPhone: '+9611000222', accountRef: 'ACC-CARRIER',
});
check('a company is registered', registered.code === '201', `HTTP ${registered.code}`);
const company = JSON.parse(registered.body);

const attach = send('POST', `/api/delivery-providers/${company.id}/staff`, { riderRef: carrierSub });
check('and the carrier is attached to it', attach.code === '204', `HTTP ${attach.code}`);

console.log('\n--- what they can now see ---');
const mine = get('/api/delivery-providers/my-company', carrier);
check('they can read their own company', mine.id === company.id, mine.name);
check('including its payout state', mine.payoutState === 'VERIFIED', mine.payoutState);
check('and their own riders', Array.isArray(get('/api/delivery-providers/my-company/riders', carrier).riders));

const score = get('/api/delivery-providers/my-company/score', carrier);
// A ranking nobody can see is a black box that appears to hand out work arbitrarily.
check('and their own score', typeof score.score === 'number', `score ${score.score}`);
check('with the parts that make it up', typeof score.completionRate === 'number',
  `${(score.completionRate * 100).toFixed(0)}% delivered, provisional=${score.provisional}`);

console.log('\n--- running their own operation ---');
const paused = send('POST', '/api/delivery-providers/my-company/pause', null, carrier);
check('they can take themselves out of rotation', paused.code === '200', `HTTP ${paused.code}`);
check('and it took effect', JSON.parse(paused.body).status === 'PAUSED',
  JSON.parse(paused.body).status);
const resumed = send('POST', '/api/delivery-providers/my-company/resume', null, carrier);
check('and put themselves back', JSON.parse(resumed.body).status === 'ACTIVE',
  JSON.parse(resumed.body).status);

console.log('\n--- what they must NOT be able to reach ---');
// The whole register, including every rival's bank details.
check('not the register of all carriers',
  send('GET', '/api/delivery-providers', null, carrier).code === '403', 'forbidden');
check('not another carrier by id',
  ['403', '404'].includes(send('GET', '/api/delivery-providers/00000000-0000-4000-8000-00000000d001',
    null, carrier).code), 'refused');

// The in-house fleet is the platform's own capacity; a third party pausing it would be a
// denial-of-service dressed up as a setting.
//
// 403 rather than 404 here, and that is correct: the by-id pause endpoint does not accept the
// CARRIER role at all, so the rejection happens at the role gate and is identical whatever id is
// asked for. It therefore confirms nothing about whether that carrier exists — which is the only
// reason the rest of this API prefers 404. A carrier pauses itself through /my-company/pause;
// giving them a second route to the same thing would be one more place to get the scoping wrong.
const pauseInHouse = send('POST',
  '/api/delivery-providers/00000000-0000-4000-8000-00000000d001/pause', null, carrier);
check('and cannot pause the platform\'s own fleet',
  pauseInHouse.code === '403', `HTTP ${pauseInHouse.code}`);

// A second company, to prove the scoping is per-carrier rather than per-role.
const other = JSON.parse(send('POST', '/api/delivery-providers', {
  slug: `rival-${tag}`, name: `Rival Couriers ${tag}`, accountRef: 'ACC-CARRIER',
}).body);
const pauseRival = send('POST', `/api/delivery-providers/${other.id}/pause`, null, carrier);
check('nor pause a rival', pauseRival.code === '403',
  `HTTP ${pauseRival.code} — same answer as for any id, so nothing is revealed`);
check('nor onboard anybody',
  send('POST', '/api/delivery-providers', { slug: `sneak-${tag}`, name: 'Sneak' }, carrier).code === '403',
  'forbidden');
check('nor attach staff to a company',
  send('POST', `/api/delivery-providers/${other.id}/staff`, { riderRef: carrierSub }, carrier).code === '403',
  'forbidden');

console.log('\n--- and nobody else gets the carrier surface ---');
check('a merchant cannot use my-company',
  send('GET', '/api/delivery-providers/my-company', null, merchant).code === '403',
  'forbidden');

console.log('\n--- the platform can still see everything ---');
const staff = get(`/api/delivery-providers/${company.id}/staff`);
check('backoffice can list a carrier\'s staff', staff.riders.includes(carrierSub),
  `${staff.riders.length} attached`);
const detached = send('DELETE', `/api/delivery-providers/staff/${carrierSub}`);
check('and detach them', detached.code === '204', `HTTP ${detached.code}`);
check('after which the carrier sees nothing again',
  send('GET', '/api/delivery-providers/my-company', null, carrier).code === '404', 'gone');

// Put the account back where it was found. Leaving it detached is what made the carrier app open on
// "you are not a member of any delivery company" for anybody who ran the suite.
if (originalCompany !== null) {
  send('POST', `/api/delivery-providers/${originalCompany}/staff`, { riderRef: carrierSub });
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
