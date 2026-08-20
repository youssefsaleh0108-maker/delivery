// Gives the demo carrier account a company and some work, so the carrier app opens on something.
//
//   node infra/seed-carrier-demo.js
//
// Without this the app is correct and useless: the `carrier` account belongs to no company, every
// screen answers "you are not a member of any delivery company", and it looks broken to anybody
// opening it for the first time.
//
// Idempotent — safe to run whenever the local stack looks empty. It reuses the demo company if it
// is already there rather than registering a second one.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';
const SLUG = 'demo-couriers';

const sh = (c) => { try { return execSync(c, { encoding: 'utf8', maxBuffer: 2e7 }); } catch (e) { return e.stdout || ''; } };
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const backoffice = token('backoffice');
const carrier = token('carrier');
const merchant = token('merchant');
const rider = token('rider');
const customer = token('customer');
const subOf = (jwt) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64').toString('utf8')).sub;

const call = (m, p, body, tok) => {
  const auth = tok ? ` -H "Authorization: Bearer ${tok}"` : '';
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}"${auth}${data} "${GW}${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, p, b, t));
const get = (p, t) => JSON.parse(send('GET', p, null, t).body);

// ---------------------------------------------------------------- the company
let company = (get('/api/delivery-providers?size=200', backoffice).content || [])
  .find((p) => p.slug === SLUG);

if (!company) {
  const made = send('POST', '/api/delivery-providers', {
    slug: SLUG, name: 'Demo Couriers', contactName: 'Dana', contactPhone: '+9611000111',
    accountRef: 'ACC-CARRIER',
  }, backoffice);
  if (made.code !== '201') {
    console.error('Could not register the demo company:', made.code, made.body.slice(0, 200));
    process.exit(1);
  }
  company = JSON.parse(made.body);
  console.log(`registered ${company.name}`);
} else {
  console.log(`reusing ${company.name}`);
}

// The carrier RUNS it; the rider CARRIES for it. Two different memberships, and only the second is
// what dispatch and claim consult — attaching a rider to /staff looks fine and then 404s on claim.
send('POST', `/api/delivery-providers/${company.id}/staff`, { riderRef: subOf(carrier) }, backoffice);
send('POST', `/api/delivery-providers/${company.id}/riders`, { riderRef: subOf(rider) }, backoffice);
console.log('attached the carrier account and a rider');

// ---------------------------------------------------------------- some work to look at
const store = get('/api/stores/mine', merchant).content.find((s) => s.availability !== 'CLOSED');
const item = store
  ? (get('/api/products/mine?size=50', merchant).content || [])
      .find((p) => p.storeId === store.id && p.status === 'ACTIVE'
        && get(`/api/whatsapp/drafts/products/${p.id}/options`, merchant).every((g) => !g.required))
  : null;

if (!item) {
  console.log('no option-free product to order; the app will open on an empty job list');
  console.log('run infra/smoke-test-store-admin.js first if you want jobs in it');
} else {
  const previousPolicy = get('/api/delivery-providers/policy', merchant);
  send('PUT', '/api/delivery-providers/policy',
    { preferredProviderId: company.id, allowFallback: false }, merchant);

  // Three delivered so Earnings has a number, one in flight so Jobs has something live.
  let made = 0;
  for (let i = 0; i < 4; i++) {
    const placed = send('POST', '/api/orders', {
      items: [{ productId: item.id, qty: 1 }],
      deliveryAddress: `Hamra, building ${12 + i}, 3rd floor`,
      paymentMethod: 'CASH',
    }, customer);
    if (placed.code !== '201') continue;
    const order = JSON.parse(placed.body);
    send('POST', `/api/orders/${order.id}/accept`, null, merchant);
    send('POST', `/api/orders/${order.id}/prepare`, null, merchant);
    send('POST', `/api/orders/${order.id}/ready`, null, merchant);
    send('POST', `/api/orders/${order.id}/claim`, null, rider);
    send('POST', `/api/orders/${order.id}/pick-up`, null, rider);
    // The last one is left mid-delivery, so the app shows both states rather than a uniform list.
    if (i < 3) send('POST', `/api/orders/${order.id}/deliver`, null, rider);
    made++;
  }
  console.log(`created ${made} jobs (${Math.max(0, made - 1)} delivered, 1 on the road)`);

  // The pin was for seeding only; dispatch goes back to deciding on merit.
  send('PUT', '/api/delivery-providers/policy', {
    preferredProviderId: previousPolicy.preferredProviderId,
    allowFallback: previousPolicy.allowFallback ?? true,
  }, merchant);
}

const earnings = get('/api/orders/carrier/earnings', carrier);
console.log(`\n${company.name}: ${earnings.delivered} delivered, ${earnings.active} in flight, `
  + `${earnings.earned} earned, ${earnings.expected} expected`);
console.log('Carrier app: http://127.0.0.1:5013  (sign in as carrier / carrier)');
