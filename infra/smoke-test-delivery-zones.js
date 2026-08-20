// Delivery priced by area, not by metres.
//
//   node infra/smoke-test-delivery-zones.js
//
// This task sat parked as "blocked on geocoding". That was the wrong premise: addresses in this
// market are landmarks and floor numbers, and every local delivery app asks the customer to pick
// their AREA rather than trying to resolve a street. So the shop declares which areas it serves and
// what it charges for each — no geocoder, no tiles, no coordinates.
//
// The check that makes this safe to ship is the first one: a shop that has set no areas must behave
// exactly as it did before areas existed.
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const back = token('backoffice');
const merchant = token('merchant');
const customer = token('customer');

const call = (m, p, body, tok = back) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, t) => JSON.parse(split(call('GET', p, null, t)).body);
const send = (m, p, b, t) => split(call(m, p, b, t));

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

const tag = Date.now().toString(36).slice(-5);

// The merchant's own shop: the seeded demo stores belong to a synthetic merchant.
const store = get('/api/stores/mine', merchant).content.find(s => s.availability !== 'CLOSED');
if (!store) {
  console.error('The merchant has no open shop; run smoke-test-store-admin.js first.');
  process.exit(1);
}
console.log(`    using ${store.name}, flat fee ${store.deliveryFee}\n`);

console.log('--- a shop that has set no areas is unchanged ---');
// This is what makes the feature shippable without a migration or a merchant doing anything.
const flat = get(`/api/delivery-zones/terms/${store.id}`, customer);
check('it serves anywhere', flat.served === true, `served=${flat.served}`);
check('at its flat fee', Number(flat.deliveryFee) === Number(store.deliveryFee),
  `${flat.deliveryFee} vs ${store.deliveryFee}`);

console.log('\n--- the platform defines the areas ---');
const hamra = send('POST', '/api/delivery-zones',
  { name: `Hamra ${tag}`, region: 'Beirut', sortOrder: 10 });
check('backoffice creates an area', hamra.code === '201', `HTTP ${hamra.code}`);
const near = JSON.parse(hamra.body);

const far = JSON.parse(send('POST', '/api/delivery-zones',
  { name: `Far Away ${tag}`, region: 'Mount Lebanon', sortOrder: 90 }).body);

check('a duplicate name is refused', send('POST', '/api/delivery-zones',
  { name: `Hamra ${tag}`, region: 'Beirut', sortOrder: 10 }).code === '409', 'conflict');
check('a merchant cannot define areas',
  send('POST', '/api/delivery-zones', { name: `Sneak ${tag}`, sortOrder: 1 }, merchant).code === '403',
  'forbidden');

const picker = get('/api/delivery-zones', customer);
check('a customer can read the picker', picker.some(z => z.id === near.id),
  `${picker.length} areas`);

console.log('\n--- the shop says where it goes, and for how much ---');
const covered = send('PUT', `/api/delivery-zones/coverage/${store.id}/${near.id}`,
  { deliveryFee: 2.00, minOrder: null, etaExtraMinutes: 0 }, merchant);
check('a merchant prices a nearby area', covered.code === '200', `HTTP ${covered.code}`);

const nearTerms = get(`/api/delivery-zones/terms/${store.id}?zoneId=${near.id}`, customer);
check('and that area now costs what they set',
  nearTerms.served === true && Number(nearTerms.deliveryFee) === 2, `${nearTerms.deliveryFee}`);
check('falling back to the shop\'s own minimum',
  Number(nearTerms.minOrder) === Number(store.minOrder),
  `${nearTerms.minOrder} vs ${store.minOrder}`);

console.log('\n--- an area the shop does not serve ---');
// "We don't go that far" — the commonest delivery rule here, and one the platform could not
// express at all before.
const farTerms = get(`/api/delivery-zones/terms/${store.id}?zoneId=${far.id}`, customer);
check('is refused rather than quietly priced', farTerms.served === false, `served=${farTerms.served}`);

console.log('\n--- a further area costs more and takes longer ---');
send('PUT', `/api/delivery-zones/coverage/${store.id}/${far.id}`,
  { deliveryFee: 7.50, minOrder: 25.00, etaExtraMinutes: 15 }, merchant);
const nowServed = get(`/api/delivery-zones/terms/${store.id}?zoneId=${far.id}`, customer);
check('now served', nowServed.served === true, `served=${nowServed.served}`);
check('at the higher fee', Number(nowServed.deliveryFee) === 7.5, `${nowServed.deliveryFee}`);
check('with its own higher minimum', Number(nowServed.minOrder) === 25, `${nowServed.minOrder}`);
// Quoting the same window everywhere is how an ETA stops being believed.
check('and a longer quoted wait',
  nowServed.etaMinMinutes === store.etaMinMinutes + 15, `${nowServed.etaMinMinutes} min`);

