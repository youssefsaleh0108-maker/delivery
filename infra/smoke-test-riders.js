// Riders are hired by a delivery company, not by the platform.
//
//   node infra/smoke-test-riders.js
//
// The properties that matter here are all about who decides. A rider applies to one company, and:
//
//   * that company sees the application and nobody else's,
//   * a different company cannot read it or decide it by putting its own id in the path,
//   * the platform's own queue does not show it at all — otherwise two reviewers hold one decision
//     and the platform ends up choosing somebody else's staff whenever it gets there first,
//   * approving creates an account with DELIVERY and puts them on that company's RIDER list, which
//     is the list dispatch actually reads.
//
// That last one is the whole point: a rider attached to the wrong list has an account that signs in
// and is never offered a single job.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';

const sh = (c) => { try { return execSync(c, { encoding: 'utf8', maxBuffer: 2e7 }); } catch (e) { return e.stdout || ''; } };
const token = (u) => {
  const raw = sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
    + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`);
  try { return JSON.parse(raw).access_token; } catch { return null; }
};
const call = (m, p, body, tok) => {
  const auth = tok ? ` -H "Authorization: Bearer ${tok}"` : '';
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}"${auth}${data} "${GW}${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, p, b, t));
const get = (p, t) => { try { return JSON.parse(send('GET', p, null, t).body); } catch { return null; } };
const psql = (q) => sh('docker exec delivery-postgres psql -U delivery -d delivery -tAc '
  + `"${q.replace(/"/g, '\\"')}"`).trim();

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};
const waitFor = (predicate, what, attempts = 40) => {
  for (let i = 0; i < attempts; i++) {
    const value = predicate();
    if (value) return value;
    execSync(process.platform === 'win32' ? 'ping -n 2 127.0.0.1 > NUL' : 'sleep 0.5');
  }
  console.log(`        gave up waiting for ${what}`);
  return null;
};

const backoffice = token('backoffice');
const carrier = token('carrier');

// ---------------------------------------------------------------- a verified applicant

/** Earns a real verification the same way a person does: ask for a code, read it, confirm it. */
const verifiedEmail = (address) => {
  send('POST', '/api/onboarding/verifications', { channel: 'EMAIL', destination: address }, null);
  const message = psql('SELECT body FROM notification.notification_log WHERE recipient = '
    + `'${address}' ORDER BY created_at DESC LIMIT 1`);
  const code = (message.match(/\b(\d{6})\b/) || [])[1];
  if (!code) return null;
  const confirmed = send('POST', '/api/onboarding/verifications/confirm',
    { channel: 'EMAIL', destination: address, code }, null);
  try { return JSON.parse(confirmed.body).token; } catch { return null; }
};

const company = get('/api/delivery-providers/my-company', carrier);
if (!company) {
  console.error('The `carrier` account runs no company; run smoke-test-onboarding.js first.');
  process.exit(1);
}
console.log(`    hiring company: ${company.name} (${company.id})\n`);

const tag = Date.now().toString(36).slice(-6);
const riderEmail = `rider-${tag}@example.test`;

console.log('--- a rider applies to one company ---');
const emailToken = verifiedEmail(riderEmail);
check('the applicant proves their address', !!emailToken, emailToken ? 'verified' : 'NO CODE');

const applied = send('POST', '/api/onboarding/applications', {
  kind: 'RIDER',
  businessName: `Rider ${tag}`,
  contactName: 'Ali Rider',
  contactEmail: riderEmail,
  emailVerificationToken: emailToken,
  targetProviderId: company.id,
  notes: 'Own motorbike, evenings',
}, null);
check('a rider application is accepted', applied.code === '201', `HTTP ${applied.code}`);

// A rider with no company is an application nobody can decide.
const noCompany = send('POST', '/api/onboarding/applications', {
  kind: 'RIDER', businessName: 'Nowhere', contactName: 'Ali',
  contactEmail: riderEmail, emailVerificationToken: emailToken,
}, null);
check('a rider who names no company is refused', noCompany.code === '422', `HTTP ${noCompany.code}`);

console.log('\n--- it is the company\'s queue, not the platform\'s ---');
const mine = get(`/api/onboarding/applications/for-company/${company.id}`, carrier);
const application = (mine || []).find((a) => a.contactEmail === riderEmail);
check('the company sees it', !!application, `${(mine || []).length} waiting`);
check('and it names them as the company applied to',
  application && application.targetProviderId === company.id, 'their own id');

