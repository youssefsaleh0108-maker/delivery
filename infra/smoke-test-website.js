// The public front door: what a stranger gets before they are anybody.
//
//   node infra/smoke-test-website.js
//
// Needs the site up (clients/docker-compose.web.yml) and the gateway on 8100.
//
// Three things are worth checking here and they are not the usual ones. First, the site serves at
// all — it is four static files, so the only way it breaks is a bad mount or a bad nginx config,
// both of which are silent until somebody loads the page. Second, the staff door is reachable by
// address and named nowhere a stranger reads: not in the page, not in the script, and not in
// robots.txt, which is the file people forget is public. Third, the register form actually reaches
// the onboarding service from the browser's origin — a form that 201s from curl and fails CORS in
// a browser looks fine from here and is broken for every applicant.
const { execSync } = require('child_process');

const SITE = 'http://127.0.0.1:5014';
const GW = 'http://127.0.0.1:8100';

const sh = (c) => { try { return execSync(c, { encoding: 'utf8', maxBuffer: 2e7 }); } catch (e) { return e.stdout || ''; } };
const token = (u, p) => {
  const raw = sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
    + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${p ?? u}" -d "grant_type=password" -d "scope=openid"`);
  try { return JSON.parse(raw).access_token; } catch { return null; }
};

const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const fetchPath = (p) => split(sh(`curl -s -w "~~%{http_code}" "${SITE}${p}"`));
const headers = (p) => sh(`curl -s -D - -o NUL "${SITE}${p}"`);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

console.log('--- the site serves ---');
const home = fetchPath('/');
check('the front page loads', home.code === '200', `HTTP ${home.code}`);
check('and it is the site, not an nginx welcome page',
  home.body.includes('Your city, delivered'), 'headline present');
check('the stylesheet is served', fetchPath('/site.css').code === '200', 'site.css');
check('the script is served', fetchPath('/site.js').code === '200', 'site.js');
// try_files ... /index.html: a typed-in path must not 404 into a bare nginx error page.
check('an unknown path falls back to the site',
  fetchPath('/anything-at-all').body.includes('Your city, delivered'), 'index.html');

console.log('\n--- the moving backdrop ---');
const css = fetchPath('/site.css').body;
check('the page has a backdrop behind it', home.body.includes('class="backdrop"'), 'present');
check('it is hidden from screen readers', /class="backdrop" aria-hidden="true"/.test(home.body),
  'aria-hidden');
// Decoration that swallows a click is worse than no decoration. It covers the whole viewport.
check('and cannot swallow a click', /\.backdrop\s*\{[^}]*pointer-events:\s*none/.test(css),
  'pointer-events: none');
check('it sits behind the content', /\.backdrop\s*\{[^}]*z-index:\s*-1/.test(css), 'z-index: -1');

// Somebody who asked their operating system for less motion asked for it here too. For a few people
// this is a vestibular problem, not a preference, and nobody chose to open a landing page.
check('a reduced-motion preference is honoured',
  /@media \(prefers-reduced-motion: reduce\)/.test(css), 'media query present');
check('and it stops the drifting background',
  /prefers-reduced-motion[\s\S]*\.orb[\s\S]*animation:\s*none/.test(css), 'orbs stilled');
check('and the smooth scrolling with it',
  /prefers-reduced-motion[\s\S]*scroll-behavior:\s*auto/.test(css), 'jumps instead of glides');

// Only transform and opacity are animated: both are composited, so the page does not repaint on
// every frame. Animating a blur or a background-position here would cost a phone real battery.
const animatedProps = [...css.matchAll(/@keyframes[^{]*\{([\s\S]*?)\n\}/g)]
  .flatMap((m) => [...m[1].matchAll(/(?:from|to|\d+%)[^{]*\{([^}]*)\}/g)])
  .flatMap((m) => [...m[1].matchAll(/([a-z-]+)\s*:/g)].map((p) => p[1]));
const offending = [...new Set(animatedProps)].filter((p) => p !== 'transform' && p !== 'opacity');
// Asserted first, because "found nothing to object to" and "found nothing at all" are the same
// result from a regex and only one of them means the check did its job.
check('the keyframes are readable by this check', animatedProps.length > 0,
  `${animatedProps.length} declarations across ${(css.match(/@keyframes/g) || []).length} keyframes`);
check('nothing but transform and opacity is animated', offending.length === 0,
  offending.length ? offending.join(', ') : [...new Set(animatedProps)].join(', '));

// The warm top darkens what the hero paragraph sits on, which took --muted from 4.69:1 to 3.91:1 —
// under the 4.5:1 minimum for body text. Guarded because a contrast failure is invisible to anyone
// who is not measuring it: the page looks fine, and it is only unreadable for some of its readers.
const lede = (css.match(/\.lede\s*\{[^}]*\}/) || [''])[0];
check('the hero paragraph is not painted in the colour that fails on it',
  lede.includes('var(--ink-soft)') && !/color:\s*var\(--muted\)/.test(lede),
  'uses --ink-soft (5.8:1)');

