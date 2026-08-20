// A WhatsApp message becomes a real order.
//
//   node infra/smoke-test-whatsapp-orders.js
//
// The whole design of this feature lives in the gap between a message and an order. A message is a
// request; a draft is the merchant's reading of it; an order is a commitment. The checks here are
// about that gap holding: "hi" must never become a purchase, a draft must commit to nothing, and
// once confirmed the result must be an ordinary order — priced by the catalog, dispatched by the
// same code, settled the same way — and not a parallel kind of thing that will drift.
const { execSync } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const GW = 'http://127.0.0.1:8100';
const SECRET = process.env.WHATSAPP_APP_SECRET || 'local-webhook-secret';

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const merchant = token('merchant');
const otherMerchant = token('merchant2');
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

// Every run needs its own customer, number and address. The first version of this file derived the
// phone number from a base36 tag with the letters stripped, which collided across runs — two runs
// then shared a conversation and its still-open draft, and the failures looked like product bugs.
const tag = Date.now().toString(36).slice(-6);
const NUMBER = `PN-ord-${tag}`;
const CUSTOMER_WA = `961${String(Date.now()).slice(-9)}`;
const ADDRESS = `Hamra, above the pharmacy, 3rd floor (${tag})`;

const bodyFile = path.join(os.tmpdir(), `wa-ord-${tag}.json`);
const postWebhook = (payload) => {
  const raw = JSON.stringify(payload);
  fs.writeFileSync(bodyFile, raw, 'utf8');
  const sig = 'sha256=' + crypto.createHmac('sha256', SECRET).update(raw, 'utf8').digest('hex');
  return split(sh(`curl -s -X POST -w "~~%{http_code}" -H "Content-Type: application/json"`
    + ` -H "X-Hub-Signature-256: ${sig}" --data-binary "@${bodyFile}" "${GW}/webhooks/whatsapp"`));
};

let seq = 0;
const envelope = (text) => ({
  object: 'whatsapp_business_account',
  entry: [{
    id: 'WABA',
    changes: [{
      field: 'messages',
      value: {
        messaging_product: 'whatsapp',
        metadata: { phone_number_id: NUMBER },
        contacts: [{ profile: { name: 'Rana' }, wa_id: CUSTOMER_WA }],
        messages: [{
          from: CUSTOMER_WA, id: `wamid.${tag}.${++seq}`,
          timestamp: String(Math.floor(Date.now() / 1000)),
          type: 'text', text: { body: text },
        }],
      },
    }],
  }],
});

// ---------------------------------------------------------------- what the shop actually sells
const store = get('/api/stores/mine', merchant).content.find(s => s.availability !== 'CLOSED');
if (!store) {
  console.error('The merchant has no open shop; run smoke-test-store-admin.js first.');
  process.exit(1);
}
// GET /api/products has no storeId filter — it is the customer browse endpoint — so the merchant's
// own list is filtered here. Order Manager requires every line to come from one shop.
const catalogue = (get('/api/products/mine?size=50', merchant).content || [])
  .filter(p => p.storeId === store.id && p.status === 'ACTIVE');

// Split by whether the product has required options. A shop's real menu has both, and the two take
// different paths through this feature — that is exactly why the first run of this test failed.
const withOptions = [];
const plain = [];
for (const p of catalogue) {
  const groups = get(`/api/whatsapp/drafts/products/${p.id}/options`, merchant);
  (groups.some(g => g.required) ? withOptions : plain).push({ ...p, groups });
  if (plain.length >= 2 && withOptions.length >= 1) break;
}
if (plain.length < 2) {
  console.error('The merchant needs at least two option-free products in one shop; '
    + 'run smoke-test-store-admin.js first.');
  process.exit(1);
}
const [itemA, itemB] = plain;
console.log(`    ${store.name}: ${itemA.name} ${itemA.price}, ${itemB.name} ${itemB.price}`);
console.log(`    ${withOptions.length ? withOptions[0].name + ' has required options' : 'no product with required options'}\n`);

