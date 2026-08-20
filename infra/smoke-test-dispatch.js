// Deciding who is asked to carry an order, rather than recording who happened to turn up.
//
//   node infra/smoke-test-dispatch.js
//
// Three things have to hold at once:
//   * a merchant who never opens this setting sees no change at all
//   * a merchant who pins a carrier gets that carrier, and its riders get the job
//   * a rider never sees work offered to somebody else's fleet
//
// The last one is the security property. The other two are the feature.
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
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

const IN_HOUSE = '00000000-0000-4000-8000-00000000d001';
const store = get('/api/stores/mine', merchant).content.find(s => s.availability !== 'CLOSED');
const product = get(`/api/stores/${store.id}/products?size=50`).content
  .find(p => get(`/api/products/${p.id}/options`).every(g => !g.required));
const qty = Math.max(1, Math.ceil(store.minOrder / product.price));

/** Places an order and drives it to READY, which is when a carrier is chosen. */
function readyOrder() {
  const placed = send('POST', '/api/orders', {
    items: [{ productId: product.id, qty }],
    deliveryAddress: '12 Test Street, Flat 4', paymentMethod: 'CASH',
  }, customer);
  const id = JSON.parse(placed.body).id;
  for (const step of ['accept', 'prepare', 'ready']) send('POST', `/api/orders/${id}/${step}`, null, merchant);
  return get(`/api/orders/${id}`, customer);
}

// Leave the merchant with no preference at the start, whatever a previous run did.
send('PUT', '/api/delivery-providers/policy', { preferredProviderId: null }, merchant);
send('DELETE', `/api/delivery-providers/riders/${riderSub}`, null);

console.log('--- a merchant who never chose anything ---');
const policy = get('/api/delivery-providers/policy', merchant);
check('the platform decides by default', policy.platformDecides === true);
const defaultOrder = readyOrder();
check('and the order goes to the in-house fleet',
  defaultOrder.deliveryProviderId === IN_HOUSE, `${defaultOrder.deliveryProviderId?.slice(0, 8)}`);
// A large page deliberately. The board is ordered oldest-first and every suite that drives an order
// to READY without claiming it leaves one behind, so the just-created order this looks for sinks
// further down the list with every run until it falls off page one.
check('an ordinary rider sees it on their board',
  get('/api/orders/available?size=500', rider).content.some(o => o.id === defaultOrder.id));
check('and can claim it',
  send('POST', `/api/orders/${defaultOrder.id}/claim`, null, rider).code === '200');

console.log('\n--- the merchant pins a delivery company ---');
const slug = `dispatch-${Date.now().toString(36).slice(-6)}`;
const company = JSON.parse(send('POST', '/api/delivery-providers', {
  slug, name: 'Dispatch Test Carrier', accountRef: 'ACC-CARRIER',
}).body);
const chosen = send('PUT', '/api/delivery-providers/policy',
  { preferredProviderId: company.id, allowFallback: true }, merchant);
check('the merchant chooses it', chosen.code === '200', `HTTP ${chosen.code}`);
check('and the policy remembers', JSON.parse(chosen.body).preferredProviderId === company.id);

const pinnedOrder = readyOrder();
check('the next order is dispatched there', pinnedOrder.deliveryProviderId === company.id,
  `${pinnedOrder.deliveryProviderId?.slice(0, 8)} vs ${company.id.slice(0, 8)}`);

// The security property: work offered to one fleet is invisible to another.
console.log('\n--- a rider only sees their own fleet\'s work ---');
check('an in-house rider does not see it',
  !get('/api/orders/available?size=50', rider).content.some(o => o.id === pinnedOrder.id));
check('and cannot claim it even knowing the id',
  send('POST', `/api/orders/${pinnedOrder.id}/claim`, null, rider).code === '404',
  'flat not-found, not a 403 that confirms it is there');

console.log('\n--- move the rider to that company ---');
send('POST', `/api/delivery-providers/${company.id}/riders`, { riderRef: riderSub });
check('now they see it',
  get('/api/orders/available?size=50', rider).content.some(o => o.id === pinnedOrder.id));
check('and can claim it',
  send('POST', `/api/orders/${pinnedOrder.id}/claim`, null, rider).code === '200');

console.log('\n--- fallback when the chosen carrier cannot take work ---');
send('POST', `/api/delivery-providers/${company.id}/suspend`, null);
const fallbackOrder = readyOrder();
check('the order still goes out, to somebody else',
  fallbackOrder.deliveryProviderId === IN_HOUSE,
  `${fallbackOrder.deliveryProviderId?.slice(0, 8)}`);

// A merchant whose brand travels with the driver can refuse a stranger. Then an undeliverable
// order stays visible rather than being quietly handed over.
console.log('\n--- a merchant who would rather wait ---');
send('PUT', '/api/delivery-providers/policy',
  { preferredProviderId: company.id, allowFallback: false }, merchant);
check('fallback can be turned off',
  get('/api/delivery-providers/policy', merchant).allowFallback === false);
// The carrier is still suspended from the step above.
const strandedOrder = readyOrder();
check('the order is left undispatched rather than reassigned',
  !strandedOrder.deliveryProviderId, `${strandedOrder.deliveryProviderId}`);
// Undispatched work is visible to everyone: better an unclaimed order somebody can see than one
// that silently never gets collected.
check('but it is not invisible — anyone may pick it up',
  get('/api/orders/available?size=50', rider).content.some(o => o.id === strandedOrder.id));

console.log('\n--- put everything back ---');
send('POST', `/api/delivery-providers/${company.id}/reinstate`, null);
send('PUT', '/api/delivery-providers/policy', { preferredProviderId: null }, merchant);
check('the rider returns to in-house',
  send('DELETE', `/api/delivery-providers/riders/${riderSub}`, null).code === '204');
const restored = readyOrder();
check('and dispatch is back to the in-house fleet',
  restored.deliveryProviderId === IN_HOUSE);

console.log('\n--- authorisation ---');
check('a customer cannot set a delivery policy',
  send('PUT', '/api/delivery-providers/policy', { preferredProviderId: null }, customer).code === '403');
check('a merchant cannot pin another merchant\'s fleet',
  send('PUT', '/api/delivery-providers/policy',
    { preferredProviderId: IN_HOUSE.replace(/d001$/, 'dfff') }, merchant).code === '404');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
