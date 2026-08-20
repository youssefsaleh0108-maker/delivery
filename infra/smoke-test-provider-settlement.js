// Paying whoever actually carried the order.
//
//   node infra/smoke-test-provider-settlement.js
//
// The delivery fee used to go entirely to the platform, which was right while the platform was the
// only delivery arm there was. Once a merchant can pick a carrier, the fee is what delivery COSTS —
// and only the take rate on it was ever platform revenue.
//
// The property that makes this safe: an order the in-house fleet carried must settle exactly as it
// did before any of this existed. That is checked here against a real order, not asserted.
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const customer = token('customer');
const merchant = token('merchant');
const rider = token('rider');
const back = token('backoffice');
const riderSub = JSON.parse(Buffer.from(rider.split('.')[1], 'base64url').toString()).sub;

const call = (m, p, body, tok = back) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, p, b, t));
const get = (p, t) => JSON.parse(split(call('GET', p, null, t)).body);
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 54) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 54) + (detail ?? '')); }
};

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
const amountOf = (legs, leg) => {
  const found = legs.find(l => l.leg === leg);
  return found ? Number(found.amount) : null;
};

const store = get('/api/stores/mine', merchant).content.find(s => s.availability !== 'CLOSED');
const product = get(`/api/stores/${store.id}/products?size=50`).content
  .find(p => get(`/api/products/${p.id}/options`).every(g => !g.required));
const qty = Math.max(1, Math.ceil(store.minOrder / product.price));

function placeAndDeliver() {
  const placed = send('POST', '/api/orders', {
    items: [{ productId: product.id, qty }],
    deliveryAddress: '12 Test Street, Flat 4', paymentMethod: 'CASH',
  }, customer);
  const id = JSON.parse(placed.body).id;
  for (const step of ['accept', 'prepare', 'ready']) send('POST', `/api/orders/${id}/${step}`, null, merchant);
  for (const step of ['claim', 'pick-up', 'deliver']) send('POST', `/api/orders/${id}/${step}`, null, rider);
  return get(`/api/orders/${id}`, customer);
}

console.log('--- carried by the in-house fleet: nothing changes ---');
const inHouseOrder = placeAndDeliver();
const inHouseLegs = settledLegs(inHouseOrder.id);
for (const l of inHouseLegs) console.log(`      ${l.leg} ${l.amount} ${l.status}`);
check('no carrier is paid, because the platform carried it',
  !inHouseLegs.some(l => l.leg === 'PROVIDER_CREDIT'));
check('the whole delivery fee stays with the platform',
  amountOf(inHouseLegs, 'MERCHANT_CREDIT') + amountOf(inHouseLegs, 'PLATFORM_COMMISSION')
    === amountOf(inHouseLegs, 'CASH_COLLECTED'));
const inHouseMerchant = amountOf(inHouseLegs, 'MERCHANT_CREDIT');
const inHousePlatform = amountOf(inHouseLegs, 'PLATFORM_COMMISSION');

console.log('\n--- the rider moves to a delivery company ---');
const slug = `carrier-${Date.now().toString(36).slice(-6)}`;
const company = JSON.parse(send('POST', '/api/delivery-providers', {
  slug, name: 'Test Carrier', accountRef: 'ACC-CARRIER',
}).body);
check('a company is registered with a payout account', company.accountRef === 'ACC-CARRIER');
check('the rider joins it',
  send('POST', `/api/delivery-providers/${company.id}/riders`, { riderRef: riderSub }).code === '204');
// Moving the rider is not enough on its own: dispatch decides who is ASKED, and it asks whoever
// the merchant chose. Without this the order goes to the in-house fleet and this rider — now
// working for somebody else — cannot claim it at all.
check('and the merchant chooses that carrier',
  send('PUT', '/api/delivery-providers/policy',
    { preferredProviderId: company.id, allowFallback: true }, merchant).code === '200');

console.log('\n--- carried by that company ---');
const carriedOrder = placeAndDeliver();
check('the order records who carried it',
  carriedOrder.deliveryProviderId === company.id,
  `${carriedOrder.deliveryProviderId?.slice(0, 8)} vs ${company.id.slice(0, 8)}`);
const carriedLegs = settledLegs(carriedOrder.id);
for (const l of carriedLegs) console.log(`      ${l.leg} ${l.amount} ${l.status}`);

check('the carrier is paid', amountOf(carriedLegs, 'PROVIDER_CREDIT') > 0,
  `${amountOf(carriedLegs, 'PROVIDER_CREDIT')}`);
check('and paid at the bank, not merely recorded',
  carriedLegs.find(l => l.leg === 'PROVIDER_CREDIT')?.status === 'POSTED',
  carriedLegs.find(l => l.leg === 'PROVIDER_CREDIT')?.status);
// The merchant must not care who carried it.
check('the merchant is paid exactly the same as before',
  amountOf(carriedLegs, 'MERCHANT_CREDIT') === inHouseMerchant,
  `${amountOf(carriedLegs, 'MERCHANT_CREDIT')} vs ${inHouseMerchant}`);
// The platform gives up the fee but keeps its take rate on it.
check('the platform earns less, because it did not do the delivery',
  amountOf(carriedLegs, 'PLATFORM_COMMISSION') < inHousePlatform,
  `${amountOf(carriedLegs, 'PLATFORM_COMMISSION')} vs ${inHousePlatform}`);
check('but still earns a take rate on the delivery',
  amountOf(carriedLegs, 'PLATFORM_COMMISSION') > inHouseMerchant * 0
    && amountOf(carriedLegs, 'PROVIDER_CREDIT') < Number(carriedOrder.deliveryFee),
  `fee ${carriedOrder.deliveryFee}, carrier got ${amountOf(carriedLegs, 'PROVIDER_CREDIT')}`);
check('the legs still sum to exactly what the customer paid',
  carriedLegs.filter(l => l.direction === 'CREDIT').reduce((s, l) => s + Number(l.amount), 0)
    === amountOf(carriedLegs, 'CASH_COLLECTED'));
check('every leg settled', carriedLegs.every(l => TERMINAL.has(l.status) && l.status !== 'FAILED'),
  carriedLegs.map(l => `${l.leg}=${l.status}`).join(' '));

console.log('\n--- put the rider back ---');
check('the merchant hands dispatch back to the platform',
  send('PUT', '/api/delivery-providers/policy', { preferredProviderId: null }, merchant).code === '200');
check('the rider returns to the in-house fleet',
  send('DELETE', `/api/delivery-providers/riders/${riderSub}`, null).code === '204');
const backInHouse = placeAndDeliver();
check('and orders settle as they did at the start',
  !settledLegs(backInHouse.id).some(l => l.leg === 'PROVIDER_CREDIT'));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
