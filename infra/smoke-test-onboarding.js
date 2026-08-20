// Joining the platform, from a form on a public website to an account that can sign in.
//
//   node infra/smoke-test-onboarding.js
//
// The check that matters most is the last one: an approved carrier ends up with a Keycloak account
// that actually gets a token, and a delivery company they actually run. Anything short of that is a
// process that looks finished and leaves somebody unable to log in.
//
// The second is the open endpoint. Submitting has to work with no token — a prospective merchant
// has no account, because getting one is what they are asking for — so everything around it has to
// be checked precisely: no reading anybody else's application, no listing, no deciding.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';

const sh = (c) => { try { return execSync(c, { encoding: 'utf8', maxBuffer: 2e7 }); } catch (e) { return e.stdout || ''; } };
const token = (u, p) => {
  const raw = sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
    + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${p ?? u}" -d "grant_type=password" -d "scope=openid"`);
  try { return JSON.parse(raw).access_token; } catch { return null; }
};

const backoffice = token('backoffice');
const merchant = token('merchant');

const call = (m, p, body, tok) => {
  const auth = tok ? ` -H "Authorization: Bearer ${tok}"` : '';
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}"${auth}${data} "${GW}${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, p, b, t));
const get = (p, t) => JSON.parse(send('GET', p, null, t).body);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

/// Provisioning runs as Camunda jobs on a background thread, so reading straight after a decision
/// is a race. Polls rather than sleeping a fixed amount.
const waitFor = (predicate, what, attempts = 40) => {
  for (let i = 0; i < attempts; i++) {
    const value = predicate();
    if (value) return value;
    execSync(process.platform === 'win32' ? 'ping -n 2 127.0.0.1 > NUL' : 'sleep 0.5');
  }
  console.log(`        gave up waiting for ${what}`);
  return null;
};

const tag = Date.now().toString(36).slice(-6);
const carrierEmail = `fleet-${tag}@example.test`;
const merchantEmail = `shop-${tag}@example.test`;

const psql = (q) => sh('docker exec delivery-postgres psql -U delivery -d delivery -tAc '
  + `"${q.replace(/"/g, '\\"')}"`).trim();

// Earns a real verification the way a person does: ask for a code, read it out of the delivery
// log (this environment's stand-in for an inbox), and confirm it.
//
// An application needs a proved address now, so this suite has to prove one. Applying without a
// token is no longer a shortcut — it is a different test, and it belongs with the refusals
// rather than at the top pretending to be the happy path.
const verify = (address) => {
  send('POST', '/api/onboarding/verifications', { channel: 'EMAIL', destination: address }, null);
  const message = psql('SELECT body FROM notification.notification_log WHERE recipient = '
    + `'${address}' ORDER BY created_at DESC LIMIT 1`);
  const code = (message.match(/\b(\d{6})\b/) || [])[1];
  if (!code) return null;
  const confirmed = send('POST', '/api/onboarding/verifications/confirm',
    { channel: 'EMAIL', destination: address, code }, null);
  try { return JSON.parse(confirmed.body).token; } catch { return null; }
};

const apply = (kind, name, email, token) => send('POST', '/api/onboarding/applications', {
  kind, businessName: name, contactName: 'Sam Owner',
  contactEmail: email, emailVerificationToken: token ?? verify(email),
  notes: 'Submitted by the onboarding smoke test',
}, null);

console.log('--- anybody can apply, because an applicant has no account ---');
const applied = apply('CARRIER', `Fleet ${tag}`, carrierEmail);
check('an unauthenticated application is accepted', applied.code === '201', `HTTP ${applied.code}`);
const receipt = JSON.parse(applied.body);
check('and comes back with a reference', (receipt.reference || '').length >= 20,
  `${(receipt.reference || '').length} chars`);
check('marked as submitted', receipt.status === 'SUBMITTED', receipt.status);
// The receipt is readable by anybody holding the reference, including whoever it was forwarded to.
check('the receipt carries no internal id', receipt.id === undefined, 'withheld');
check('and no reviewer name', receipt.decidedBy === undefined, 'withheld');

console.log('\n--- but applying is all an applicant can do ---');
check('they cannot list the queue',
  send('GET', '/api/onboarding/applications', null, null).code === '401', 'unauthorised');
check('nor read one by id',
  send('GET', `/api/onboarding/applications/00000000-0000-4000-8000-000000000001`, null, null)
    .code === '401', 'unauthorised');
check('nor approve anything',
  send('POST', `/api/onboarding/applications/00000000-0000-4000-8000-000000000001/approve`,
    null, null).code === '401', 'unauthorised');
check('a merchant cannot review applications',
  send('GET', '/api/onboarding/applications', null, merchant).code === '403', 'forbidden');

console.log('\n--- checking your own application, with the reference you were given ---');
const mine = get(`/api/onboarding/applications/by-reference/${receipt.reference}`, null);
check('the reference reads back the application', mine.businessName === `Fleet ${tag}`,
  mine.businessName);
// 160 random bits, precisely because there is no caller identity to check it against.
check('a wrong reference reveals nothing',
  send('GET', '/api/onboarding/applications/by-reference/not-a-real-reference', null, null)
    .code === '404', 'not found');

