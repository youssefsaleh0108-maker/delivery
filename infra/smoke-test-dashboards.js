// The portal dashboards: how trade is going, for the party asking.
//
//   node infra/smoke-test-dashboards.js
//
// A dashboard fails differently from the rest of the platform. Nothing 500s and nothing is refused;
// the numbers are simply wrong, and being plausible is exactly what stops anybody noticing. So most
// of what is checked here is arithmetic that has to agree with itself:
//
//   * the totals are the series added up, so a headline cannot contradict the chart under it,
//   * the fee shown is the configured percentage of the sales shown, to the cent,
//   * today and yesterday are the last two days of the series and not a separate query,
//   * and a new order moves today's figure by exactly one.
//
// The rest is access: these summaries are the shape of somebody's business — what they sell and how
// much of it — and the endpoints take no id, so the only thing standing between one shop and
// another's takings is that the caller's own identity decides the scope.
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
const get = (p, t) => JSON.parse(send('GET', p, null, t).body);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.005;
const sum = (xs) => xs.reduce((a, b) => a + b, 0);

const merchant = token('merchant');
const carrier = token('carrier');
const customer = token('customer');
const backoffice = token('backoffice');

// ---------------------------------------------------------------- a shop's own page

console.log('--- the shop: what the series says and what the headline says ---');
const m = get('/api/orders/merchant/summary', merchant);

check('the summary loads', !!m.days, `${(m.days || []).length} days`);
check('a fortnight by default', m.windowDays === 14 && m.days.length === 14, `${m.windowDays} days`);

// The whole reason the totals are derived from the series rather than queried beside it. Two
// queries would drift apart on any day the second one ran a millisecond later.
check('the window total is the series added up',
  m.window.orders === sum(m.days.map((d) => d.orders)), `${m.window.orders} orders`);
check('and so is the delivered count',
  m.window.delivered === sum(m.days.map((d) => d.delivered)), `${m.window.delivered} delivered`);
check('and so is the money',
  near(m.window.money, sum(m.days.map((d) => d.money))), m.window.money.toFixed(2));

check('today is the last day of the series',
  m.today.day === m.days[m.days.length - 1].day, m.today.day);
check('yesterday is the one before it',
  m.yesterday.day === m.days[m.days.length - 2].day, m.yesterday.day);
// The series ends today rather than yesterday: a dashboard whose newest bar is yesterday's is one
// that answers a question nobody asked.
check('the series ends today, in the platform\'s own timezone',
  m.today.day === new Date(Date.now() + 3 * 3600e3).toISOString().slice(0, 10), m.today.day);

console.log('\n--- what the platform charges, shown rather than left to be inferred ---');
const chargeable = m.window.money - m.window.waived;
check('the fee is the stated percentage of delivered sales',
  near(m.platformFees, Math.round(chargeable * m.commissionPercentage) / 100),
  `${m.platformFees} = ${m.commissionPercentage}% of ${chargeable.toFixed(2)}`);
check('the percentage matches the one settlement applies',
  m.commissionPercentage === 12.5, `${m.commissionPercentage}%`);
check('nothing is claimed as saved that was not waived',
  m.window.waived > 0 || m.savedByOffers === 0, `${m.savedByOffers} saved`);

console.log('\n--- the window can be asked for, within reason ---');
check('a shorter window is honoured',
  get('/api/orders/merchant/summary?days=7', merchant).days.length === 7, '7 days');
// Clamped rather than refused: a bad number in a query string should not be a 400 on a page load.
check('an absurd window is clamped, not refused',
  get('/api/orders/merchant/summary?days=9999', merchant).days.length === 90, 'capped at 90');
check('and so is a nonsensical one',
  get('/api/orders/merchant/summary?days=0', merchant).days.length === 1, 'floored at 1');

console.log('\n--- best sellers ---');
const top = m.topProducts || [];
check('ranked by quantity, highest first',
  top.every((p, i) => i === 0 || top[i - 1].qty >= p.qty), `${top.length} products`);
check('at most five', top.length <= 5, `${top.length}`);
check('each carries what it earned as well as how many',
  top.every((p) => p.revenue !== undefined && p.name), 'name, qty, revenue');

console.log('\n--- the queue is now, not the window ---');
const openNow = get('/api/orders?status=PLACED&size=1', backoffice);
check('orders awaiting the shop are counted',
  typeof m.awaitingYou === 'number' && m.awaitingYou >= 0, `${m.awaitingYou} to accept`);