console.log('\n--- the two audiences who belong here ---');
// One way in, from the masthead and the hero, both to the same page. The two partner cards that
// used to restate this further down are gone: the form's first question is which of the two you
// are, so the cards were a second place to keep the same choice in step.
check('a business can reach the form from the masthead',
  /<nav>[\s\S]*?href="\/register"[\s\S]*?<\/nav>/.test(home.body), 'in the nav');
check('and from the hero, which is all a phone shows',
  /class="hero-actions"[\s\S]{0,400}href="\/register"/.test(home.body), 'hero button');
check('the old partner cards are gone', !home.body.includes('id="partners"'), 'removed');
// It was a dialog and is now a page. A sheet that closes on a stray click is a poor place to keep
// a half-finished application while somebody goes to find a code in their inbox.
check('applying is a page, not a sheet over the landing page',
  !home.body.includes('id="apply"'), 'the dialog is gone');

console.log('\n--- about and contact ---');
for (const [label, id] of [['About us', 'about'], ['Contact us', 'contact']]) {
  check(`${label} is in the nav`, home.body.includes(`href="#${id}"`), `#${id}`);
  // A nav link to a section that does not exist scrolls nowhere and looks like a broken page.
  check(`and the section it points at exists`, home.body.includes(`id="${id}"`), 'present');
}
check('sign-in offers the merchant portal', home.body.includes('127.0.0.1:5010'), 'port 5010');
check('sign-in offers the carrier portal', home.body.includes('127.0.0.1:5013'), 'port 5013');
// Customers and riders sign themselves up in a minute; a web form would be a longer road to the
// same place. They get the app, and they get the SAME app — one sign-in, two roles.
check('customers and riders are sent to the app instead',
  home.body.includes('127.0.0.1:5012'), 'port 5012');
check('and told it is one app for both',
  /Customers order\. Riders pick up work\./.test(home.body), 'stated on the page');

console.log('\n--- applying, on its own page and in steps ---');
const register = fetchPath('/register');
check('/register is served', register.code === '200', `HTTP ${register.code}`);
check('with the .html hidden, so it can be typed or read aloud',
  register.body.includes('id="apply-heading"'), '/register');
check('the carrier link lands on the same page', fetchPath('/register?kind=CARRIER').code === '200',
  'query preserved');
check('its script is served', fetchPath('/register.js').code === '200', 'register.js');

// Four steps and a receipt. The count is asserted because a step lost to a bad edit would not
// throw — it would silently skip whatever that step was collecting.
const steps = (register.body.match(/class="panel step"/g) || []).length;
check('four steps and a receipt', steps === 5, `${steps} panels`);
for (const [label, marker] of [
  ['email is verified with a code', 'id="email-code"'],
  ['so is a phone number', 'id="phone-code"'],
  ['and the phone step can be skipped', 'id="phone-skip"'],
]) {
  check(label, register.body.includes(marker), 'present');
}
// The one thing on this page that must not quietly become mandatory.
check('the phone step says it is optional',
  /class="optional"/.test(register.body), 'labelled optional');
check('and its field is not marked required',
  !/id="contactPhone"[^>]*\brequired\b/.test(register.body), 'no required attribute');