// Something belonging to a different shop, for the ownership check below. Created if the second
// merchant has nothing, because "no competitor product to try" would silently turn the most
// important check in this file into a no-op.
let foreign = (get('/api/products/mine?size=20', otherMerchant).content || [])
  .find(p => p.status === 'ACTIVE');
if (!foreign) {
  // Creating a first product auto-provisions the shop, so the second merchant needs nothing set up
  // beforehand.
  const made = send('POST', '/api/products', {
    name: `Rival Special ${tag}`, description: 'for an ownership check',
    price: 9.99, categoryId: get('/api/categories', otherMerchant)[0].id,
  }, otherMerchant);
  if (made.code === '201') {
    foreign = JSON.parse(made.body);
    send('POST', `/api/products/${foreign.id}/publish`, null, otherMerchant);
  }
}

console.log('--- a message arrives, and is still only a message ---');
send('POST', '/api/whatsapp/numbers', { phoneNumberId: NUMBER, label: 'Orders' }, merchant);
postWebhook(envelope('hi'));
const convo = get('/api/whatsapp/conversations', merchant).find(c => c.customerWaId === CUSTOMER_WA);
check('the conversation exists', !!convo, convo && convo.customerName);
// The single most important property of this design: nothing was bought.
check('and no order was created by it',
  get('/api/orders/merchant?size=50', merchant).content
    .every(o => !(o.contactPhone === CUSTOMER_WA && o.status === 'PENDING' && !o.deliveryAddress)),
  'no purchase');
check('and no draft appeared on its own',
  get('/api/whatsapp/drafts', merchant).every(d => d.conversationId !== convo.id), 'none');

postWebhook(envelope(`2 ${itemA.name} and 1 ${itemB.name}, Hamra 3rd floor`));

console.log('\n--- the merchant opens a draft ---');
const opened = send('POST', `/api/whatsapp/drafts/conversations/${convo.id}`,
  { requestText: `2 ${itemA.name} and 1 ${itemB.name}, Hamra 3rd floor` }, merchant);
check('a draft opens against the conversation', opened.code === '201', `HTTP ${opened.code}`);
let draft = JSON.parse(opened.body);
check('holding what the customer wrote', draft.requestText.includes(itemA.name), 'verbatim');
check('with nothing in it yet', draft.lines.length === 0 && !draft.placeable, 'empty');

const again = send('POST', `/api/whatsapp/drafts/conversations/${convo.id}`, {}, merchant);
// A merchant tapping twice, or on two devices, must not split one request into two half-orders.
check('opening it again returns the same draft',
  JSON.parse(again.body).id === draft.id, 'idempotent');

console.log('\n--- building it from the merchant\'s own catalog ---');
draft = JSON.parse(send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
  { productId: itemA.id, qty: 1 }, merchant).body);
draft = JSON.parse(send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
  { productId: itemA.id, qty: 1 }, merchant).body);
check('the same item twice is a quantity, not two lines',
  draft.lines.length === 1 && draft.lines[0].qty === 2, `${draft.lines.length} line(s)`);

draft = JSON.parse(send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
  { productId: itemB.id, qty: 1 }, merchant).body);
check('a second product is its own line', draft.lines.length === 2, `${draft.lines.length} lines`);

const expected = Number(itemA.price) * 2 + Number(itemB.price);
check('the estimate adds up at captured prices',
  Math.abs(Number(draft.estimatedSubtotal) - expected) < 0.005,
  `${draft.estimatedSubtotal} vs ${expected.toFixed(2)}`);

