// Delivery as a pluggable service rather than a fixed in-house fleet.
//
//   node infra/smoke-test-providers.js
//
// The keystone of the marketplace: once whoever carries an order is a party rather than an
// assumption, a merchant can choose a carrier, a company can bring its own drivers, and a merchant's
// own fleet is just another provider — which is what makes overflow routing free later.
//
// Nothing visible changes today, and that is itself one of the checks: the in-house fleet is
// provider #1 and every existing rider belongs to it without a backfill.
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const back = token('backoffice');
const merchant = token('merchant');
const customer = token('customer');
const rider = token('rider');

const call = (m, p, body, tok = back) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, p, b, t));
const get = (p, t) => JSON.parse(split(call('GET', p, null, t)).body);
const detailOf = (b) => { try { return JSON.parse(b).detail ?? ''; } catch { return ''; } };
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 54) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 54) + (detail ?? '')); }
};

const IN_HOUSE = '00000000-0000-4000-8000-00000000d001';
const unique = Date.now().toString(36).slice(-6);

console.log('--- the in-house fleet exists, and nothing changed ---');
const all = get('/api/delivery-providers?size=50');
const inHouse = all.content.find(p => p.id === IN_HOUSE);
check('the platform fleet is seeded as a provider', !!inHouse, inHouse?.name);
check('it is a PLATFORM kind', inHouse?.kind === 'PLATFORM', inHouse?.kind);
check('it is active', inHouse?.canTakeWork === true);
// The absence of a membership row means in-house, which is what keeps every existing rider working.
check('it owns nobody, because membership is opt-in',
  get(`/api/delivery-providers/${IN_HOUSE}/riders`).riders.length === 0,
  'no explicit members needed');

console.log('\n--- onboarding a delivery company ---');
// ACC-CARRIER, not the ACC-SWIFT this suite used to invent. Payout accounts are now checked
// against the bank when they are set, and an account nobody holds is refused — which is the whole
// point of the check, and which this suite was quietly relying on the absence of.
const registered = send('POST', '/api/delivery-providers', {
  slug: `swift-${unique}`, name: 'Swift Couriers',
  contactName: 'Operations', contactPhone: '+9611000111', accountRef: 'ACC-CARRIER',
});
check('backoffice registers a company', registered.code === '201', `HTTP ${registered.code}`);
const swift = JSON.parse(registered.body);
check('it is EXTERNAL', swift.kind === 'EXTERNAL', swift.kind);
check('and carries its own payout account', swift.accountRef === 'ACC-CARRIER', swift.accountRef);
check('which the bank confirmed before it was stored',
  swift.payoutState === 'VERIFIED', swift.payoutState);
// Asserted here rather than only in the payout suite: this is the registration test, and "a
// carrier can be onboarded" must not be true for an account that cannot be paid.
check('a company whose account the bank has never heard of is refused',
  send('POST', '/api/delivery-providers', {
    slug: `ghost-${unique}`, name: 'Ghost Logistics', accountRef: 'ACC-NOT-A-REAL-ACCOUNT',
  }).code === '422', 'rejected at registration, not at the first delivery');
check('a duplicate handle is refused',
  send('POST', '/api/delivery-providers', { slug: `swift-${unique}`, name: 'Impostor' }).code === '409');
check('and a handle with spaces is refused before it reaches the database',
  send('POST', '/api/delivery-providers', { slug: 'not a slug', name: 'Bad' }).code === '400');

console.log('\n--- a merchant fleet is just another provider ---');
const mine = send('POST', '/api/delivery-providers/mine', null, merchant);
check('a merchant can create their own fleet', mine.code === '200', `HTTP ${mine.code}`);
const fleet = JSON.parse(mine.body);
check('it is a MERCHANT kind owned by them', fleet.kind === 'MERCHANT' && !!fleet.ownerRef,
  `owner ${fleet.ownerRef?.slice(0, 8)}`);
// A setting somebody will press twice.
check('asking again returns the same fleet, not a second one',
  JSON.parse(send('POST', '/api/delivery-providers/mine', null, merchant).body).id === fleet.id);