console.log('\n--- the staff door: reachable by address, advertised nowhere ---');
const admin = fetchPath('/admin');
check('/admin is served', admin.code === '200', `HTTP ${admin.code}`);
check('and it is the administration page', admin.body.includes('Platform administration'), 'served');
check('with a trailing slash too', fetchPath('/admin/').code === '200', '/admin/');
check('it asks search engines to stay away',
  /<meta name="robots" content="noindex/.test(admin.body), 'noindex');
check('and it is the Backoffice behind it', admin.body.includes('127.0.0.1:5011'), 'port 5011');

// The whole point of an unadvertised door. Checked across everything a stranger can read without
// being told where to look: the page, the script, and the stylesheet.
const publicText = home.body + fetchPath('/site.js').body + fetchPath('/site.css').body
    + register.body + fetchPath('/register.js').body;
const mentions = (publicText.match(/admin/gi) || []).length;
check('nothing a visitor can read names it', mentions === 0, `${mentions} mentions`);
check('nor does the page link the Backoffice port',
  !home.body.includes('127.0.0.1:5011'), 'absent from the public page');

// robots.txt is public, always fetched, and the first place a scanner looks. A Disallow line here
// would publish exactly what was kept out of the page — and would stop the crawler ever fetching
// the page whose noindex tag does the real work.
const robots = fetchPath('/robots.txt');
check('robots.txt is served', robots.code === '200', `HTTP ${robots.code}`);
check('and does not name the staff door either',
  !/admin/i.test(robots.body), robots.body.trim().replace(/\s+/g, ' '));

console.log('\n--- the form reaches the platform from a browser ---');
// Not the same question as "does the endpoint work". The site is a different origin from the
// gateway, so the browser asks permission first, and a missing header fails only in a browser.
const preflight = sh(`curl -s -D - -o NUL -X OPTIONS "${GW}/api/onboarding/applications"`
  + ` -H "Origin: ${SITE}" -H "Access-Control-Request-Method: POST"`
  + ' -H "Access-Control-Request-Headers: content-type"');
check('the gateway allows the site origin',
  preflight.toLowerCase().includes(`access-control-allow-origin: ${SITE}`), 'preflight allowed');
check('and allows the method the form uses',
  /access-control-allow-methods:.*POST/i.test(preflight), 'POST');

const tag = Date.now().toString(36).slice(-6);
const email = `website-${tag}@example.test`;

const post = (path, body) => split(sh(`curl -s -X POST -w "~~%{http_code}" "${GW}${path}"`
  + ` -H "Origin: ${SITE}" -H "Content-Type: application/json"`
  + ` -d "${JSON.stringify(body).replace(/"/g, '\\"')}"`));

// An application now needs a proved address, so the suite has to earn one the same way a visitor
// does. The code is read from the delivery log, which is this environment's stand-in for an inbox.
const asked = post('/api/onboarding/verifications', { channel: 'EMAIL', destination: email });
check('the site can ask for a verification code', asked.code === '200', `HTTP ${asked.code}`);

const message = sh('docker exec delivery-postgres psql -U delivery -d delivery -tAc '
  + `"SELECT body FROM notification.notification_log WHERE recipient = '${email}'`
  + ' ORDER BY created_at DESC LIMIT 1"').trim();
const code = (message.match(/\b(\d{6})\b/) || [])[1];
// Asserted before it is used: without this, a missing code turns every check below into a test of
// the string "undefined".
check('the code actually goes out to that address', !!code, code ? 'delivered' : 'NOTHING SENT');

const confirmed = code ? post('/api/onboarding/verifications/confirm',
  { channel: 'EMAIL', destination: email, code }) : { code: 'skipped', body: '{}' };
check('and the right code is accepted', confirmed.code === '200', `HTTP ${confirmed.code}`);
const emailToken = (() => { try { return JSON.parse(confirmed.body).token; } catch { return null; } })();

const application = {
  kind: 'MERCHANT',
  businessName: `Website Smoke ${tag}`,
  contactName: 'Sam Owner',
  contactEmail: email,
  emailVerificationToken: emailToken,
  // Deliberately no phone. This is the path the Skip button takes, and it is the one most likely
  // to be broken by somebody making the field required again.
  notes: 'Submitted by the website smoke test',
};
const submitted = post('/api/onboarding/applications', application);
check('an application with a verified email and no phone is accepted', submitted.code === '201',
  `HTTP ${submitted.code}`);

// The other half of the same rule: unverified contact details cannot get in.
const unverified = post('/api/onboarding/applications',
  { ...application, businessName: `Unverified ${tag}`, emailVerificationToken: 'not-a-real-token' });
check('and one with an unproved address is refused', unverified.code === '422',
  `HTTP ${unverified.code}`);

let reference = null;
if (submitted.code === '201') {
  reference = JSON.parse(submitted.body).reference;
  check('the applicant gets a reference back', (reference || '').length >= 20,
    `${(reference || '').length} chars`);
  // The receipt screen offers "Check its status", and it has no token to check it with.
  const looked = split(sh(`curl -s -w "~~%{http_code}" -H "Origin: ${SITE}"`
    + ` "${GW}/api/onboarding/applications/by-reference/${reference}"`));
  check('and can check on it with no account', looked.code === '200',
    looked.code === '200' ? JSON.parse(looked.body).status : `HTTP ${looked.code}`);
}

// Leave the reviewer queue as it was found. An abandoned smoke-test application sitting in a real
// person's work list is a small mess that grows by one every run.
const backoffice = token('backoffice');
if (reference && backoffice) {
  const queue = JSON.parse(sh(`curl -s -H "Authorization: Bearer ${backoffice}"`
    + ` "${GW}/api/onboarding/applications"`));
  const stale = queue.filter((a) => a.contactEmail === application.contactEmail
    || a.contactEmail === 'cors-probe@example.test');
  for (const a of stale) {
    sh(`curl -s -o NUL -X POST -H "Authorization: Bearer ${backoffice}"`
      + ' -H "Content-Type: application/json"'
      + ' -d "{\\"reason\\":\\"Smoke test application, not a real applicant\\"}"'
      + ` "${GW}/api/onboarding/applications/${a.id}/reject"`);
  }
  const left = JSON.parse(sh(`curl -s -H "Authorization: Bearer ${backoffice}"`
    + ` "${GW}/api/onboarding/applications"`))
    .filter((a) => a.contactEmail === application.contactEmail);
  check('the test application is cleared out of the reviewer queue', left.length === 0,
    `${stale.length} closed`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