console.log('\n--- one live application per business ---');
// Applying a second time now takes a second verification, and the resend cooldown deliberately
// refuses one for the first minute. So this waits it out rather than asserting on the 400 that a
// missing token produces — that would be a test of validation dressed up as a test of the
// duplicate rule, passing for the wrong reason the day the rule was removed.
console.log(`        waiting out the ${61}s resend cooldown to earn a second code…`);
execSync(process.platform === 'win32' ? 'ping -n 62 127.0.0.1 > NUL' : 'sleep 61');

const secondToken = verify(carrierEmail);
check('a second code can be had once the cooldown passes', !!secondToken,
  secondToken ? 'verified again' : 'still refused');

const duplicate = apply('CARRIER', `Fleet ${tag}`, carrierEmail, secondToken);
// Two reviewers doing the same work and possibly disagreeing is the failure this prevents.
check('applying twice while the first is open is refused', duplicate.code === '422',
  `HTTP ${duplicate.code}`);
check('with a reason the applicant can act on',
  (() => { try { return (JSON.parse(duplicate.body).message || '').length > 0; } catch { return false; } })(),
  (() => { try { return JSON.parse(duplicate.body).message; } catch { return duplicate.body.slice(0, 40); } })());

console.log('\n--- the platform reviews it ---');
const queue = get('/api/onboarding/applications', backoffice);
const queued = queue.find((a) => a.reference === receipt.reference);
check('it appears in the reviewer queue', !!queued, `${queue.length} waiting`);
check('with the contact details a reviewer needs', queued && queued.contactEmail === carrierEmail,
  queued && queued.contactEmail);
check('and the notes the applicant wrote',
  queued && (queued.notes || '').includes('smoke test'), 'present');

console.log('\n--- a rejection has to say why ---');
const rejected = apply('MERCHANT', `Doomed Shop ${tag}`, `doomed-${tag}@example.test`);
const doomedId = get('/api/onboarding/applications', backoffice)
  .find((a) => a.reference === JSON.parse(rejected.body).reference).id;
check('rejecting with no reason is refused',
  send('POST', `/api/onboarding/applications/${doomedId}/reject`, { reason: '' }, backoffice)
    .code === '400', 'validation');
const declined = send('POST', `/api/onboarding/applications/${doomedId}/reject`,
  { reason: 'The address given is outside the area we cover' }, backoffice);
check('rejecting with one works', declined.code === '200', `HTTP ${declined.code}`);
check('and the applicant is told why',
  get(`/api/onboarding/applications/by-reference/${JSON.parse(rejected.body).reference}`, null)
    .rejectionReason.includes('outside the area'), 'explained');
check('a decided application cannot be decided again',
  send('POST', `/api/onboarding/applications/${doomedId}/approve`, null, backoffice).code === '422',
  'already rejected');

console.log('\n--- approving a carrier provisions a real, working partner ---');
const approve = send('POST', `/api/onboarding/applications/${queued.id}/approve`, null, backoffice);
check('the platform approves it', approve.code === '200', `HTTP ${approve.code}`);

// Provisioning runs as Camunda jobs, so this is where the process either finishes its work or
// quietly stops halfway.
const provisioned = waitFor(() => {
  const a = get(`/api/onboarding/applications/${queued.id}`, backoffice);
  return a.status === 'PROVISIONED' ? a : null;
}, 'provisioning to finish');

check('and the process runs it through to provisioned', provisioned !== null,
  provisioned ? provisioned.status : 'never got there');
check('an account was created', provisioned && !!provisioned.provisionedUserRef,
  provisioned && provisioned.provisionedUserRef);
check('and a delivery company with it', provisioned && !!provisioned.provisionedEntityId,
  provisioned && provisioned.provisionedEntityId);

if (provisioned) {
  // The whole point. An approval that does not end in somebody able to sign in is a process that
  // looks finished and has not finished.
  const company = get(`/api/delivery-providers/${provisioned.provisionedEntityId}`, backoffice);
  check('the company exists and is named after the business',
    company.name === `Fleet ${tag}`, company.name);
  const staff = get(`/api/delivery-providers/${provisioned.provisionedEntityId}/staff`, backoffice);
  check('and the new account runs it',
    (staff.riders || []).includes(provisioned.provisionedUserRef), 'attached as staff');
}

console.log('\n--- a merchant is approved without a shop being invented for them ---');
const shop = apply('MERCHANT', `Shop ${tag}`, merchantEmail);
const shopId = get('/api/onboarding/applications', backoffice)
  .find((a) => a.reference === JSON.parse(shop.body).reference).id;
send('POST', `/api/onboarding/applications/${shopId}/approve`, null, backoffice);

const shopDone = waitFor(() => {
  const a = get(`/api/onboarding/applications/${shopId}`, backoffice);
  return a.status === 'PROVISIONED' ? a : null;
}, 'the merchant to be provisioned');
check('the merchant is provisioned', shopDone !== null,
  shopDone ? shopDone.status : 'never got there');
check('with an account', shopDone && !!shopDone.provisionedUserRef, 'created');
// Product Service provisions a shop on their first product, named by the person who trades from it.
// An empty store created here would be a row nobody asked for.
check('and deliberately no shop record yet',
  shopDone && shopDone.provisionedEntityId === null, 'left for their first product');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
