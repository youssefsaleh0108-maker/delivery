// A stranger becomes a partner — across the website, the back office, and the app.
//
//   node infra/scenario-partner-onboarding.mjs dev
//
// THE SCENARIO, as it happens to a real person:
//
//   1. They fill in the wizard on the public website and ask for a code to prove their email.
//   2. They type the code back in.
//   3. They submit the application. It is now somebody's job to look at it — or not.
//   4. They pick a passcode, so they can sign in and watch it.
//   5. They sign in, and what they can do depends on one setting.
//   6. If that setting says review, an operator finds them in the BACK OFFICE queue and approves.
//   7. They sign in again, and now they can trade.
//
// Every step is the real endpoint the real surface calls: steps 1-4 are what
// clients/website/register.js posts, step 6 is what the portal's onboarding screen does, and
// steps 5 and 7 are the app's own password grant. The only thing here a person would not do is
// read the code out of the notification log — the deployed environment's stand-in for an inbox.
//
// WHY IT READS THE POLICY FIRST RATHER THAN ASSUMING. Auto-approval is per applicant kind and is
// set from the portal at runtime, so the correct outcome of an application is not a constant. On
// dev today merchants are automatic and riders are not, which means the two kinds exercise
// DIFFERENT halves of the same flow — the instant-provision path and the human-review path — and
// a test that hard-codes either one is wrong half the time and, worse, is wrong the moment an
// operator changes their mind. This asks the platform what it intends, then holds it to it.
//
// It writes real data: one Keycloak account and one application per kind per run, tagged with the
// run id so they can be told apart from a person's.
import { execSync } from 'node:child_process';

const ENV = process.argv[2] || 'dev';
const API = `https://api-${ENV}.youdrop.shop`;
const IAM = `https://iam-${ENV}.youdrop.shop`;
const NS = `delivery-${ENV}`;

const RUN = Date.now().toString(36).toUpperCase();
const PASSCODE = '778899';

let pass = 0;
let fail = 0;
const ok = (what, detail = '') => { pass++; console.log(`  ok    ${what.padEnd(54)} ${detail}`); };
const bad = (what, detail = '') => { fail++; console.log(`  FAIL  ${what.padEnd(54)} ${detail}`); };

const call = async (method, path, { token, body } = {}) => {
  const res = await fetch(API + path, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not json */ }
  return { code: res.status, ok: res.ok, json, text };
};

