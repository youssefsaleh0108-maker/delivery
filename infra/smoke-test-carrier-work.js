// A delivery company's own work, and what it is owed.
//
//   node infra/smoke-test-carrier-work.js
//
// The carrier portal could show a company its score, its fleet and its payout account — everything
// except the two things it opens an app to find out: what are we carrying, and what will we be
// paid. This covers both, plus the boundary that matters most on a marketplace of competing
// carriers: a company sees its own jobs and nobody else's.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const carrier = token('carrier');
const backoffice = token('backoffice');
const merchant = token('merchant');
const rider = token('rider');
const customer = token('customer');

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
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.02;

const tag = Date.now().toString(36).slice(-5);
const subOf = (jwt) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64').toString('utf8')).sub;
const carrierSub = subOf(carrier);
const riderSub = subOf(rider);

// ---------------------------------------------------------------- set the company up
//
// Own setup rather than inheriting it, and the account is put back at the end. The seeded stack
// attaches this carrier to a demo company so the app is usable the moment somebody opens it; a
// suite that left it detached would silently break that for every later reader.
const originalCompany = (() => {
  const r = send('GET', '/api/delivery-providers/my-company', null, carrier);
  return r.code === '200' ? JSON.parse(r.body).id : null;
})();

console.log('--- a company, with this carrier running it ---');
const registered = send('POST', '/api/delivery-providers', {
  slug: `work-${tag}`, name: `Work Couriers ${tag}`,
  contactName: 'Cara', contactPhone: '+9611000333', accountRef: 'ACC-CARRIER',
}, backoffice);
check('the platform registers it', registered.code === '201', `HTTP ${registered.code}`);
const company = JSON.parse(registered.body);
check('and attaches the carrier to it',
  send('POST', `/api/delivery-providers/${company.id}/staff`,
    { riderRef: carrierSub }, backoffice).code === '204', 'attached');
// A rider is attached through /riders, not /staff. They are two different memberships: staff are
// the people who RUN the company and get the portal; riders are who CARRIES for it, and only that
// second one is what dispatch and claim consult. Attaching to the wrong one produced a 204 and an
// order the rider then could not see.
check('and a rider who can actually carry it',
  send('POST', `/api/delivery-providers/${company.id}/riders`,
    { riderRef: riderSub }, backoffice).code === '204', 'crewed');

// Pinned so this run's orders land with this run's company rather than wherever the Delivery Score
// would have sent them. Without it the job list would be empty and the money checks vacuous.
const previousPolicy = get('/api/delivery-providers/policy', merchant);
check('the merchant pins their deliveries to it',
  send('PUT', '/api/delivery-providers/policy',
    { preferredProviderId: company.id, allowFallback: false }, merchant).code === '200', 'pinned');

// ---------------------------------------------------------------- give them work
const store = get('/api/stores/mine', merchant).content.find((s) => s.availability !== 'CLOSED');
const item = (get('/api/products/mine?size=50', merchant).content || [])
  .find((p) => p.storeId === store.id && p.status === 'ACTIVE'
    && get(`/api/whatsapp/drafts/products/${p.id}/options`, merchant).every((g) => !g.required));

const drive = (toDelivered) => {
  const placed = send('POST', '/api/orders', {
    items: [{ productId: item.id, qty: 1 }],
    deliveryAddress: `Hamra carrier ${tag}`,
    paymentMethod: 'CASH',
  }, customer);
  if (placed.code !== '201') return null;
  const order = JSON.parse(placed.body);
  send('POST', `/api/orders/${order.id}/accept`, null, merchant);
  send('POST', `/api/orders/${order.id}/prepare`, null, merchant);
  // READY is where dispatch chooses a carrier, so this is the step that makes it their job.
  send('POST', `/api/orders/${order.id}/ready`, null, merchant);
  if (toDelivered) {
    send('POST', `/api/orders/${order.id}/claim`, null, rider);
    send('POST', `/api/orders/${order.id}/pick-up`, null, rider);
    send('POST', `/api/orders/${order.id}/deliver`, null, rider);
  }
  return get(`/api/orders/${order.id}`, merchant);
};

const finished = drive(true);
const inProgress = drive(false);
check('an order is delivered by them',
  finished !== null && finished.deliveryProviderId === company.id
    && finished.status === 'DELIVERED',
  finished ? finished.status : 'not placed');
check('and another is still in flight',
  inProgress !== null && inProgress.deliveryProviderId === company.id,
  inProgress ? inProgress.status : 'not placed');

console.log('\n--- only a delivery company can see a delivery company\'s work ---');
check('a merchant cannot read the carrier job list',
  send('GET', '/api/orders/carrier', null, merchant).code === '403', 'forbidden');
check('nor can a customer',
  send('GET', '/api/orders/carrier', null, customer).code === '403', 'forbidden');
check('nor can a rider, who works for one but does not run it',
  send('GET', '/api/orders/carrier', null, rider).code === '403', 'forbidden');
check('nor can the backoffice use the carrier-scoped view',
  send('GET', '/api/orders/carrier/earnings', null, backoffice).code === '403', 'forbidden');
check('an anonymous caller gets nothing',
  send('GET', '/api/orders/carrier', null, null).code === '401', 'unauthorised');

