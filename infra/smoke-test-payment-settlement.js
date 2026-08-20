// Payment method through to settlement.
//
// The rule under test: the platform must never pay a merchant out of money nobody collected.
// A cash order is paid at the door and settles; a card order has no provider behind it, so it is
// delivered but unpaid and must NOT produce accounting legs.
//
//   node infra/smoke-test-payment-settlement.js
const { execSync } = require('child_process');
const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });

const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const customer = token('customer');
const merchant = token('merchant');
const rider = token('rider');
const back = token('backoffice');

const call = (m, p, body, tok) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, tok) => JSON.parse(split(call('GET', p, null, tok)).body);
const send = (m, p, body, tok) => split(call(m, p, body, tok));
const pad = (s, n) => String(s).slice(0, n).padEnd(n);
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 50) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 50) + (detail ?? '')); }
};

// The merchant's OWN shop. The seeded demo stores belong to a synthetic 'demo-merchant', so the
// real merchant user cannot accept orders against them — the whole lifecycle has to be drivable
// here, not just the placement.
const store = get('/api/stores/mine', merchant).content
  .find(s => s.availability !== 'CLOSED');
if (!store) {
  console.error('The merchant has no open shop; run smoke-test-store-admin.js first.');
  process.exit(1);
}
const product = get(`/api/stores/${store.id}/products?size=50`, customer).content
  // Skip anything with required options; this suite is about payment, not configuration.
  .find(p => get(`/api/products/${p.id}/options`, customer).every(g => !g.required));
if (!product) { console.error('That store has no optionless products.'); process.exit(1); }

// Enough to clear whatever minimum this shop happens to have. The minimum itself is another
// suite's concern; here it must simply not be the reason an order fails.
const qtyToClearMinimum = Math.max(1, Math.ceil(store.minOrder / product.price));
console.log(`    using ${product.name} x${qtyToClearMinimum} `
  + `to clear a ${store.minOrder} minimum`);


// Dispatch must reach THIS suite's rider, or nothing is ever delivered and every check below fails
// for a reason that has nothing to do with cash.
//
// Since orders are routed to a carrier at READY, a merchant left pinned to a fleet this rider does
// not belong to makes `claim` correctly return 404 and the order stalls on the counter. That is the
// feature working — but it is also state a previous suite can leave behind, so each suite that
// needs a delivery now asserts its own starting conditions rather than inheriting them.
send('PUT', '/api/delivery-providers/policy', { preferredProviderId: null }, merchant);
const riderSub = JSON.parse(Buffer.from(rider.split('.')[1], 'base64url').toString()).sub;
send('DELETE', `/api/delivery-providers/riders/${riderSub}`, null, back);
const TERMINAL_LEG = new Set(['POSTED', 'SETTLED_IN_CASH', 'FAILED', 'ABANDONED']);

/**
 * Places an order and drives it the whole way to DELIVERED.
 *
 * Reports the first step that refused rather than throwing, so a lifecycle that stalls is one
 * readable failure naming the step and its status — not eight later checks failing on an order
 * that never left the counter.
 */
function deliverOrder(paymentMethod) {
  const placed = send('POST', '/api/orders', {
    items: [{ productId: product.id, qty: qtyToClearMinimum }],
    deliveryAddress: '12 Test Street, Flat 4',
    paymentMethod,
  }, customer);
  if (placed.code !== '201') {
    return { error: `place: HTTP ${placed.code} ${placed.body.slice(0, 100)}` };
  }
  const id = JSON.parse(placed.body).id;

  const steps = [
    ['accept', merchant], ['prepare', merchant], ['ready', merchant],
    ['claim', rider], ['pick-up', rider], ['deliver', rider],
  ];
  for (const [step, tok] of steps) {
    const res = send('POST', `/api/orders/${id}/${step}`, null, tok);
    if (res.code !== '200') {
      return { id, error: `${step}: HTTP ${res.code} ${res.body.slice(0, 100)}` };
    }
  }
  return { id, order: get(`/api/orders/${id}`, customer) };
}

function legsFor(orderId) {
  let last = [];
  for (let i = 0; i < 20; i++) {
    const legs = get(`/api/accounting/orders/${orderId}`, back);
    if (Array.isArray(legs) && legs.length > 0) {
      last = legs;
      if (legs.every(l => TERMINAL_LEG.has(l.status))) return legs;
    }
    sleep(1000);
  }
  // Handing back what we last saw rather than nothing: a suite that times out should report which
  // leg was still in flight, not claim settlement produced no legs at all.
  return last;
}

console.log(`--- cash: paid at the door, settles (${store.name}) ---`);
const cash = deliverOrder('CASH');
check('a cash order delivers', !cash.error, cash.error ?? 'ok');
if (!cash.error) {
  check('cash is COLLECTED on delivery', cash.order.paymentStatus === 'COLLECTED',
    cash.order.paymentStatus);
  check('paid_at is set', !!cash.order.paidAt, cash.order.paidAt ? 'set' : 'null');
  const legs = legsFor(cash.id);
  check('settlement produced legs', legs.length >= 2, `${legs.length} legs`);

  // Asserting the legs actually settled, not merely that rows exist. An earlier version of this
  // suite only counted rows, and passed while every debit was FAILING at the bank and abandoning
  // the merchant credit behind it. Existence is not settlement.
  //
  // A cash order has no bank debit at all: the customer handed over notes, so no account moved and
  // the collection is recorded as an obligation against whoever took them. Asserting the absence of
  // a CUSTOMER_DEBIT is the stronger claim, because that leg reappearing would mean the ledger had
  // gone back to describing a transfer that never happened.
  const collection = legs.find(l => l.leg === 'CASH_COLLECTED' || l.leg === 'CUSTOMER_DEBIT');
  check('the collection settled', !!collection && collection.status === 'SETTLED_IN_CASH',
    collection ? `${collection.leg} ${collection.status}` : 'no collection leg');
  check('and no bank account was claimed to have moved',
    !legs.some(l => l.leg === 'CUSTOMER_DEBIT'),
    legs.map(l => l.leg).join(' '));

  const merchantLeg = legs.find(l => l.leg === 'MERCHANT_CREDIT');
  check('the merchant credit actually posted',
    !!merchantLeg && merchantLeg.status === 'POSTED',
    merchantLeg ? `${merchantLeg.amount} ${merchantLeg.status}` : 'missing');

  check('nothing was abandoned',
    legs.every(l => l.status !== 'ABANDONED' && l.status !== 'FAILED'),
    legs.map(l => `${l.leg}=${l.status}`).join(' '));
}

console.log('--- card: no provider, delivered but unpaid, must NOT settle ---');
const card = deliverOrder('CARD');
check('a card order delivers', !card.error, card.error ?? 'ok');
if (!card.error) {
  // Delivery must not silently mark a card order paid — nothing captured it.
  check('card stays AUTHORIZATION_PENDING after delivery',
    card.order.paymentStatus === 'AUTHORIZATION_PENDING', card.order.paymentStatus);
  check('paid_at stays null', !card.order.paidAt, card.order.paidAt ?? 'null');
  sleep(4000);
  const legs = get(`/api/accounting/orders/${card.id}`, back);
  check('NO settlement legs were created', Array.isArray(legs) && legs.length === 0,
    `${Array.isArray(legs) ? legs.length : '?'} legs — a merchant must not be paid from money nobody took`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