const signIn = async (user, password, client = 'mobile-app') => {
  const res = await fetch(`${IAM}/realms/delivery-platform/protocol/openid-connect/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: client, username: user, password, grant_type: 'password' }),
  });
  return res.ok ? (await res.json()).access_token : null;
};

const rolesOf = (token) => {
  const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
  const all = claims.realm_access?.roles ?? claims.roles ?? [];
  // The three that decide what a person can do. The rest are Keycloak's own furniture.
  return all.filter((r) => ['APPLICANT', 'MERCHANT', 'DELIVERY', 'CARRIER'].includes(r));
};

/// The environment's inbox. A person reads the code in their mail client; there is no mail client
/// here, and the notification log is the row the mail relay sends from.
const codeSentTo = (address) => {
  const sql = `SELECT body FROM notification.notification_log WHERE recipient = '${address}' `
    + 'ORDER BY created_at DESC LIMIT 1';
  const out = execSync(
    `ssh delivery-vps "kubectl -n ${NS} exec postgres-0 -- psql -U delivery -d delivery -t -c \\"${sql}\\""`,
    { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 },
  );
  return (out.match(/\b(\d{6})\b/) || [])[1] ?? null;
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

console.log(`\n=== a stranger becomes a partner on ${ENV} ===\n`);

const backoffice = await signIn('backoffice', '400004', 'delivery-portal');
backoffice ? ok('an operator signs in to the portal') : bad('backoffice sign-in', 'no token');
if (!backoffice) process.exit(1);

// ---------------------------------------------------------------- what does the platform intend?

const policyRes = await call('GET', '/api/onboarding/admin/auto-approval', { token: backoffice });
const policy = policyRes.json;
policyRes.ok
  ? ok('the auto-approval policy is readable',
    `merchant ${policy.merchant.automatic ? 'AUTO' : 'REVIEW'} · rider ${policy.rider.automatic ? 'AUTO' : 'REVIEW'}`)
  : bad('reading the auto-approval policy', `HTTP ${policyRes.code}`);

/// One applicant, all the way through, held to whatever the policy says should happen to them.
async function applyAs(kind, roleWhenTrading, automatic) {
  const label = kind.toLowerCase();
  const email = `${label}-${RUN.toLowerCase()}@youdrop.test`;
  const business = `Scenario ${kind} ${RUN}`;
  console.log(`\n--- ${label}: ${business} <${email}> ---`);
  console.log(`    the policy says ${automatic ? 'AUTOMATIC' : 'HUMAN REVIEW'}\n`);

  // 1 & 2. proving the address
  const asked = await call('POST', '/api/onboarding/verifications', {
    body: { channel: 'EMAIL', destination: email },
  });
  asked.ok || asked.code === 202
    ? ok('the website asks for a code', `HTTP ${asked.code}`)
    : bad('verification request', `HTTP ${asked.code} ${asked.text.slice(0, 140)}`);

  // The code is written by the notifications fan-out, which is asynchronous.
  let code = null;
  for (let i = 0; i < 15 && !code; i++) {
    await sleep(2000);
    try { code = codeSentTo(email); } catch { /* the pod may be busy; try again */ }
  }
  code
    ? ok('a code was actually sent', code.replace(/\d/g, '•'))
    : bad('no code reached the inbox', 'the notification never left, so nobody could ever apply');
  if (!code) return;

  const confirmed = await call('POST', '/api/onboarding/verifications/confirm', {
    body: { channel: 'EMAIL', destination: email, code },
  });
  const emailToken = confirmed.json?.token ?? null;
  emailToken
    ? ok('typing it back proves the address')
    : bad('confirming the code', `HTTP ${confirmed.code} ${confirmed.text.slice(0, 140)}`);
  if (!emailToken) return;

  // 3. the application
  const applied = await call('POST', '/api/onboarding/applications', {
    body: {
      kind,
      businessName: business,
      contactName: 'Sam Owner',
      contactEmail: email,
      emailVerificationToken: emailToken,
      notes: 'Submitted by the partner-onboarding scenario.',
      details: kind === 'RIDER'
        ? { vehicle: 'MOTORCYCLE', plate: `SC-${RUN.slice(-4)}`, region: 'Beirut' }
        : { businessType: 'BAKERY', region: 'Beirut' },
    },
  });
  const reference = applied.json?.reference ?? null;
  reference
    ? ok('the application is submitted', `${reference.slice(0, 12)}… ${applied.json.status ?? ''}`)
    : bad('submitting the application', `HTTP ${applied.code} ${applied.text.slice(0, 200)}`);
  if (!reference) return;

  // 4. an account of their own
  const account = await call('POST', `/api/onboarding/applications/${reference}/account`, {
    body: { password: PASSCODE },
  });
  account.ok || account.code === 201
    ? ok('they choose a passcode', `HTTP ${account.code}`)
    : bad('creating the applicant account', `HTTP ${account.code} ${account.text.slice(0, 140)}`);

  // 5. and sign in — where the two paths separate
  const first = await signIn(email, PASSCODE);
  if (!first) {
    bad('the applicant signs in', 'the account cannot authenticate at all');
    return;
  }
  const firstRoles = rolesOf(first);
  ok('the applicant signs in', firstRoles.join(' ') || '(no trading role)');

  const mine = await call('GET', '/api/onboarding/applications/mine', { token: first });
  mine.ok && mine.json?.reference === reference
    ? ok('the app shows them their own application', mine.json.status ?? '')
    : bad('applications/mine', `HTTP ${mine.code} — an applicant cannot see their own application`);

  if (automatic) {
    // The instant path: nobody looked, and they can trade.
    firstRoles.includes(roleWhenTrading)
      ? ok(`auto-approval gave them ${roleWhenTrading} straight away`)
      : bad(`auto-approval did not grant ${roleWhenTrading}`,
        `got ${firstRoles.join(' ') || 'nothing'} — the policy says automatic but the account cannot trade`);
    return;
  }

  // 6. The review path: they wait, and somebody has to see them.
  //
  // APPLICANT is the gate, and its PRESENCE is the whole assertion — not the absence of the
  // trading role. A pending partner is deliberately given their trading role early so they can
  // set themselves up and see every screen; what is withheld is the act that affects somebody
  // else, and the server withholds it by testing for APPLICANT rather than for the role's
  // absence. `POST /api/orders/{id}/claim` is literally
  // `@PreAuthorize("hasRole('DELIVERY') and !hasRole('APPLICANT')")`. So a rider who carries both
  // is correct, and asserting they do not carry DELIVERY would be asserting a bug into place.
  firstRoles.includes('APPLICANT')
    ? ok('they carry APPLICANT, which is what holds them back',
      `${firstRoles.join(' ')} — the trading role is granted early on purpose, and every act that `
      + 'affects somebody else is gated on !APPLICANT')
    : bad('roles before review',
      `expected APPLICANT, got ${firstRoles.join(' ') || 'nothing'} — nobody has reviewed this `
      + 'application, so nothing should be unlocked');
  mine.json?.status === 'SUBMITTED'
    ? ok('and their application still says SUBMITTED', 'nobody has decided')
    : bad('application status before review', `${mine.json?.status} — expected SUBMITTED`);

  const queue = await call('GET', '/api/onboarding/applications?page=0&size=100', { token: backoffice });
  const rows = Array.isArray(queue.json?.content) ? queue.json.content : (queue.json ?? []);
  const waiting = rows.find((a) => a.reference === reference || a.businessName === business);
  waiting
    ? ok('it is waiting in the back office queue', `${waiting.kind} ${waiting.status}`)
    : bad('the application never reached the queue',
      'nobody can approve what nobody can see — this is where an applicant waits forever');
  if (!waiting) return;

  const approved = await call('POST', `/api/onboarding/applications/${waiting.id}/approve`, {
    token: backoffice,
  });
  approved.ok
    ? ok('the operator approves it', `HTTP ${approved.code}`)
    : bad('approving', `HTTP ${approved.code} ${approved.text.slice(0, 200)}`);

  // 7. Keycloak role changes land on the NEXT token, so this is a fresh sign-in, not a refresh.
  //
  // The thing that has to change is APPLICANT going AWAY. That is what unlocks the acts the gate
  // was holding: claiming a job, publishing a product. A run where the trading role is present
  // both before and after proves nothing on its own.
  let unlocked = false;
  let lastRoles = firstRoles;
  for (let i = 0; i < 10 && !unlocked; i++) {
    await sleep(3000);
    const after = await signIn(email, PASSCODE);
    if (!after) continue;
    lastRoles = rolesOf(after);
    if (lastRoles.includes(roleWhenTrading) && !lastRoles.includes('APPLICANT')) unlocked = true;
  }
  unlocked
    ? ok(`they sign in again and they can work as a ${label}`,
      `${lastRoles.join(' ')} — APPLICANT is gone, so the gate is open`)
    : bad('approval never reached the account',
      `approved in the back office, but the token still reads ${lastRoles.join(' ') || 'nothing'}. `
      + 'While APPLICANT remains, every act that matters is still refused with a 403 the app '
      + 'reports as a generic failure.');
}

await applyAs('MERCHANT', 'MERCHANT', policy?.merchant?.automatic ?? false);
await applyAs('RIDER', 'DELIVERY', policy?.rider?.automatic ?? false);

console.log(`\n=== ${pass} passed, ${fail} failed ===\n`);
process.exit(fail ? 1 : 0);
