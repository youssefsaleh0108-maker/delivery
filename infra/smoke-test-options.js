// Product options and modifiers smoke test.
//
// The "Choose Size: Medium (30 Cm)" flow, end to end: a merchant defines option groups, the catalog
// prices a selection, invalid selections are refused, and an order snapshots what was chosen.
//
//   node infra/smoke-test-options.js
const { execSync } = require('child_process');
const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });

const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const merchant = token('merchant');
const customer = token('customer');
const call = (m, p, body, tok = merchant) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, tok) => JSON.parse(split(call('GET', p, null, tok)).body);
const send = (m, p, body, tok) => split(call(m, p, body, tok));
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 50) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 50) + (detail ?? '')); }
};

// A product of the merchant's own to attach options to.
const mine = get('/api/products/mine?size=1');
if (!mine.content.length) { console.error('Merchant has no products.'); process.exit(1); }
const product = mine.content[0];
const base = product.price;
console.log(`--- "${product.name}" (base ${base}) ---`);

const groups = send('PUT', `/api/products/${product.id}/options`, [
  { name: 'Choose Size', minSelect: 1, maxSelect: 1, options: [
      { name: 'Small (24 Cm)', priceDelta: -1.50, isDefault: false },
      { name: 'Medium (30 Cm)', priceDelta: 0, isDefault: true },
      { name: 'Large (36 Cm)', priceDelta: 3.00, isDefault: false } ] },
  { name: 'Extras', minSelect: 0, maxSelect: 2, options: [
      { name: 'Extra cheese', priceDelta: 1.25, isDefault: false },
      { name: 'Mushrooms', priceDelta: 0.75, isDefault: false },
      { name: 'Olives', priceDelta: 0.50, isDefault: false } ] },
]);
check('option groups save', groups.code === '200', `HTTP ${groups.code}`);
const saved = JSON.parse(groups.body);
check('two groups come back', saved.length === 2, saved.map(g => g.name).join(', '));
check('size is required and single-choice', saved[0].required && saved[0].singleChoice);
check('extras is optional and multi-choice', !saved[1].required && !saved[1].singleChoice);

// Reading them back, which the customer app does before it can show the sheet. Untested until a
// 500 turned up here: the write path returns the entity it just built in-session, so it never
// touched the lazy collection, while the read path mapped it after the session had closed. A
// product with no options answered fine either way, which is how this survived.
const fetched = send('GET', `/api/products/${product.id}/options`, null, customer);
check('a customer can read the options back', fetched.code === '200', `HTTP ${fetched.code}`);
const read = JSON.parse(fetched.body);
check('both groups come back', read.length === 2, read.map(g => g.name).join(', '));
check('and their choices come with them',
  read.every(g => Array.isArray(g.options) && g.options.length > 0),
  read.map(g => `${g.name}=${(g.options || []).length}`).join(' '));

const size = saved[0].options;
const extras = saved[1].options;
const medium = size.find(o => o.name.startsWith('Medium'));
const large = size.find(o => o.name.startsWith('Large'));
const small = size.find(o => o.name.startsWith('Small'));
const cheese = extras.find(o => o.name === 'Extra cheese');
const olives = extras.find(o => o.name === 'Olives');

console.log('--- pricing ---');
const priceOf = (ids) => send('POST', `/api/products/${product.id}/price`, { optionIds: ids }, customer);
const medPrice = priceOf([medium.id]);
check('a valid selection prices', medPrice.code === '200', `HTTP ${medPrice.code}`);
check('medium is the base price', JSON.parse(medPrice.body).unitPrice === base,
  `${JSON.parse(medPrice.body).unitPrice}`);
check('large adds its delta',
  JSON.parse(priceOf([large.id]).body).unitPrice === Number((base + 3).toFixed(2)),
  `${JSON.parse(priceOf([large.id]).body).unitPrice}`);
// A negative delta is ordinary — a menu priced from its middle size needs it.
check('small subtracts its delta',
  JSON.parse(priceOf([small.id]).body).unitPrice === Number((base - 1.5).toFixed(2)),
  `${JSON.parse(priceOf([small.id]).body).unitPrice}`);