console.log('\n--- the company sees its own jobs ---');
const jobsRes = send('GET', '/api/orders/carrier?size=100', null, carrier);
check('a carrier can read their job list', jobsRes.code === '200', `HTTP ${jobsRes.code}`);
const jobs = JSON.parse(jobsRes.body);

// The whole point of scoping it: on a marketplace of competing carriers, one company reading
// another's job list would be reading their customer base.
const myCompany = get('/api/delivery-providers/my-company', carrier);
check('and every job on it belongs to their own company',
  jobs.content.every((o) => o.deliveryProviderId === myCompany.id),
  `${jobs.content.length} job(s), company ${myCompany.name}`);

check('each job carries what the delivery is worth',
  jobs.content.length === 0 || jobs.content.every((o) => typeof o.deliveryFee === 'number'),
  'priced');
check('and the address the rider has to reach',
  jobs.content.length === 0 || jobs.content.every((o) => (o.deliveryAddress || '').length > 0),
  'addressed');

console.log('\n--- earnings separate what is owed from what is only expected ---');
const earnings = get('/api/orders/carrier/earnings', carrier);
check('the summary loads', typeof earnings.earned === 'number', `${earnings.earned} earned`);
check('delivered and in-flight are counted apart',
  typeof earnings.delivered === 'number' && typeof earnings.active === 'number',
  `${earnings.delivered} delivered, ${earnings.active} in flight`);
// Adding them into one headline would flatter the number and mislead somebody deciding whether
// they can afford another van.
check('and so are earned and expected',
  typeof earnings.expected === 'number' && earnings.earned !== undefined,
  `${earnings.earned} vs ${earnings.expected}`);
check('the platform\'s share is stated, not implied',
  earnings.cutPercentage > 0, `${earnings.cutPercentage}%`);
check('over a window the company can see', earnings.windowDays > 0, `${earnings.windowDays} days`);
check('nothing is negative', earnings.earned >= 0 && earnings.expected >= 0
  && earnings.savedByOffers >= 0, 'sane');

console.log('\n--- the numbers agree with the jobs behind them ---');
const delivered = jobs.content.filter((o) => o.status === 'DELIVERED');
const inFlight = jobs.content.filter((o) => !['DELIVERED', 'CANCELLED'].includes(o.status));
// The page defaults to 100 above, so this only holds while the company has fewer than that in the
// window. Stated rather than assumed, so a future failure reads as "it grew" not "it broke".
if (jobs.totalElements <= 100) {
  check('the delivered count matches the list',
    earnings.delivered === delivered.length,
    `${earnings.delivered} vs ${delivered.length}`);
  check('the in-flight count matches the list',
    earnings.active === inFlight.length, `${earnings.active} vs ${inFlight.length}`);

  // Gross fees less the platform's cut, with waived orders keeping the whole fee.
  const expectedNet = delivered.reduce((sum, o) => sum + (o.carrierFeeWaived
    ? Number(o.deliveryFee)
    : Number(o.deliveryFee) * (1 - earnings.cutPercentage / 100)), 0);
  check('and the earnings are the fees less the platform\'s share',
    near(earnings.earned, expectedNet), `${earnings.earned} vs ${expectedNet.toFixed(2)}`);
} else {
  console.log(`  SKIP  ${jobs.totalElements} jobs is past the page size; totals not cross-checked`);
}

console.log('\n--- a waived platform cut is visible to the company that received it ---');
const waivedJobs = jobs.content.filter((o) => o.carrierFeeWaived);
check('the order says so, rather than only the platform knowing',
  waivedJobs.every((o) => o.carrierFeeWaived === true), `${waivedJobs.length} waived`);
if (waivedJobs.length > 0) {
  // A discount nobody is told about changes nothing about who a carrier works for.
  check('and the summary reports what it saved them',
    earnings.savedByOffers > 0, `${earnings.savedByOffers}`);
} else {
  check('and the summary reports nothing saved, because nothing was',
    earnings.savedByOffers === 0, '0');
}

// ---------------------------------------------------------------- put it back
//
// The pinned policy and the company membership are this run's, not the platform's. Left behind they
// would send every later order to a company that exists only because a test created it — which is
// how the next suite along ends up failing for a reason nobody can find.
send('PUT', '/api/delivery-providers/policy', {
  preferredProviderId: previousPolicy.preferredProviderId,
  allowFallback: previousPolicy.allowFallback ?? true,
}, merchant);
// The in-flight order is cancelled rather than abandoned. Left READY and unclaimed it sits at the
// front of the rider job board forever — that board is ordered oldest-first, so one leaked order
// per run eventually pushes every real one off the first page. That is precisely how this run broke
// smoke-test-dispatch.js, which looks for a just-created order among the first fifty.
if (inProgress !== null) {
  send('POST', `/api/orders/${inProgress.id}/cancel`,
    { reason: 'smoke test cleanup' }, merchant);
}
send('DELETE', `/api/delivery-providers/staff/${carrierSub}`, null, backoffice);
send('DELETE', `/api/delivery-providers/riders/${riderSub}`, null, backoffice);
check('the carrier is detached again',
  send('GET', '/api/delivery-providers/my-company', null, carrier).code === '404', 'clean');

// And put back where it was found.
if (originalCompany !== null) {
  send('POST', `/api/delivery-providers/${originalCompany}/staff`,
    { riderRef: carrierSub }, backoffice);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
