// Cash is money somebody is holding, not money a bank moved.
//
//   node infra/smoke-test-cash-float.js
//
// The bug this covers: a cash order used to debit the CUSTOMER's bank account, which never
// happened — they handed notes to a rider. The first fix swapped the debit onto the rider and every
// posting failed for want of funds, abandoning the merchant leg and paying nobody. So the two
// checks that matter here are that the customer's account is NOT touched, and that the merchant is
// still paid anyway.
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const customer = token('customer');
const merchant = token('merchant');
const rider = token('rider');
const back = token('backoffice');

const call = (m, p, body, tok = customer) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, tok) => JSON.parse(split(call('GET', p, null, tok)).body);
const send = (m, p, b, t) => split(call(m, p, b, t));

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 54).padEnd(54) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 54).padEnd(54) + (detail ?? '')); }
};


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
const TERMINAL = new Set(['POSTED', 'SETTLED_IN_CASH', 'FAILED', 'ABANDONED']);
function settledLegs(orderId) {
  let last = [];
  for (let i = 0; i < 25; i++) {
    const legs = get(`/api/accounting/orders/${orderId}`, back);
    if (Array.isArray(legs) && legs.length > 0) {
      last = legs;
      if (legs.every(l => TERMINAL.has(l.status))) return legs;
    }
    sleep(1000);
  }
  return last;
}
const legOf = (legs, name) => legs.find(l => l.leg === name);

// The merchant's OWN shop: the seeded demo stores belong to a synthetic merchant, so the real
// merchant user cannot accept orders against them and the lifecycle would stall at ACCEPTED.
const store = get('/api/stores/mine', merchant).content.find(s => s.availability !== 'CLOSED');
if (!store) {
  console.error('The merchant has no open shop; run smoke-test-store-admin.js first.');
  process.exit(1);
}
const product = get(`/api/stores/${store.id}/products?size=50`).content
  // Anything with a required option cannot be ordered by product id alone, and configuration is
  // another suite's subject.
  .find(p => get(`/api/products/${p.id}/options`).every(g => !g.required));
if (!product) { console.error('That store has no optionless products.'); process.exit(1); }

const qty = Math.max(1, Math.ceil(store.minOrder / product.price));

/** Places an order and drives it all the way to DELIVERED. */
function placeAndDeliver(paymentMethod) {
  const placed = send('POST', '/api/orders', {
    items: [{ productId: product.id, qty }],
    deliveryAddress: '12 Test Street, Flat 4',
    paymentMethod,
  });
  if (placed.code !== '201') {
    console.error(`could not place a ${paymentMethod} order: HTTP ${placed.code} ${placed.body.slice(0, 120)}`);
    process.exit(1);
  }
  const id = JSON.parse(placed.body).id;
  for (const step of ['accept', 'prepare', 'ready']) {
    send('POST', `/api/orders/${id}/${step}`, null, merchant);
  }
  for (const step of ['claim', 'pick-up', 'deliver']) {
    send('POST', `/api/orders/${id}/${step}`, null, rider);
  }
  return get(`/api/orders/${id}`);
}

console.log('--- a cash order ---');
const cash = placeAndDeliver('CASH');
console.log(`order ${cash.id}: total ${cash.totalAmount}`);
const cashLegs = settledLegs(cash.id);
for (const l of cashLegs) console.log(`      ${l.leg} ${l.amount} ${l.status}`);

check('the customer bank account is never debited',
  !legOf(cashLegs, 'CUSTOMER_DEBIT'), 'no CUSTOMER_DEBIT leg');
check('the collection is recorded as cash instead',
  legOf(cashLegs, 'CASH_COLLECTED')?.amount === cash.totalAmount,
  `${legOf(cashLegs, 'CASH_COLLECTED')?.amount}`);
check('and marked settled in cash, not posted',
  legOf(cashLegs, 'CASH_COLLECTED')?.status === 'SETTLED_IN_CASH',
  legOf(cashLegs, 'CASH_COLLECTED')?.status);
