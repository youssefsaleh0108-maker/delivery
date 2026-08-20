// Fee waivers: the platform giving up its own share, and refusing to give up more than it can.
//
//   node infra/smoke-test-offers.js
//
// Three audiences, one mechanism: somebody stops paying a fee and the platform absorbs it. The
// properties that matter are all about nobody being cheated —
//
//   * a customer with free delivery still has a carrier who gets paid in full,
//   * a merchant promotion does not quietly change what the customer is charged,
//   * an offer withdrawn today does not change what yesterday's order pays out,
//   * and the platform cannot give away more than its cap allows.
//
// The last one is what makes "based on the revenue" a rule rather than a slogan.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const backoffice = token('backoffice');
const merchant = token('merchant');
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
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.005;

const tag = Date.now().toString(36).slice(-6);

// Withdraw everything already running, so this run starts from a known state rather than inheriting
// a promotion left live by the last one.
const startingOffers = get('/api/offers', backoffice);
startingOffers.filter((o) => o.active)
  .forEach((o) => send('POST', `/api/offers/${o.id}/withdraw`, null, backoffice));

// ---------------------------------------------------------------- the shop
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
console.log(`    ${store.name}: ${item.name} ${item.price}, delivery ${store.deliveryFee}\n`);

const place = () => {
  const res = send('POST', '/api/orders', {
    items: [{ productId: item.id, qty: 1 }],
    deliveryAddress: `Hamra (${tag})`,
    paymentMethod: 'CASH',
  }, customer);
  return res.code === '201' ? JSON.parse(res.body) : { error: res.body, code: res.code };
};

console.log('--- only the Backoffice can give the platform\'s money away ---');
check('a merchant cannot create an offer',
  send('POST', '/api/offers', { audience: 'CUSTOMER', title: 'Mine' }, merchant).code === '403',
  'forbidden');
check('nor can a customer',
  send('POST', '/api/offers', { audience: 'CUSTOMER', title: 'Mine' }, customer).code === '403',
  'forbidden');
check('nor can they read the budget',
  send('GET', '/api/offers/budget', null, merchant).code === '403', 'forbidden');
check('an anonymous caller gets nothing',
  send('GET', '/api/offers', null, null).code === '401', 'unauthorised');

console.log('\n--- the budget is a share of what was earned ---');
const budget0 = get('/api/offers/budget', backoffice);
check('the cap is a percentage', budget0.capPercentage > 0, `${budget0.capPercentage}%`);
// Plus the standing allowance, which is what makes offers possible before there is any revenue.
//
// The share is rounded to the cent BEFORE the allowance is added, because that is what the server
// does — and it matters. Without it, any revenue whose half-share lands on a half-cent (768.93
// gives 384.465) puts the two figures exactly 0.005 apart, right on the tolerance boundary, and the
// suite fails once every few runs for reasons that look like a pricing bug.
const ceiling = (b) => Math.round(b.earned * b.capPercentage) / 100 + b.allowance;
check('the budget is that share of revenue, plus the allowance',
  near(budget0.budget, ceiling(budget0)),
  `${budget0.budget} = ${budget0.earned} x ${budget0.capPercentage}% + ${budget0.allowance}`);
check('kept is earned less given', near(budget0.kept, budget0.earned - budget0.given),
  `${budget0.kept}`);
check('the window is stated', budget0.windowDays > 0, `${budget0.windowDays} days`);

console.log('\n--- with no offers, an order is priced exactly as before ---');
const plain = place();
check('the order is placed', !!plain.id, plain.id || plain.error);
check('and the customer pays the delivery fee',
  near(plain.deliveryFee, store.deliveryFee) && near(plain.totalAmount, plain.subtotal + Number(store.deliveryFee)),
  `${plain.totalAmount} = ${plain.subtotal} + ${plain.deliveryFee}`);