if (foreign) {
  // Without this check a merchant builds a draft from a competitor's menu, quotes the customer a
  // price, and only discovers the problem when Order Manager refuses the whole thing.
  const before = draft.lines.length;
  const poached = send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: foreign.id, qty: 1 }, merchant);
  check('a competitor\'s product is refused', poached.code === '422', `HTTP ${poached.code}`);
  // Two legitimate refusals reach here depending on the rival product's status: the catalog hides a
  // DRAFT from anyone but its owner (404 → "could not be found"), and an ACTIVE one is stopped by
  // the ownership check ("not yours to sell"). Both are correct; asserting one wording made this
  // check fail for a reason that had nothing to do with the rule.
  check('with a message the merchant can act on',
    (JSON.parse(poached.body).message || '').length > 0, JSON.parse(poached.body).message);
  check('and nothing was added to the draft',
    get(`/api/whatsapp/drafts/${draft.id}`, merchant).lines.length === before, `${before} lines`);
  check('nor can its options be read',
    send('GET', `/api/whatsapp/drafts/products/${foreign.id}/options`, null, merchant).code === '422',
    'menu structure is theirs');
} else {
  fail++;
  console.log('  FAIL  could not obtain a competitor product; ownership check not run');
}
check('a product that does not exist is refused',
  send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: '00000000-0000-0000-0000-000000000000', qty: 1 }, merchant).code === '422',
  'unknown product');
check('a quantity of zero is refused',
  send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: itemA.id, qty: 0 }, merchant).code === '400', 'validation');

console.log('\n--- products with options, which is most of a real menu ---');
// The first run of this test failed here, and correctly: the shop's own products have required
// option groups, and a draft that could only name a product could not express one of them. Half the
// catalogue was unorderable over WhatsApp.
if (withOptions.length) {
  const configurable = withOptions[0];
  const required = configurable.groups.find(g => g.required);

  const noPick = send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: configurable.id, qty: 1 }, merchant);
  check('a required group must be answered', noPick.code === '422', `HTTP ${noPick.code}`);
  // The catalog names the group that is missing. Flattening that to "invalid selection" leaves the
  // merchant guessing while a customer waits.
  check('and the refusal names the group',
    JSON.parse(noPick.body).message.includes(required.name),
    JSON.parse(noPick.body).message);

  const choice = required.options.find(o => o.available) || required.options[0];
  const configured = send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: configurable.id, qty: 1, optionIds: [choice.id] }, merchant);
  check('a valid selection is accepted', configured.code === '200', `HTTP ${configured.code}`);

  draft = JSON.parse(configured.body);
  const line = draft.lines.find(l => l.productId === configurable.id);
  check('the line reads back in words, not UUIDs',
    line.optionsSummary === `${required.name}: ${choice.name}`, line.optionsSummary);
  check('priced by the catalog with the option applied',
    Math.abs(Number(line.unitPrice) - (Number(configurable.price) + Number(choice.priceDelta))) < 0.005,
    `${line.unitPrice}`);

  // Removal is by line id: with options the same product is legitimately in the basket twice, and
  // "remove the pizza" would delete the wrong one.
  draft = JSON.parse(send('DELETE', `/api/whatsapp/drafts/${draft.id}/lines/${line.id}`,
    null, merchant).body);
  check('and can be removed by line, not by product',
    !draft.lines.some(l => l.id === line.id), `${draft.lines.length} lines left`);
} else {
  console.log('  SKIP  no product with required options in this shop');
}

console.log('\n--- it commits to nothing until confirmed ---');
check('not placeable without an address', draft.placeable === false, 'no address');
const tooSoon = send('POST', `/api/whatsapp/drafts/${draft.id}/place`, null, merchant);
check('and placing it is refused', tooSoon.code === '422', `HTTP ${tooSoon.code}`);
check('with a reason the merchant can act on',
  JSON.parse(tooSoon.body).message.toLowerCase().includes('address'),
  JSON.parse(tooSoon.body).message);

draft = JSON.parse(send('PUT', `/api/whatsapp/drafts/${draft.id}/delivery`, {
  deliveryAddress: ADDRESS,
  contactPhone: CUSTOMER_WA,
  notes: 'ring twice',
}, merchant).body);
check('an address makes it placeable', draft.placeable === true, 'ready');
check('and the address is kept as typed',
  draft.deliveryAddress === ADDRESS, draft.deliveryAddress);

console.log('\n--- another shop cannot touch it ---');
check('cannot read it',
  send('GET', `/api/whatsapp/drafts/${draft.id}`, null, otherMerchant).code === '404', 'absent');
check('cannot add to it',
  send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: itemA.id, qty: 1 }, otherMerchant).code === '422', 'no such request');