// The platform must not also be holding this decision.
const platformQueue = get('/api/onboarding/applications', backoffice) || [];
check('the Backoffice queue does not show it',
  !platformQueue.some((a) => a.contactEmail === riderEmail),
  `${platformQueue.length} on the platform's own queue`);
check('and shows no rider applications at all',
  !platformQueue.some((a) => a.kind === 'RIDER'), 'merchants and carriers only');

console.log('\n--- another company cannot reach it ---');
const someoneElse = '00000000-0000-4000-8000-000000000001';
check('a carrier cannot read a company they do not run',
  send('GET', `/api/onboarding/applications/for-company/${someoneElse}`, null, carrier).code === '403',
  'forbidden');
check('nor approve through it',
  send('POST', `/api/onboarding/applications/for-company/${someoneElse}/${application.id}/approve`,
    null, carrier).code === '403', 'forbidden');
// Their own company id, somebody else's application: the id in the path is not enough on its own.
check('nor decide an application addressed elsewhere',
  send('POST', `/api/onboarding/applications/for-company/${company.id}/`
    + '00000000-0000-4000-8000-000000000009/approve', null, carrier).code === '422', 'no such application');
check('a merchant has no business here at all',
  send('GET', `/api/onboarding/applications/for-company/${company.id}`, null, token('merchant'))
    .code === '403', 'forbidden');
check('and nor does an anonymous caller',
  send('GET', `/api/onboarding/applications/for-company/${company.id}`, null, null).code === '401',
  'unauthorised');

console.log('\n--- the company hires them ---');
const hired = send('POST',
  `/api/onboarding/applications/for-company/${company.id}/${application.id}/approve`, null, carrier);
check('the company approves its own applicant', hired.code === '200', `HTTP ${hired.code}`);

const provisioned = waitFor(() => {
  const a = get(`/api/onboarding/applications/for-company/${company.id}?all=true`, carrier)
    ?.find((x) => x.id === application.id);
  return a && a.status === 'PROVISIONED' ? a : null;
}, 'the rider to be set up');
check('and the process sets them up', provisioned !== null,
  provisioned ? provisioned.status : 'never got there');
check('an account was created', provisioned && !!provisioned.provisionedUserRef,
  provisioned && provisioned.provisionedUserRef);

if (provisioned) {
  // The check that matters. /riders is what dispatch and a claim consult; /staff is who runs the
  // company. Attaching a new rider to staff produces an account that signs in and is offered
  // nothing, and looks correct from every screen until somebody wonders why they never get work.
  const riders = get(`/api/delivery-providers/${company.id}/riders`, backoffice);
  check('they are on the company\'s RIDER list',
    (riders?.riders || []).includes(provisioned.provisionedUserRef), 'dispatchable');
  const staff = get(`/api/delivery-providers/${company.id}/staff`, backoffice);
  check('and not quietly added as staff who run the company',
    !(staff?.riders || []).includes(provisioned.provisionedUserRef), 'not staff');
}

console.log('\n--- turning somebody down ---');
const otherEmail = `rider-no-${tag}@example.test`;
const otherToken = verifiedEmail(otherEmail);
send('POST', '/api/onboarding/applications', {
  kind: 'RIDER', businessName: `Rider No ${tag}`, contactName: 'Sami Rider',
  contactEmail: otherEmail, emailVerificationToken: otherToken, targetProviderId: company.id,
}, null);
const declined = get(`/api/onboarding/applications/for-company/${company.id}`, carrier)
  .find((a) => a.contactEmail === otherEmail);

check('a refusal with no reason is rejected',
  send('POST', `/api/onboarding/applications/for-company/${company.id}/${declined.id}/reject`,
    { reason: '' }, carrier).code === '400', 'validation');
check('one with a reason works',
  send('POST', `/api/onboarding/applications/for-company/${company.id}/${declined.id}/reject`,
    { reason: 'We are not taking on evenings just now' }, carrier).code === '200', 'declined');
// The applicant holds only their reference, and it has to keep telling them the truth.
const asApplicant = get(
  `/api/onboarding/applications/by-reference/${JSON.parse(applied.body).reference}`, null);
check('the applicant can still follow their own application',
  asApplicant && asApplicant.status === 'PROVISIONED', asApplicant && asApplicant.status);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
