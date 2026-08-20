// A carrier's payout account, checked against the bank before it is ever used.
//
//   node infra/smoke-test-payout-verification.js
//
// The bug this covers: an account number typed at registration was taken on trust and first tested
// by a real delivery. ACC-CARRIER did not exist at the bank, every unit test passed, and it showed
// up as a PROVIDER_CREDIT leg that could not post — after the cash was collected and the rider had
// already been.
//
// The property under test is not "we call the bank". It is that a REFUSAL and an OUTAGE are treated
// differently: one is the carrier's problem and blocks onboarding, the other is ours and must not.
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
const send = (m, p, b, t) => split(call(m, p, b, t));
const get = (p, t) => JSON.parse(split(call('GET', p, null, t)).body);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 56).padEnd(56) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 56).padEnd(56) + (detail ?? '')); }
};

// Unique per run: slugs are unique and this suite registers several carriers.
const tag = Date.now().toString(36).slice(-5);
const register = (suffix, accountRef) => send('POST', '/api/delivery-providers', {
  slug: `payout-${suffix}-${tag}`,
  name: `Payout Test ${suffix} ${tag}`,
  contactName: 'Ada',
  contactPhone: '+10000000',
  accountRef,
});

console.log('--- an account the bank has never heard of ---');
const ghost = register('ghost', 'ACC-DOES-NOT-EXIST');
check('registering with it is refused', ghost.code === '422', `HTTP ${ghost.code}`);
check('and the reason names the account', ghost.body.includes('ACC-DOES-NOT-EXIST'),
  ghost.body.slice(0, 90));
// Not half-registered: the carrier must not exist at all rather than exist unpayable.
const afterGhost = get('/api/delivery-providers?size=200').content
  .filter(p => p.slug === `payout-ghost-${tag}`);
check('and no carrier was created', afterGhost.length === 0, `${afterGhost.length} found`);

console.log('\n--- an account that exists but cannot be paid into ---');
// The subtler half. A frozen account passes any "does it exist" check and still cannot receive
// money, so existence alone was never the right question.
const frozen = register('frozen', 'ACC-FROZEN');
check('a frozen account is refused too', frozen.code === '422', `HTTP ${frozen.code}`);
check('and says what is wrong with it', /FROZEN/i.test(frozen.body), frozen.body.slice(0, 90));

console.log('\n--- an account the bank confirms ---');
const good = register('good', 'ACC-CARRIER');
check('registering succeeds', good.code === '201', `HTTP ${good.code}`);
const created = good.code === '201' ? JSON.parse(good.body) : {};
check('and it is recorded as verified', created.payoutState === 'VERIFIED', created.payoutState);
check('with the moment it was checked', !!created.payoutCheckedAt, created.payoutCheckedAt ?? 'null');
// The holder name is the only thing that catches a real account belonging to the wrong company.
check('and the name the bank has on the account',
  (created.payoutDetail ?? '').includes('Test Delivery Company'), created.payoutDetail);

console.log('\n--- a carrier with no payout account ---');
const none = register('none', null);
check('registers without a bank check', none.code === '201', `HTTP ${none.code}`);
check('and is neither verified nor flagged',
  JSON.parse(none.body).payoutState === 'NONE', JSON.parse(none.body).payoutState);

console.log('\n--- the work list ---');
const unconfirmed = get('/api/delivery-providers/unconfirmed-payout');
check('carriers onboarded before this check are flagged', unconfirmed.length > 0,
  `${unconfirmed.length} to chase`);
check('and the verified one is not among them',
  !unconfirmed.some(p => p.id === created.id), 'absent');
check('nor is anyone without an account',
  !unconfirmed.some(p => !p.accountRef), 'none accountless');

console.log('\n--- a bank that is down ---');
// The case the whole three-valued design exists for, and the one that cannot be tested by feeding
// in a bad account number: the bank being unreachable must NOT read as a bad account.
const faults = (mode) => JSON.parse(sh('curl -s -X POST -H "Content-Type: application/json"'
  + ` -d "{\\"mode\\":\\"${mode}\\",\\"latencyMs\\":0,\\"callCount\\":0}"`
  + ' "http://127.0.0.1:8114/test/faults"'));

// Held until reset rather than expiring after a set number of calls. A call budget looks safer and
// is not: other services talk to this simulator continuously, so a one-call fault is usually spent
// by somebody else's posting before the registration below ever reaches the bank — which is exactly
// how this check first passed while proving nothing.
check('the bank can be taken down for this test',
  faults('UNAVAILABLE').mode === 'UNAVAILABLE', 'fault injected');
const duringOutage = register('outage', 'ACC-CARRIER');
check('a carrier can still be onboarded while the bank is down',
  duringOutage.code === '201', `HTTP ${duringOutage.code}`);
const outaged = duringOutage.code === '201' ? JSON.parse(duringOutage.body) : {};
check('but the account is marked unconfirmed, not verified',
  outaged.payoutState === 'UNCONFIRMED', outaged.payoutState);
check('and the reason is ours, not theirs',
  /unavailable|unreachable|HTTP 5/i.test(outaged.payoutDetail ?? ''), outaged.payoutDetail);

console.log('\n--- re-checking, the other half of not blocking on an outage ---');
// Without this every carrier onboarded while the bank was down stays flagged forever, and a state
// that never clears stops being read.
check('and put back', faults('HEALTHY').mode === 'HEALTHY', 'fault cleared');
const cleared = send('POST', `/api/delivery-providers/${outaged.id}/verify-payout`);
check('once the bank is back, re-checking clears the flag',
  cleared.code === '200' && JSON.parse(cleared.body).payoutState === 'VERIFIED',
  `HTTP ${cleared.code} ${JSON.parse(cleared.body).payoutState}`);

// Recorded, not thrown: the account is already on file and already being paid into, so the useful
// outcome is making that visible rather than leaving the record saying what it said before.
const legacyBad = unconfirmed.find(p => p.accountRef === 'ACC-SWIFT');
if (legacyBad) {
  const rechecked = send('POST', `/api/delivery-providers/${legacyBad.id}/verify-payout`);
  check('re-checking an account the bank refuses records that',
    rechecked.code === '200' && JSON.parse(rechecked.body).payoutState === 'UNCONFIRMED',
    `HTTP ${rechecked.code}`);
  check('and says the bank has no such account',
    /no such account/i.test(JSON.parse(rechecked.body).payoutDetail ?? ''),
    JSON.parse(rechecked.body).payoutDetail);
} else {
  // Only reachable on a database with no carriers predating this check — there is then nothing on
  // file with a refused account, and no way to put one there, which is the feature working.
  console.log('  ....  no carrier with a refused account on file; nothing to re-check');
}

const noAccount = JSON.parse(none.body);
const cannot = send('POST', `/api/delivery-providers/${noAccount.id}/verify-payout`);
check('a carrier with no account cannot be checked', cannot.code === '422', `HTTP ${cannot.code}`);

console.log('\n--- a merchant still cannot read a carrier\'s banking ---');
// The account was already withheld from merchants; whether the bank confirmed it is the same kind
// of fact and travels with it.
const visible = get('/api/delivery-providers/available', merchant);
check('merchants see carriers', visible.length > 0, `${visible.length} available`);
check('but no account numbers', visible.every(p => !p.accountRef), 'all stripped');
check('and no payout state', visible.every(p => !p.payoutState), 'all stripped');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
