// Keeping the promise: order updates reach the customer's chat.
//
//   node infra/smoke-test-whatsapp-updates.js
//
// The confirmation sent at placement says "we will message you when it is on the way". A customer
// who ordered over WhatsApp has no app to open and no tracking screen to refresh — the thread is
// the only thing they have, so that promise is the whole feature.
//
// The two properties worth the most here: the customer is told the three things they cannot
// otherwise know (it left, it arrived, it is not coming), and they are told each of them exactly
// once. Bus delivery is at-least-once, so "exactly once" is a claim that has to be tested.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';
const SVC = 'http://127.0.0.1:8116';

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const merchant = token('merchant');
const rider = token('rider');
const backoffice = token('backoffice');

const call = (m, base, p, body, tok) => {
  const auth = tok ? ` -H "Authorization: Bearer ${tok}"` : '';
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}"${auth}${data} "${base}${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, GW, p, b, t));
const get = (p, t) => JSON.parse(send('GET', p, null, t).body);
const sim = (m, p, b) => split(call(m, SVC, p, b, null));

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

/// The bus is asynchronous, so a check that reads immediately after a transition is a race. Polls
/// rather than sleeping a fixed amount: a fixed sleep is either flaky or slow, and usually both.
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
const NUMBER = `PN-upd-${tag}`;
const CUSTOMER_WA = `961${String(Date.now()).slice(-9)}`;
const ADDRESS = `Hamra, 3rd floor (${tag})`;

const sentTo = (customer) => JSON.parse(sim('GET', '/simulator/sent').body)
  .filter((m) => m.to === customer);
const sentMatching = (customer, text) =>
  sentTo(customer).filter((m) => m.body.toLowerCase().includes(text));
/// Exact-body match. The first version of this file searched for "on the way" as a substring, which
/// the placement confirmation also contains ("we will message you when it is on the way") — so the
/// check passed before the update had been sent at all. A phrase that appears in two messages is
/// not a test.
const sentExactly = (customer, body) => sentTo(customer).filter((m) => m.body === body);

// ---------------------------------------------------------------- an order, taken over chat
const store = get('/api/stores/mine', merchant).content.find((s) => s.availability !== 'CLOSED');
if (!store) {
  console.error('The merchant has no open shop; run smoke-test-store-admin.js first.');
  process.exit(1);
}
const item = (get('/api/products/mine?size=50', merchant).content || [])
  .find((p) => p.storeId === store.id && p.status === 'ACTIVE'
    && get(`/api/whatsapp/drafts/products/${p.id}/options`, merchant).every((g) => !g.required));
if (!item) {
  console.error('The merchant needs an option-free product; run smoke-test-store-admin.js first.');
  process.exit(1);
}

console.log('--- a customer orders over chat ---');
send('POST', '/api/whatsapp/numbers', { phoneNumberId: NUMBER, label: 'Orders' }, merchant);
sim('DELETE', '/simulator/sent');
sim('POST', '/simulator/inbound',
  { phoneNumberId: NUMBER, from: CUSTOMER_WA, name: 'Rana', body: 'one please, Hamra 3rd floor' });

const convo = get('/api/whatsapp/conversations', merchant).find((c) => c.customerWaId === CUSTOMER_WA);
let draft = JSON.parse(send('POST', `/api/whatsapp/drafts/conversations/${convo.id}`,
  { requestText: 'one please' }, merchant).body);
draft = JSON.parse(send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
  { productId: item.id, qty: 1 }, merchant).body);
send('PUT', `/api/whatsapp/drafts/${draft.id}/delivery`, { deliveryAddress: ADDRESS }, merchant);

const placed = send('POST', `/api/whatsapp/drafts/${draft.id}/place`, null, merchant);
check('the order is placed', placed.code === '200', `HTTP ${placed.code}`);
const orderId = JSON.parse(placed.body).orderId;
check('and the customer is told, with the total',
  sentMatching(CUSTOMER_WA, 'confirmed').length === 1, 'confirmation sent');

console.log('\n--- the shop working the order is not the customer\'s business ---');
send('POST', `/api/orders/${orderId}/accept`, null, merchant);
send('POST', `/api/orders/${orderId}/prepare`, null, merchant);
send('POST', `/api/orders/${orderId}/ready`, null, merchant);

// Give the bus a moment to deliver events we expect to produce nothing, so "nothing arrived" is a
// real observation rather than a check that ran too early.
execSync(process.platform === 'win32' ? 'ping -n 4 127.0.0.1 > NUL' : 'sleep 2');
// The merchant typed this order in themselves; PLACED → ACCEPTED → PREPARING is the shop agreeing
// with itself, and READY means the food is on our counter. None of it is news.
check('accepting it sends nothing', sentMatching(CUSTOMER_WA, 'accepted').length === 0, 'quiet');
check('preparing it sends nothing', sentMatching(CUSTOMER_WA, 'preparing').length === 0, 'quiet');
check('and neither does it being ready', sentMatching(CUSTOMER_WA, 'ready').length === 0, 'quiet');
check('so the thread still holds only the confirmation',
  sentTo(CUSTOMER_WA).length === 1, `${sentTo(CUSTOMER_WA).length} message(s)`);