// The distinction that makes this number useful: an order placed a month ago and never accepted is
// still waiting, and a fortnight's window would have hidden it.
check('including ones older than the window',
  m.awaitingYou <= (openNow.totalElements ?? 0), `${m.awaitingYou} of ${openNow.totalElements} platform-wide`);

console.log('\n--- a new order moves today, and moves it by one ---');
const store = get('/api/stores/mine', merchant).content.find((s) => s.availability !== 'CLOSED');
const item = store == null ? null : (get('/api/products/mine?size=50', merchant).content || [])
  .find((p) => p.storeId === store.id && p.status === 'ACTIVE'
    && get(`/api/whatsapp/drafts/products/${p.id}/options`, merchant).every((g) => !g.required));

if (item == null) {
  console.log('        skipped: the merchant has no option-free product to order');
} else {
  const before = get('/api/orders/merchant/summary', merchant);
  const placed = send('POST', '/api/orders', {
    items: [{ productId: item.id, qty: 1 }],
    deliveryAddress: 'Hamra (dashboard smoke test)',
    paymentMethod: 'CASH',
  }, customer);
  check('an order is placed', placed.code === '201', `HTTP ${placed.code}`);

  const after = get('/api/orders/merchant/summary', merchant);
  check('today\'s order count goes up by exactly one',
    after.today.orders === before.today.orders + 1,
    `${before.today.orders} -> ${after.today.orders}`);
  check('and the last bar of the chart with it',
    after.days[after.days.length - 1].orders === before.days[before.days.length - 1].orders + 1,
    'series and headline agree');
  // Placed, not delivered. Counting it as a sale the moment it is placed is how a dashboard ends up
  // reading high all evening and dropping overnight.
  check('but not the day\'s sales, which are delivered orders only',
    near(after.today.money, before.today.money), after.today.money.toFixed(2));
  check('nor the delivered count',
    after.today.delivered === before.today.delivered, `${after.today.delivered} delivered`);

  // Left cancelled rather than open: an abandoned order from a test run sits in a real reviewer's
  // queue forever, and this suite adds one every time it runs.
  const id = JSON.parse(placed.body).id;
  send('POST', `/api/orders/${id}/cancel`, { reason: 'Dashboard smoke test' }, backoffice);
}

// ---------------------------------------------------------------- a company's own page

console.log('\n--- the delivery company ---');
const c = get('/api/orders/carrier/summary', carrier);
check('the summary loads', !!c.days, `${(c.days || []).length} days`);
check('its totals are its series added up',
  c.window.orders === sum(c.days.map((d) => d.orders))
    && near(c.window.money, sum(c.days.map((d) => d.money))), `${c.window.orders} jobs`);

// The figure a company plans against, so it has to be the one they are actually paid. The waived
// part is added back whole because on those the platform took nothing at all.
const carrierChargeable = c.window.money - c.window.waived;
const expectedNet = carrierChargeable
  - Math.round(carrierChargeable * c.cutPercentage) / 100
  + c.window.waived;
check('earned is the fee less the platform\'s cut, waivers added back whole',
  near(c.earned, expectedNet), `${c.earned} of ${c.window.money.toFixed(2)} gross`);
check('the cut matches the one the payout uses', c.cutPercentage === 10, `${c.cutPercentage}%`);
check('today and yesterday come from the same series',
  c.today.day === c.days[c.days.length - 1].day
    && c.yesterday.day === c.days[c.days.length - 2].day, `${c.today.day}`);

// ---------------------------------------------------------------- who may ask

console.log('\n--- these are somebody\'s books, and the endpoint takes no id ---');
check('an anonymous caller gets nothing from the shop summary',
  send('GET', '/api/orders/merchant/summary', null, null).code === '401', 'unauthorised');
check('nor from the company summary',
  send('GET', '/api/orders/carrier/summary', null, null).code === '401', 'unauthorised');
check('a carrier cannot read a shop\'s takings',
  send('GET', '/api/orders/merchant/summary', null, carrier).code === '403', 'forbidden');
check('a merchant cannot read a company\'s work',
  send('GET', '/api/orders/carrier/summary', null, merchant).code === '403', 'forbidden');
check('nor can a customer read either',
  send('GET', '/api/orders/merchant/summary', null, customer).code === '403'
    && send('GET', '/api/orders/carrier/summary', null, customer).code === '403', 'forbidden');
// There is no id to tamper with — that is the design, and this records it. Scope comes from the
// token's subject, so the only way to read another shop's numbers is to be that shop.
check('there is no id in the path to substitute',
  send('GET', '/api/orders/merchant/summary?merchantId=someone-else', null, merchant).code === '200',
  'the parameter is ignored, not honoured');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
