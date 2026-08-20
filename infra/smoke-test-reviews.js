// Reviews, real store ratings, and the order a review has to belong to.
//
// Proves the aggregate is recomputed from the reviews rather than incremented, that "no reviews" is
// null and not zero, that one order buys exactly one review — and, since V19, that a review has to
// correspond to an order this customer actually had delivered from this shop.
//
// That last part is why this suite now drives real orders the whole way to DELIVERED instead of
// inventing order ids. It used to invent them, and it passed: the endpoint took the caller's word,
// so a token plus a random UUID bought a five-star review of anybody's shop, repeatedly. Ratings
// drive the storefront ranking, so this suite was demonstrating the hole rather than covering it.
//
//   node infra/smoke-test-reviews.js
const { execSync } = require('child_process');
const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const customer = token('customer');
const merchant = token('merchant');
const rider = token('rider');
const back = token('backoffice');
const call = (m, p, body, tok = customer) => {
  const d = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${d} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, tok) => JSON.parse(split(call('GET', p, null, tok)).body);
const send = (m, p, b, tok) => split(call(m, p, b, tok));
const pad = (s, n) => String(s).slice(0, n).padEnd(n);
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const uuid = () => 'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx'.replace(/x/g,
  () => Math.floor(Math.random() * 16).toString(16));

