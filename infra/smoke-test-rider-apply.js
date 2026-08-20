// A rider applying from the app, with no account at all.
//
//   node infra/smoke-test-rider-apply.js
//
// Walks the exact calls RideWithUsScreen makes, in order and with no token: list the companies,
// prove an email, skip the phone, apply. If any one of these needs authentication the screen is
// unreachable for the only people who would ever open it.
//
// The other half is what must stay shut. Opening a list of company names is fine — they are painted
// on the bikes — but the endpoints beside it register companies, suspend them and read their
// scores, and a wildcard would have opened all of it.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';

const sh = (c) => { try { return execSync(c, { encoding: 'utf8', maxBuffer: 2e7 }); } catch (e) { return e.stdout || ''; } };
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const anon = (m, p, body) => {
  const data = body ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return split(sh(`curl -s -X ${m} -w "~~%{http_code}"${data} "${GW}${p}"`));
};
const psql = (q) => sh('docker exec delivery-postgres psql -U delivery -d delivery -tAc '
  + `"${q.replace(/"/g, '\\"')}"`).trim();

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

console.log('--- step 1: who is hiring, with no account ---');
const listed = anon('GET', '/api/delivery-providers/hiring');
check('the list is readable by a stranger', listed.code === '200', `HTTP ${listed.code}`);

let companies = [];
try { companies = JSON.parse(listed.body); } catch { /* reported below */ }
check('and it has companies in it', companies.length > 0, `${companies.length} hiring`);
check('each carries an id and a name',
  companies.every((c) => c.id && c.name), 'id + name');
// The thinnest possible answer. Anything else on the record — payout state, score, contact
// details, the fleet — is nobody's business until they work there.
const leaked = ['payoutState', 'accountRef', 'contactPhone', 'score', 'status', 'ownerRef']
  .filter((field) => companies.some((c) => c[field] !== undefined));
check('and nothing else about the company', leaked.length === 0,
  leaked.length ? `LEAKED ${leaked.join(', ')}` : 'id and name only');

console.log('\n--- what stays shut beside it ---');
for (const [what, method, path] of [
  ['listing every company', 'GET', '/api/delivery-providers'],
  ['registering one', 'POST', '/api/delivery-providers'],
  ['their scores', 'GET', '/api/delivery-providers/scores'],
  ['a company\'s riders', 'GET', `/api/delivery-providers/${companies[0]?.id}/riders`],
]) {
  const refused = anon(method, path, method === 'POST' ? { slug: 'x', name: 'X' } : null);
  check(`${what} still needs a token`, refused.code === '401', `HTTP ${refused.code}`);
}

console.log('\n--- steps 2-4: prove an address, skip the phone, apply ---');
const tag = Date.now().toString(36).slice(-6);
const email = `app-rider-${tag}@example.test`;

check('a code can be asked for',
  anon('POST', '/api/onboarding/verifications', { channel: 'EMAIL', destination: email })
    .code === '200', 'sent');

const message = psql('SELECT body FROM notification.notification_log WHERE recipient = '
  + `'${email}' ORDER BY created_at DESC LIMIT 1`);
const code = (message.match(/\b(\d{6})\b/) || [])[1];
check('and it reaches the address', !!code, code ? 'delivered' : 'NOTHING SENT');

const confirmed = code
  ? anon('POST', '/api/onboarding/verifications/confirm',
      { channel: 'EMAIL', destination: email, code })
  : { code: 'skipped', body: '{}' };
check('confirming returns the proof', confirmed.code === '200', `HTTP ${confirmed.code}`);
const token = (() => { try { return JSON.parse(confirmed.body).token; } catch { return null; } })();

// Exactly the body applyAsRider sends when the phone step is skipped.
const applied = anon('POST', '/api/onboarding/applications', {
  kind: 'RIDER',
  businessName: `Rider ${tag}`,
  contactName: `Rider ${tag}`,
  contactEmail: email,
  emailVerificationToken: token,
  contactPhone: null,
  phoneVerificationToken: null,
  targetProviderId: companies[0]?.id,
  notes: 'Applied from the app',
});
check('the application is accepted with no phone', applied.code === '201', `HTTP ${applied.code}`);

const reference = (() => { try { return JSON.parse(applied.body).reference; } catch { return null; } })();
check('and hands back a reference to keep', (reference || '').length >= 20,
  `${(reference || '').length} chars`);

// The receipt screen shows this reference; following it must work without an account, because the
// applicant still has not got one.
const followed = reference
  ? anon('GET', `/api/onboarding/applications/by-reference/${reference}`)
  : { code: 'skipped', body: '{}' };
check('the applicant can follow it with no account', followed.code === '200',
  followed.code === '200' ? JSON.parse(followed.body).status : `HTTP ${followed.code}`);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