console.log('\n--- an order that names no area still works ---');
// A client that predates areas, or an order placed before the customer picked one. Failing here
// would break every existing app the moment one merchant sets one area.
const noZone = get(`/api/delivery-zones/terms/${store.id}`, customer);
check('served, at the flat fee', noZone.served === true, `${noZone.deliveryFee}`);

console.log('\n--- coverage is the merchant\'s own ---');
const coverage = get(`/api/delivery-zones/coverage/${store.id}`, merchant);
// Scoped to the areas this run created, not to a total: the shop is the merchant's real one and
// every previous run of this suite left its own areas priced on it. Asserting a count would pass
// once and then fail forever, for a reason that has nothing to do with zones.
const mine = coverage.filter(c => c.zoneId === near.id || c.zoneId === far.id);
check('a merchant reads their own coverage', mine.length === 2,
  `${mine.length} of this run's, ${coverage.length} in total`);
check('and it names them', mine.every(c => typeof c.zoneName === 'string' && c.zoneName.length > 0));

console.log('\n--- retiring an area ---');
const retired = send('POST', `/api/delivery-zones/${far.id}/retire`);
check('backoffice retires it', retired.code === '200', `HTTP ${retired.code}`);
check('it leaves the picker',
  !get('/api/delivery-zones', customer).some(z => z.id === far.id), 'hidden');
// Retired, not deleted: a saved address naming it must keep resolving, and the shop's price for it
// is still on file for when it comes back.
check('but the shop still has terms for it',
  get(`/api/delivery-zones/coverage/${store.id}`, merchant).some(c => c.zoneId === far.id),
  'kept');

console.log('\n--- and a real order is priced by the area it goes to ---');
// The point of all of the above. Until this was wired, zones existed and no customer was ever
// charged by one.
const product = get(`/api/stores/${store.id}/products?size=50`, customer).content
  .find(p => get(`/api/products/${p.id}/options`, customer).every(g => !g.required));
if (!product) {
  console.error('That store has no optionless products.');
  process.exit(1);
}
// Enough to clear the far area's higher minimum as well as the shop's own.
const qty = Math.max(1, Math.ceil(30 / product.price));

const nearOrder = send('POST', '/api/orders', {
  items: [{ productId: product.id, qty }],
  deliveryAddress: '12 Test Street, Flat 4',
  deliveryZoneId: near.id,
  paymentMethod: 'CASH',
}, customer);
check('an order to a served area is placed', nearOrder.code === '201', `HTTP ${nearOrder.code}`);
check('and charged that area\'s fee',
  Number(JSON.parse(nearOrder.body).deliveryFee) === 2, `${JSON.parse(nearOrder.body).deliveryFee}`);

const farOrder = send('POST', '/api/orders', {
  items: [{ productId: product.id, qty }],
  deliveryAddress: '99 Distant Road',
  deliveryZoneId: far.id,
  paymentMethod: 'CASH',
}, customer);
check('an order to the further area costs more',
  farOrder.code === '201' && Number(JSON.parse(farOrder.body).deliveryFee) === 7.5,
  `HTTP ${farOrder.code} fee ${farOrder.code === '201' ? JSON.parse(farOrder.body).deliveryFee : '-'}`);

const noZoneOrder = send('POST', '/api/orders', {
  items: [{ productId: product.id, qty }],
  deliveryAddress: '12 Test Street, Flat 4',
  paymentMethod: 'CASH',
}, customer);
// An address saved before areas existed. Priced at the flat fee rather than refused.
check('an order naming no area still goes through',
  noZoneOrder.code === '201', `HTTP ${noZoneOrder.code}`);
check('at the shop\'s flat fee',
  Number(JSON.parse(noZoneOrder.body).deliveryFee) === Number(store.deliveryFee),
  `${JSON.parse(noZoneOrder.body).deliveryFee}`);

console.log('\n--- dropping coverage ---');
const dropped = send('DELETE', `/api/delivery-zones/coverage/${store.id}/${far.id}`, null, merchant);
check('a merchant stops serving an area', dropped.code === '204', `HTTP ${dropped.code}`);
check('and it is refused again',
  get(`/api/delivery-zones/terms/${store.id}?zoneId=${far.id}`, customer).served === false,
  'not served');

// The refusal has to reach order placement, not just the terms endpoint.
const refused = send('POST', '/api/orders', {
  items: [{ productId: product.id, qty }],
  deliveryAddress: '99 Distant Road',
  deliveryZoneId: far.id,
  paymentMethod: 'CASH',
}, customer);
check('an order there is now refused outright', refused.code === '422', `HTTP ${refused.code}`);
check('with a reason the customer can act on',
  /does not deliver to that area/.test(refused.body), refused.body.slice(0, 90));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