check('cannot place it',
  send('POST', `/api/whatsapp/drafts/${draft.id}/place`, null, otherMerchant).code === '422',
  'no such request');
check('a customer cannot reach drafts at all',
  send('GET', '/api/whatsapp/drafts', null, customer).code === '403', 'forbidden');

console.log('\n--- confirming it makes an ordinary order ---');
const placed = send('POST', `/api/whatsapp/drafts/${draft.id}/place`, null, merchant);
check('the draft is placed', placed.code === '200', `HTTP ${placed.code}`);
const done = JSON.parse(placed.body);
check('and now names the order it became', !!done.orderId, done.orderId);
check('marked PLACED', done.status === 'PLACED', done.status);

const order = get(`/api/orders/${done.orderId}`, merchant);
check('the order exists in Order Manager', !!order.id, order.id);
check('as a CATALOG order like any other', order.kind === 'CATALOG', order.kind);
check('belonging to this merchant',
  get('/api/orders/merchant?size=50', merchant).content.some(o => o.id === done.orderId), 'listed');
check('carrying the address the merchant typed',
  order.deliveryAddress === ADDRESS, order.deliveryAddress);
check('and the note', order.notes === 'ring twice', order.notes);
check('paid in cash', order.paymentMethod === 'CASH', order.paymentMethod);

// The point of going through Order Manager rather than pricing it here: the catalog prices it and
// the shop's own delivery fee applies, exactly as for an order from the app.
check('priced by the catalog, not by the draft',
  Math.abs(Number(order.subtotal) - expected) < 0.005,
  `${order.subtotal} vs ${expected.toFixed(2)}`);
check('with the shop\'s delivery fee applied',
  Number(order.deliveryFee) === Number(store.deliveryFee),
  `${order.deliveryFee} vs ${store.deliveryFee}`);
check('and a total that is the sum of both',
  Math.abs(Number(order.totalAmount) - (Number(order.subtotal) + Number(order.deliveryFee))) < 0.005,
  `${order.totalAmount}`);

console.log('\n--- a placed draft is frozen ---');
check('it cannot be placed twice',
  send('POST', `/api/whatsapp/drafts/${draft.id}/place`, null, merchant).code === '422',
  'already placed');
// The expensive failure: two orders, two riders, one customer who asked once.
check('and no second order appeared',
  get('/api/orders/merchant?size=50', merchant).content
    .filter(o => o.deliveryAddress === ADDRESS).length === 1,
  'exactly one');
check('it cannot be edited',
  send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: itemA.id, qty: 1 }, merchant).code === '422', 'frozen');
check('it leaves the open work list',
  get('/api/whatsapp/drafts', merchant).every(d => d.id !== draft.id), 'done');
check('but stays on the conversation\'s history',
  get(`/api/whatsapp/drafts/conversations/${convo.id}`, merchant).some(d => d.id === draft.id),
  'kept');

console.log('\n--- the customer is not an account holder, and is not treated as one ---');
// A merchant places these orders. If the customer reference could look like a Keycloak subject, a
// merchant could place an order in a real account holder's name.
check('the order does not appear in any app customer\'s history',
  get('/api/orders/mine?size=50', customer).content.every(o => o.id !== done.orderId), 'isolated');

console.log('\n--- a request the merchant decides is not an order ---');
postWebhook(envelope('actually never mind'));
const second = JSON.parse(send('POST', `/api/whatsapp/drafts/conversations/${convo.id}`,
  { requestText: 'actually never mind' }, merchant).body);
check('a new draft opens once the last one is resolved', second.id !== draft.id, 'new draft');
const discarded = send('POST', `/api/whatsapp/drafts/${second.id}/discard`, null, merchant);
check('and can simply be discarded',
  discarded.code === '200' && JSON.parse(discarded.body).status === 'DISCARDED', 'discarded');
check('leaving no order behind',
  get('/api/orders/merchant?size=50', merchant).content
    .filter(o => o.deliveryAddress === ADDRESS).length === 1,
  'still exactly one');

try { fs.unlinkSync(bodyFile); } catch { /* best effort */ }

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);