let pass = 0, fail = 0;
const check = (l, c, d) => { if (c) { pass++; console.log('  PASS  ' + pad(l, 50) + (d ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(l, 50) + (d ?? '')); } };

// The merchant's OWN shop. The seeded demo stores belong to a synthetic 'demo-merchant', so the
// real merchant user cannot accept orders against them — and without an accepted order there is
// nothing reviewable to test with.
const store = get('/api/stores/mine', merchant).content.find(s => s.availability !== 'CLOSED');
if (!store) {
  console.error('The merchant has no open shop; run smoke-test-store-admin.js first.');
  process.exit(1);
}
const product = get(`/api/stores/${store.id}/products?size=50`, customer).content
  .find(p => get(`/api/products/${p.id}/options`, customer).every(g => !g.required));
if (!product) { console.error('That store has no optionless products.'); process.exit(1); }
const qty = Math.max(1, Math.ceil(store.minOrder / product.price));

console.log(`--- "${store.name}" ---`);

// A seeded store nobody has ordered from: the cleanest place to assert that "unrated" is null
// rather than zero, which is the distinction the storefront depends on.
const unrated = get('/api/stores?size=20').content.find(s => s.ratingCount === 0);
if (unrated) {
  check('an unrated store has a null rating', unrated.rating === null, `${unrated.rating}`);
  check('and a count of zero', unrated.ratingCount === 0, `${unrated.ratingCount}`);
}

// Baselines rather than absolutes: this shop is reused across runs, and a suite that assumes it
// starts empty fails for a reason that has nothing to do with reviews.
const before = get(`/api/stores/${store.id}`);
const baseCount = before.ratingCount;

// Dispatch must reach THIS suite's rider or nothing is ever delivered. The same starting conditions
// every other lifecycle suite asserts for itself rather than inheriting.
send('PUT', '/api/delivery-providers/policy', { preferredProviderId: null }, merchant);
const riderSub = JSON.parse(Buffer.from(rider.split('.')[1], 'base64url').toString()).sub;
send('DELETE', `/api/delivery-providers/riders/${riderSub}`, null, back);

/** Places an order and drives it to DELIVERED, reporting the first step that refused. */
function deliverOrder() {
  const placed = send('POST', '/api/orders', {
    items: [{ productId: product.id, qty }],
    deliveryAddress: '12 Test Street, Flat 4',
    paymentMethod: 'CASH',
  }, customer);
  if (placed.code !== '201') return { error: `place: HTTP ${placed.code} ${placed.body.slice(0, 120)}` };
  const id = JSON.parse(placed.body).id;
  const steps = [['accept', merchant], ['prepare', merchant], ['ready', merchant],
                 ['claim', rider], ['pick-up', rider], ['deliver', rider]];
  for (const [step, tok] of steps) {
    const res = send('POST', `/api/orders/${id}/${step}`, null, tok);
    if (res.code !== '200') return { id, error: `${step}: HTTP ${res.code} ${res.body.slice(0, 120)}` };
  }
  return { id };
}

/**
 * Reviews an order, retrying while the projection catches up.
 *
 * reviewable_orders is written by product-service consuming order.delivered off the bus, so there
 * is a real gap between the rider tapping Delivered and the review being accepted. Retrying is the
 * honest way to test that — a fixed sleep is either flaky or slow, and usually both.
 */
function review(orderId, rating, comment, tok) {
  let res;
  for (let i = 0; i < 20; i++) {
    res = send('POST', `/api/stores/${store.id}/reviews`, { orderId, rating, comment }, tok);
    if (res.code !== '404') return res;
    sleep(500);
  }
  return res;
}

console.log('--- an order has to exist before it can be rated ---');
const invented = send('POST', `/api/stores/${store.id}/reviews`, { orderId: uuid(), rating: 5, comment: 'Mine' });
check('an invented order id is refused', invented.code === '404', `HTTP ${invented.code}`);

const a = deliverOrder();
check('an order reaches DELIVERED', !a.error, a.error ?? 'ok');
if (a.error) { console.log(`\n  ${pass} passed, ${fail} failed`); process.exit(1); }

console.log('--- rating ---');
const first = review(a.id, 4, 'Good', customer);
check('a delivered order can be reviewed', first.code === '201', `HTTP ${first.code}`);
let after = get(`/api/stores/${store.id}`);
check('the count goes up by one', after.ratingCount === baseCount + 1, `${after.ratingCount}`);
if (baseCount === 0) {
  check('the store rating becomes the review', Number(after.rating) === 4, `${after.rating}`);
}

const b = deliverOrder();
check('a second order reaches DELIVERED', !b.error, b.error ?? 'ok');
review(b.id, 5, 'Great', customer);
after = get(`/api/stores/${store.id}`);
check('the count goes up again', after.ratingCount === baseCount + 2, `${after.ratingCount}`);
if (baseCount === 0) {
  check('two reviews average', Number(after.rating) === 4.5, `${after.rating}`);
}

console.log('--- one review per order ---');
const revise = send('POST', `/api/stores/${store.id}/reviews`, { orderId: a.id, rating: 1, comment: 'Changed my mind' });
check('the same order revises rather than adds', revise.code === '201' || revise.code === '200', `HTTP ${revise.code}`);
after = get(`/api/stores/${store.id}`);
check('a revision does not change the count', after.ratingCount === baseCount + 2, `${after.ratingCount}`);

console.log('--- who may review what ---');
// The attack that needs no forged id: a genuine order of your own, aimed at a shop you never
// bought from. Refused on the store, not just on the order.
const otherStore = get('/api/stores?size=20').content.find(s => s.id !== store.id);
if (otherStore) {
  check('a real order cannot be aimed at another shop',
    send('POST', `/api/stores/${otherStore.id}/reviews`, { orderId: a.id, rating: 5 }).code === '404');
}
check('a merchant cannot review',
  send('POST', `/api/stores/${store.id}/reviews`, { orderId: a.id, rating: 5 }, merchant).code === '403');
check('a rating below one is refused',
  send('POST', `/api/stores/${store.id}/reviews`, { orderId: a.id, rating: 0 }).code === '400');
check('a rating above five is refused',
  send('POST', `/api/stores/${store.id}/reviews`, { orderId: a.id, rating: 6 }).code === '400');

console.log('--- reading ---');
const list = get(`/api/stores/${store.id}/reviews`);
check('reviews list', list.totalElements === baseCount + 2, `${list.totalElements}`);
const mine = send('GET', `/api/stores/reviews/order/${a.id}`);
check('a review can be looked up by order', mine.code === '200' && JSON.parse(mine.body).rating === 1);
check('an unreviewed order returns no content',
  send('GET', `/api/stores/reviews/order/${uuid()}`).code === '204');

console.log('--- withdrawing ---');
check('a review can be withdrawn', send('DELETE', `/api/stores/reviews/order/${a.id}`).code === '204');
send('DELETE', `/api/stores/reviews/order/${b.id}`);
after = get(`/api/stores/${store.id}`);
check('the count returns to where it started', after.ratingCount === baseCount, `${after.ratingCount}`);
if (baseCount === 0) {
  // Back to null, not 0 — "nobody has rated this" must stay distinct from "everybody rated it badly".
  check('removing the last review returns the rating to null', after.rating === null, `${after.rating}`);
}

console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