// The regression that matters: the previous attempt broke exactly this.
check('the merchant is still paid',
  legOf(cashLegs, 'MERCHANT_CREDIT')?.status === 'POSTED',
  `${legOf(cashLegs, 'MERCHANT_CREDIT')?.amount} ${legOf(cashLegs, 'MERCHANT_CREDIT')?.status}`);
check('and the platform still takes its commission',
  legOf(cashLegs, 'PLATFORM_COMMISSION')?.status === 'POSTED',
  `${legOf(cashLegs, 'PLATFORM_COMMISSION')?.amount}`);
check('the legs sum to what the customer handed over',
  cashLegs.filter(l => l.direction === 'CREDIT').reduce((s, l) => s + Number(l.amount), 0)
    === Number(legOf(cashLegs, 'CASH_COLLECTED')?.amount));

console.log('\n--- the rider now owes the platform ---');
const float = get('/api/accounting/float', back);
const riderRow = float.find(f => f.orders > 0 && Number(f.amount) > 0);
check('somebody shows as holding cash', !!riderRow, riderRow ? `${riderRow.amount} over ${riderRow.orders} orders` : 'none');
check('and it is a rider holding it', riderRow?.holderKind === 'RIDER', riderRow?.holderKind);

console.log('\n--- a card order is unaffected ---');
const card = placeAndDeliver('CARD');
// A card order is delivered but unpaid: no provider is integrated, so it stays authorisation
// pending and must NOT settle. That gate predates this change and must still hold.
sleep(3000);
const cardLegs = get(`/api/accounting/orders/${card.id}`, back);
check('an uncaptured card order still does not settle',
  Array.isArray(cardLegs) && cardLegs.length === 0, `${cardLegs.length} legs`);
check('and creates no float, because nobody is holding notes',
  get('/api/accounting/float', back).every(f => !f.orderIds || !f.orderIds.includes(card.id)));

console.log('\n--- banking the takings ---');
// The other half of the float: until this existed the balance only ever grew.
const holderBefore = get('/api/accounting/float', back).find(f => Number(f.amount) > 0);
check('somebody is carrying cash to bank', !!holderBefore,
  holderBefore ? `${holderBefore.holderRef.slice(0, 8)} holds ${holderBefore.amount}` : 'none');

const remitted = send('POST', `/api/accounting/float/${holderBefore.holderRef}/remit`, null, back);
check('the remittance is recorded', remitted.code === '200', `HTTP ${remitted.code}`);
const receipt = JSON.parse(remitted.body);
check('for exactly what they were holding',
  Number(receipt.amount) === Number(holderBefore.amount),
  `${receipt.amount} vs ${holderBefore.amount}`);
check('covering every collection', receipt.collections === holderBefore.orders,
  `${receipt.collections} of ${holderBefore.orders}`);

// The expensive failure this guards: they hand over the money and still show as owing it.
const after = get('/api/accounting/float', back).find(f => f.holderRef === holderBefore.holderRef);
check('and they now owe nothing', !after, after ? `still ${after.amount}` : 'clear');

// Unlike a collection, banking the takings really does move money.
sleep(2000);
const legs = get(`/api/accounting/orders/${receipt.remittanceId}`, back);
const remitLeg = Array.isArray(legs) ? legs.find(l => l.leg === 'CASH_REMITTANCE') : null;
check('it posted at the bank as a real movement',
  remitLeg && ['POSTED', 'PENDING'].includes(remitLeg.status),
  remitLeg ? `${remitLeg.amount} ${remitLeg.status}` : 'no leg');
check('crediting the platform, not the rider',
  remitLeg && remitLeg.accountRef !== holderBefore.holderRef, remitLeg?.accountRef);

check('remitting again is harmless',
  JSON.parse(send('POST', `/api/accounting/float/${holderBefore.holderRef}/remit`, null, back).body)
    .collections === 0, 'nothing left to bank');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