check('deltas stack across groups',
  JSON.parse(priceOf([large.id, cheese.id, olives.id]).body).unitPrice
    === Number((base + 3 + 1.25 + 0.5).toFixed(2)),
  `${JSON.parse(priceOf([large.id, cheese.id, olives.id]).body).unitPrice}`);
check('the chosen options come back for the receipt',
  JSON.parse(priceOf([large.id, cheese.id]).body).options
    .map(o => `${o.groupName}: ${o.optionName}`).join(', ')
    === 'Choose Size: Large (36 Cm), Extras: Extra cheese');

console.log('--- invalid selections are refused ---');
const missingChoice = priceOf([]);
const detailOf = (body) => { try { return JSON.parse(body).detail ?? ''; } catch { return ''; } };
const missingDetail = detailOf(missingChoice.body);
check('a missing required choice is refused', missingChoice.code === '422', missingDetail);
// The group here is literally named "Choose Size". A template that folds the name into the
// sentence produces "Choose an option under Choose Size"; the name must stay a quoted label.
check('the message does not stack verbs on the group name',
  !/choose an option under/i.test(missingDetail) && !/Choose Choose/i.test(missingDetail),
  missingDetail);
check('two choices in a single-choice group are refused',
  priceOf([medium.id, large.id]).code === '422');
check('exceeding a multi-select maximum is refused',
  priceOf([medium.id, ...extras.map(o => o.id)]).code === '422', '3 extras, max 2');
check('an option from another product is refused',
  priceOf([medium.id, '11111111-2222-4333-8444-555555555555']).code === '422');
// Sending the same option twice must not apply its delta twice.
check('a duplicated option is counted once',
  JSON.parse(priceOf([large.id, large.id]).body).unitPrice === Number((base + 3).toFixed(2)));

console.log('--- ordering ---');
const placeWith = (ids, qty = 1) => send('POST', '/api/orders', {
  items: [{ productId: product.id, qty, optionIds: ids }],
  deliveryAddress: '12 Test Street', contactPhone: null, notes: null,
}, customer);

const bad = placeWith([]);
check('an order with a missing required choice is refused', bad.code === '422',
  detailOf(bad.body));

const ok = placeWith([large.id, cheese.id]);
check('an order with a valid selection is accepted', ok.code === '201', `HTTP ${ok.code}`);
if (ok.code === '201') {
  const line = JSON.parse(ok.body).items[0];
  check('the line is priced with the options',
    line.unitPrice === Number((base + 3 + 1.25).toFixed(2)), `${line.unitPrice}`);
  check('the base price is kept for the breakdown', line.baseUnitPrice === base,
    `${line.baseUnitPrice}`);
  check('the options are snapshotted onto the line', line.options.length === 2);
  check('the receipt summary reads correctly',
    line.optionsSummary === 'Choose Size: Large (36 Cm), Extras: Extra cheese',
    line.optionsSummary);
}

// Two configurations of one product are two lines, not quantity two.
const twoConfigs = send('POST', '/api/orders', {
  items: [
    { productId: product.id, qty: 1, optionIds: [large.id] },
    { productId: product.id, qty: 1, optionIds: [small.id] },
  ],
  deliveryAddress: '12 Test Street', contactPhone: null, notes: null,
}, customer);
check('the same product with different options is two lines',
  twoConfigs.code === '201' && JSON.parse(twoConfigs.body).items.length === 2,
  twoConfigs.code === '201' ? `${JSON.parse(twoConfigs.body).items.length} lines` : `HTTP ${twoConfigs.code}`);

// ...but the identical configuration twice still merges into quantity two.
const sameTwice = send('POST', '/api/orders', {
  items: [
    { productId: product.id, qty: 1, optionIds: [large.id] },
    { productId: product.id, qty: 1, optionIds: [large.id] },
  ],
  deliveryAddress: '12 Test Street', contactPhone: null, notes: null,
}, customer);
check('the identical configuration twice merges to qty 2',
  sameTwice.code === '201' && JSON.parse(sameTwice.body).items.length === 1
    && JSON.parse(sameTwice.body).items[0].qty === 2,
  sameTwice.code === '201' ? `${JSON.parse(sameTwice.body).items.length} line(s)` : `HTTP ${sameTwice.code}`);

console.log('--- ownership ---');
check('a customer cannot set options',
  send('PUT', `/api/products/${product.id}/options`, [], customer).code === '403');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
