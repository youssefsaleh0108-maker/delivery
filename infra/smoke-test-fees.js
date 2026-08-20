// Delivery-fee and minimum-order smoke test.
//
// Proves the three things that were only true in the app before: the fee is added server-side, the
// minimum is enforced server-side, and a closed shop refuses. Also checks the invariant the
// database now holds — subtotal + delivery_fee = total_amount.
//
//   node infra/smoke-test-fees.js
const { execSync } = require('child_process');
const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });

const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const cust = token('customer');
const call = (m, p, body, tok = cust) => {
  const data = body ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const get = (p, tok) => JSON.parse(call('GET', p, null, tok).split('~~')[0]);
const post = (p, body) => { const r = call('POST', p, body); const i = r.lastIndexOf('~~'); return { code: r.slice(i + 2).trim(), body: r.slice(0, i) }; };
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 48) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 48) + (detail ?? '')); }
};

const stores = get('/api/stores?size=30').content;
const itemsOf = (storeId, count) => get(`/api/stores/${storeId}/products?size=50`).content.slice(0, count);
const place = (lines) => post('/api/orders', {
  items: lines, deliveryAddress: '12 Test Street', contactPhone: null, notes: null,
});

// Shops are picked by their current state, never by name. Availability is derived from the clock,
// so a suite that hardcodes "Fresh Market" passes in the afternoon and fails at 4am.
//
// The shop also has to stock something cheaper than its own minimum, or the "under the minimum is
// refused" case cannot be built at all — a suite that silently tests nothing is worse than one
// that fails.
const openWithMinimum = stores
  .filter(s => s.availability !== 'CLOSED' && s.minOrder > 0)
  .find(s => {
    const items = itemsOf(s.id, 50);
    return items.length > 0 && Math.min(...items.map(p => p.price)) < s.minOrder;
  });
const closedStore = stores.find(s => s.availability === 'CLOSED');
if (!openWithMinimum) {
  console.error('No open store with a minimum above its cheapest item; cannot run the fee checks.');
  process.exit(1);
}

console.log(`--- the fee is added server-side (${openWithMinimum.name}, `
  + `fee ${openWithMinimum.deliveryFee}, min ${openWithMinimum.minOrder}) ---`);
const fresh = openWithMinimum;
const cheap = itemsOf(fresh.id, 50);
// Build a basket that just clears this shop's minimum, whatever it happens to be.
let picked = [], running = 0;
for (const p of cheap) { if (running > fresh.minOrder) break; picked.push(p); running += p.price; }
running = Number(running.toFixed(2));
const ok = place(picked.map(p => ({ productId: p.id, qty: 1 })));
check('order is accepted over the minimum', ok.code === '201', `HTTP ${ok.code}`);
const order = JSON.parse(ok.body);
check('subtotal is the goods only', Math.abs(order.subtotal - running) < 0.001, `${order.subtotal}`);
check('delivery fee came from the store', Number(order.deliveryFee) === fresh.deliveryFee, `${order.deliveryFee}`);
check('total is subtotal + fee',
  Math.abs(order.totalAmount - (order.subtotal + order.deliveryFee)) < 0.001,
  `${order.subtotal} + ${order.deliveryFee} = ${order.totalAmount}`);
check('the shop is snapshotted', order.storeName === fresh.name && order.storeId === fresh.id,
  order.storeName);

console.log('--- the minimum is enforced server-side ---');
const oneCheapItem = cheap.reduce((a, b) => (a.price <= b.price ? a : b));
const under = place([{ productId: oneCheapItem.id, qty: 1 }]);
check('a basket under the minimum is refused', under.code === '422', `HTTP ${under.code} on ${oneCheapItem.price}`);
check('the refusal explains why', /minimum/i.test(under.body), (under.body.match(/"detail":"([^"]*)"/) || [])[1] || '');

console.log('--- a closed shop refuses ---');
if (closedStore) {
  const flowers = itemsOf(closedStore.id, 1);
  const shut = place([{ productId: flowers[0].id, qty: 1 }]);
  check(`ordering from a closed shop is refused`, shut.code === '422',
    `${closedStore.name}: HTTP ${shut.code}`);
  check('the refusal says the shop is closed', /closed/i.test(shut.body),
    (shut.body.match(/"detail":"([^"]*)"/) || [])[1] || '');
} else {
  console.log('  SKIP  every shop is open at this hour');
}

console.log('--- the client cannot set its own fee ---');
const forged = post('/api/orders', {
  items: picked.map(p => ({ productId: p.id, qty: 1 })),
  deliveryAddress: '12 Test Street', contactPhone: null, notes: null,
  deliveryFee: 0, subtotal: 0, totalAmount: 0,
});
check('a forged fee in the body is ignored', forged.code === '201'
  && Number(JSON.parse(forged.body).deliveryFee) === fresh.deliveryFee,
  `fee stayed ${forged.code === '201' ? JSON.parse(forged.body).deliveryFee : '?'}`);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