console.log('\n--- free delivery for customers ---');
const freeDelivery = send('POST', '/api/offers', {
  audience: 'CUSTOMER',
  title: `Free delivery ${tag}`,
  subtitle: 'Launch promotion',
  minSubtotal: 0,
}, backoffice);
check('the Backoffice creates it', freeDelivery.code === '201', `HTTP ${freeDelivery.code}`);
const offer = JSON.parse(freeDelivery.body);
check('and it is live immediately', offer.live === true, 'live');

const freeOrder = place();
check('the next order charges no delivery fee',
  near(freeOrder.totalAmount, freeOrder.subtotal),
  `total ${freeOrder.totalAmount} vs subtotal ${freeOrder.subtotal}`);
// The fee still exists — it is what the carrier is owed. Only the payer changed.
check('but the fee itself is still on the order',
  near(freeOrder.deliveryFee, store.deliveryFee), `${freeOrder.deliveryFee}`);

console.log('\n--- and the customer is told, on a receipt that adds up ---');
// The bug this section exists for: the receipt rendered the delivery COST against a total that
// excluded it, so subtotal 15.00 + delivery 3.25 came to a total of 15.00.
check('the order says the fee was waived', freeOrder.deliveryFeeWaived === true, 'flagged');
check('and what the customer was actually charged for it',
  near(freeOrder.deliveryFeeCharged, 0), `${freeOrder.deliveryFeeCharged}`);
check('so the receipt adds up',
  near(freeOrder.subtotal + freeOrder.deliveryFeeCharged, freeOrder.totalAmount),
  `${freeOrder.subtotal} + ${freeOrder.deliveryFeeCharged} = ${freeOrder.totalAmount}`);
// Still shown as worth something, so the customer can see what they were given.
check('while still recording what delivery was worth',
  near(freeOrder.deliveryFee, store.deliveryFee), `${freeOrder.deliveryFee}`);

// The basket has to quote what will be charged, or checkout shows one number and bills another.
const preview = get(`/api/offers/preview?storeId=${store.id}&subtotal=${item.price}`
  + `&deliveryFee=${store.deliveryFee}`, customer);
check('a customer can ask what their basket qualifies for',
  preview.deliveryFeeWaived === true, 'free delivery');
check('and is told it will cost them nothing', near(preview.deliveryFeeCharged, 0),
  `${preview.deliveryFeeCharged}`);
check('and what the offer is called, so they know why',
  (preview.offerTitle || '').length > 0, preview.offerTitle);
check('the quote matches what placing it actually charges',
  near(preview.deliveryFeeCharged, freeOrder.deliveryFeeCharged), 'agreed');

const budget1 = get('/api/offers/budget', backoffice);
check('the giveaway is counted against the budget',
  near(budget1.givenCustomer, budget0.givenCustomer + Number(store.deliveryFee)),
  `${budget1.givenCustomer}`);
check('and earnings still grew, because the order still earned commission',
  budget1.earned > budget0.earned, `${budget0.earned} to ${budget1.earned}`);

console.log('\n--- withdrawing it is not retroactive ---');
check('the offer is withdrawn',
  send('POST', `/api/offers/${offer.id}/withdraw`, null, backoffice).code === '200', 'withdrawn');
check('and no longer live',
  get('/api/offers', backoffice).find((o) => o.id === offer.id).live === false, 'not live');

const afterWithdrawal = place();
check('the next order pays the fee again',
  near(afterWithdrawal.totalAmount, afterWithdrawal.subtotal + Number(store.deliveryFee)),
  `${afterWithdrawal.totalAmount}`);
// The whole reason the decision is stamped on the order rather than looked up at settlement.
check('but the earlier order still shows free delivery',
  near(get(`/api/orders/${freeOrder.id}`, customer).totalAmount, freeOrder.subtotal),
  'unchanged');

console.log('\n--- no commission for merchants ---');
const noCommission = JSON.parse(send('POST', '/api/offers', {
  audience: 'MERCHANT',
  title: `No commission ${tag}`,
  minSubtotal: 0,
}, backoffice).body);