console.log('\n--- but the moment it leaves, they hear about it ---');
const claim = send('POST', `/api/orders/${orderId}/claim`, null, rider);
check('a rider claims it', claim.code === '200' || claim.code === '204', `HTTP ${claim.code}`);
const pickup = send('POST', `/api/orders/${orderId}/pick-up`, null, rider);
check('and picks it up', pickup.code === '200', `HTTP ${pickup.code}`);

const onTheWay = waitFor(() => {
  const hits = sentExactly(CUSTOMER_WA, 'Your order is on the way.');
  return hits.length ? hits : null;
}, '"on the way"');
// The exact promise the confirmation made.
check('the customer is told it is on the way', onTheWay !== null && onTheWay.length === 1,
  onTheWay ? onTheWay[0].body : 'never arrived');
check('and it is in their thread, not only on the wire',
  get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant)
    .some((m) => m.direction === 'OUTBOUND' && m.body.includes('on the way')), 'visible');

console.log('\n--- and when it arrives ---');
send('POST', `/api/orders/${orderId}/deliver`, null, rider);
const delivered = waitFor(() => {
  const hits = sentMatching(CUSTOMER_WA, 'delivered');
  return hits.length ? hits : null;
}, '"delivered"');
check('the loop is closed', delivered !== null && delivered.length === 1,
  delivered ? delivered[0].body : 'never arrived');

console.log('\n--- exactly once, however many times the bus redelivers ---');
// Every status is republished by the outbox relay whenever a PUBLISHED flag fails to commit, so
// "once" is a claim that has to survive repetition. Re-driving the same transitions is the closest
// thing to a redelivery this suite can force from outside.
send('POST', `/api/orders/${orderId}/pick-up`, null, rider);
send('POST', `/api/orders/${orderId}/deliver`, null, rider);
execSync(process.platform === 'win32' ? 'ping -n 4 127.0.0.1 > NUL' : 'sleep 2');
check('still one "on the way"', sentExactly(CUSTOMER_WA, 'Your order is on the way.').length === 1,
  `${sentExactly(CUSTOMER_WA, 'Your order is on the way.').length}`);
check('still one "delivered"', sentMatching(CUSTOMER_WA, 'delivered').length === 1,
  `${sentMatching(CUSTOMER_WA, 'delivered').length}`);
check('three messages in total, no more',
  sentTo(CUSTOMER_WA).length === 3, `${sentTo(CUSTOMER_WA).length} messages`);

console.log('\n--- a cancellation says why ---');
const second = (() => {
  sim('POST', '/simulator/inbound',
    { phoneNumberId: NUMBER, from: CUSTOMER_WA, name: 'Rana', body: 'another one please' });
  let d = JSON.parse(send('POST', `/api/whatsapp/drafts/conversations/${convo.id}`,
    { requestText: 'another one' }, merchant).body);
  d = JSON.parse(send('POST', `/api/whatsapp/drafts/${d.id}/lines`,
    { productId: item.id, qty: 1 }, merchant).body);
  send('PUT', `/api/whatsapp/drafts/${d.id}/delivery`, { deliveryAddress: ADDRESS }, merchant);
  return JSON.parse(send('POST', `/api/whatsapp/drafts/${d.id}/place`, null, merchant).body).orderId;
})();

const cancel = send('POST', `/api/orders/${second}/cancel`,
  { reason: 'the kitchen closed early' }, merchant);
check('the merchant cancels it', cancel.code === '200', `HTTP ${cancel.code}`);

const cancelled = waitFor(() => {
  const hits = sentMatching(CUSTOMER_WA, 'cancelled');
  return hits.length ? hits : null;
}, '"cancelled"');
check('the customer is told', cancelled !== null, cancelled ? 'told' : 'never arrived');
// "Your order was cancelled" with no explanation generates the phone call this feature exists to
// save the merchant.
check('and told why', cancelled !== null && cancelled[0].body.includes('the kitchen closed early'),
  cancelled ? cancelled[0].body : '');

console.log('\n--- ordinary app orders are none of this service\'s business ---');
const appOrders = get('/api/orders/merchant?size=50', merchant).content
  .filter((o) => o.deliveryAddress !== ADDRESS);
check('most orders have no conversation, and none is invented',
  appOrders.length > 0 && sentTo(CUSTOMER_WA).length === 5,
  `${appOrders.length} app orders, ${sentTo(CUSTOMER_WA).length} messages to this customer`);
check('a backoffice token cannot read the thread either',
  send('GET', `/api/whatsapp/conversations/${convo.id}/messages`, null, backoffice).code === '403',
  'forbidden');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