console.log('\n--- who may carry whose orders ---');
const available = get('/api/delivery-providers/available', merchant);
check('the merchant sees the in-house fleet', available.some(p => p.id === IN_HOUSE));
check('and the company', available.some(p => p.id === swift.id));
check('and their own drivers', available.some(p => p.id === fleet.id));
// The one that matters: a shop's drivers are not a supplier anybody else can book.
check('but never another merchant\'s fleet',
  available.every(p => p.kind !== 'MERCHANT' || p.ownerRef === fleet.ownerRef),
  `${available.length} available`);
check('and never a carrier\'s bank details while choosing between carriers',
  available.every(p => p.accountRef === null), 'accountRef stripped');

console.log('\n--- riders belong to a fleet ---');
check('a rider is assigned to the company',
  send('POST', `/api/delivery-providers/${swift.id}/riders`, { riderRef: 'rider-alpha' }).code === '204');
check('and shows on its roster',
  get(`/api/delivery-providers/${swift.id}/riders`).riders.includes('rider-alpha'));
// One employer at a time, or the same job appears on two boards and is claimed twice.
send('POST', `/api/delivery-providers/${fleet.id}/riders`, { riderRef: 'rider-alpha' });
check('moving them elsewhere leaves the old roster',
  !get(`/api/delivery-providers/${swift.id}/riders`).riders.includes('rider-alpha'));
check('and puts them on the new one',
  get(`/api/delivery-providers/${fleet.id}/riders`).riders.includes('rider-alpha'));
check('releasing them sends them back to in-house',
  send('DELETE', '/api/delivery-providers/riders/rider-alpha', null).code === '204');

console.log('\n--- taking a provider out of rotation ---');
check('a provider can pause itself', send('POST', `/api/delivery-providers/${fleet.id}/pause`, null, merchant).code === '200');
check('and it stops being available',
  !get('/api/delivery-providers/available', merchant).some(p => p.id === fleet.id));
check('it can resume', send('POST', `/api/delivery-providers/${fleet.id}/resume`, null, merchant).code === '200');

// The hole this closes: a role check alone would let any merchant pause a competitor's carrier, or
// the platform's own riders. That is a denial of service dressed up as a setting.
console.log('\n--- one merchant cannot pause another carrier ---');
check('a merchant cannot pause a delivery company',
  send('POST', `/api/delivery-providers/${swift.id}/pause`, null, merchant).code === '404',
  'and gets a flat not-found, not a 403 that confirms it exists');
check('a merchant cannot pause the in-house fleet',
  send('POST', `/api/delivery-providers/${IN_HOUSE}/pause`, null, merchant).code === '404');
check('the company is still taking work',
  get('/api/delivery-providers/available', merchant).some(p => p.id === swift.id));

console.log('\n--- suspension is the platform\'s, not the provider\'s ---');
check('backoffice suspends a company',
  send('POST', `/api/delivery-providers/${swift.id}/suspend`, null).code === '200');
// Otherwise suspension and pausing would be the same thing with two names.
//
// 422 specifically, not merely "not 200". An earlier version of this check accepted anything but
// success and happily passed on a 500 from an unmapped exception — the rule was being enforced by
// the service falling over, which is not the same as being enforced.
const selfResume = send('POST', `/api/delivery-providers/${swift.id}/resume`, null);
check('a suspended provider cannot simply resume', selfResume.code === '422',
  `HTTP ${selfResume.code}`);
check('and is told to be reinstated instead',
  detailOf(selfResume.body).includes('reinstated'), detailOf(selfResume.body).slice(0, 48));
check('but the platform can reinstate it',
  send('POST', `/api/delivery-providers/${swift.id}/reinstate`, null).code === '200');

console.log('\n--- authorisation ---');
check('a customer cannot list providers',
  send('GET', '/api/delivery-providers', null, customer).code === '403');
check('a customer cannot register one',
  send('POST', '/api/delivery-providers', { slug: 'x', name: 'X' }, customer).code === '403');
check('a merchant cannot list every provider',
  send('GET', '/api/delivery-providers', null, merchant).code === '403');
check('a rider cannot move themselves between fleets',
  send('POST', `/api/delivery-providers/${swift.id}/riders`, { riderRef: 'rider-x' }, rider).code === '403');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