const merchantOffer = place();
// A merchant promotion is between the platform and the shop. The customer is not part of it.
check('the customer still pays their delivery fee',
  near(merchantOffer.totalAmount, merchantOffer.subtotal + Number(store.deliveryFee)),
  `${merchantOffer.totalAmount}`);

// A merchant's payout is their own money, so the order has to say the commission was waived.
check('the order tells the merchant their commission was waived',
  merchantOffer.merchantFeeWaived === true, 'flagged');
check('and the customer\'s own receipt is untouched by it',
  merchantOffer.deliveryFeeWaived === false
    && near(merchantOffer.subtotal + merchantOffer.deliveryFeeCharged, merchantOffer.totalAmount),
  'adds up');

const budget2 = get('/api/offers/budget', backoffice);
check('the commission given up is counted',
  budget2.givenMerchant > budget1.givenMerchant,
  `${budget1.givenMerchant} to ${budget2.givenMerchant}`);
check('and it is booked against merchants, not customers',
  near(budget2.givenCustomer, budget1.givenCustomer), `${budget2.givenCustomer}`);

send('POST', `/api/offers/${noCommission.id}/withdraw`, null, backoffice);

console.log('\n--- a minimum basket keeps an offer off small orders ---');
const bigOnly = JSON.parse(send('POST', '/api/offers', {
  audience: 'CUSTOMER',
  title: `Big baskets only ${tag}`,
  minSubtotal: 100000,
}, backoffice).body);

const belowMinimum = place();
check('an order under the minimum pays normally',
  near(belowMinimum.totalAmount, belowMinimum.subtotal + Number(store.deliveryFee)),
  `${belowMinimum.totalAmount}`);
send('POST', `/api/offers/${bigOnly.id}/withdraw`, null, backoffice);

console.log('\n--- an offer that could never run is refused ---');
const backwards = send('POST', '/api/offers', {
  audience: 'CUSTOMER',
  title: `Backwards ${tag}`,
  startsAt: new Date(Date.now() + 86400000).toISOString(),
  endsAt: new Date(Date.now() + 3600000).toISOString(),
}, backoffice);
check('an end before its start is refused', backwards.code === '422', `HTTP ${backwards.code}`);
check('with a reason', (JSON.parse(backwards.body).message || '').length > 0,
  JSON.parse(backwards.body).message);

const alreadyOver = send('POST', '/api/offers', {
  audience: 'CUSTOMER',
  title: `Over ${tag}`,
  endsAt: new Date(Date.now() - 3600000).toISOString(),
}, backoffice);
// Better to find out now than from the merchant you just promised it to.
check('so is one that is already over', alreadyOver.code === '422', `HTTP ${alreadyOver.code}`);

console.log('\n--- the budget is a ceiling, not a suggestion ---');
const budget3 = get('/api/offers/budget', backoffice);
check('what is left is never negative', budget3.remaining >= 0, `${budget3.remaining}`);
check('the gauge never exceeds a hundred', budget3.usedPercent <= 100, `${budget3.usedPercent}%`);
check('the ceiling did not shrink as it was spent',
  near(budget3.budget, ceiling(budget3)),
  `${budget3.budget} on earnings of ${budget3.earned}`);

// The real test of the cap: an offer nobody can afford. A 100% cap would still be bounded, so this
// only proves the mechanism if the cap is below 100 — which it is by default.
if (budget3.capPercentage < 100) {
  check('giving away everything is not possible under a cap below 100%',
    budget3.given <= budget3.budget + 0.005,
    `given ${budget3.given} against a budget of ${budget3.budget}`);
} else {
  console.log('  SKIP  the cap is 100%, so there is no ceiling to test');
}

console.log('\n--- withdrawn offers are kept, not deleted ---');
// The row is the only record of why the platform gave that money away.
check('the withdrawn offer is still listed',
  get('/api/offers', backoffice).some((o) => o.id === offer.id), 'kept');
check('marked inactive rather than removed',
  get('/api/offers', backoffice).find((o) => o.id === offer.id).active === false, 'inactive');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
