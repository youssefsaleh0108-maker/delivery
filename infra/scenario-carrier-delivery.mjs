// An order carried by an outside company, and the money that follows it.
//
//   node infra/scenario-carrier-delivery.mjs dev
//
// THE SCENARIO. Most orders on this platform go to the in-house fleet. Some do not: a merchant can
// hand dispatch to a delivery company, and from that moment the order belongs to somebody else's
// business — it appears on THEIR board, one of THEIR riders carries it, and the settlement owes
// THEM a cut that the in-house case never produces.
//
//   1. The back office makes sure the company exists and can take work.
//   2. A rider joins that company. From now on the in-house board is not theirs.
//   3. The merchant pins dispatch to the company.
//   4. A customer orders. The merchant accepts, prepares, marks it ready — and only at READY does
//      dispatch choose, so this is where the order becomes the carrier's.
//   5. It appears on the CARRIER's own job list, and on their rider's board.
//   6. The rider carries it. The carrier's earnings move.
//   7. Settlement posts a PROVIDER_CREDIT leg — the leg an in-house delivery never has.
//
// WHY THE CLEANUP IS IN A `finally`. Three suites under infra/ already set this world up and put
// it back at the END OF THE FILE, unguarded. Any run that fails before the tail leaves the demo
// rider inside an external company while dispatch keeps routing to the in-house fleet — and from
// then on EVERY order on that environment reaches READY and stops, invisible to the only rider
// who can sign in. That is not hypothetical: it is the state dev was found in, and it is why no
// order could be delivered there. A scenario that arranges a shared environment has to hand it
// back whatever happens.
import { execSync } from 'node:child_process';

const ENV = process.argv[2] || 'dev';
const API = `https://api-${ENV}.youdrop.shop`;
const IAM = `https://iam-${ENV}.youdrop.shop`;

const IN_HOUSE = '00000000-0000-4000-8000-00000000d001';
const RUN = Date.now().toString(36).toUpperCase();

let pass = 0;
let fail = 0;
const ok = (what, detail = '') => { pass++; console.log(`  ok    ${what.padEnd(52)} ${detail}`); };
const bad = (what, detail = '') => { fail++; console.log(`  FAIL  ${what.padEnd(52)} ${detail}`); };

const signIn = async (user, password, client = 'mobile-app') => {
  const res = await fetch(`${IAM}/realms/delivery-platform/protocol/openid-connect/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: client, username: user, password, grant_type: 'password' }),
  });
  if (!res.ok) throw new Error(`sign in as ${user}: HTTP ${res.status}`);
  return (await res.json()).access_token;
};

const subOf = (token) =>
  JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()).sub;

const call = async (method, path, token, body) => {
  const res = await fetch(API + path, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { 'Content-Type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not json */ }
  return { code: res.status, ok: res.ok, json, text };
};

const need = (res, what) => {
  if (!res.ok) throw new Error(`${what}: HTTP ${res.code} ${res.text.slice(0, 200)}`);
  return res.json;
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const waitFor = async (attempt, seconds = 60) => {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    const value = await attempt();
    if (value) return value;
    await sleep(2000);
  }
  return null;
};

console.log(`\n=== an outside company carries an order on ${ENV} ===\n`);

const customer = await signIn('customer', '100001');
const merchant = await signIn('merchant', '200002');
const rider = await signIn('rider', '300003');
const carrier = await signIn('carrier', '500005');
const backoffice = await signIn('backoffice', '400004', 'delivery-portal');
const riderSub = subOf(rider);
ok('every role signs in');

let company = null;

try {
  // ---------------------------------------------------------------- 1. the company

  const providers = need(await call('GET', '/api/delivery-providers?size=50', backoffice),
    'listing providers');
  company = (providers.content ?? []).find((p) => p.id !== IN_HOUSE && p.canTakeWork);
  if (!company) {
    bad('no external carrier can take work',
      'dispatch has nobody but the in-house fleet to choose, so this scenario cannot run');
    throw new Error('no carrier');
  }
  ok('an external company can take work', `${company.name} (${company.slug})`);

  // ---------------------------------------------------------------- 2 & 3. crewing and pinning

  const joined = await call('POST', `/api/delivery-providers/${company.id}/riders`, backoffice,
    { riderRef: riderSub });
  joined.code === 204 || joined.ok
    ? ok('the rider joins that company', `HTTP ${joined.code}`)
    : bad('crewing the company', `HTTP ${joined.code} ${joined.text.slice(0, 140)}`);

  // Moving the rider is not enough on its own. Dispatch asks whoever the MERCHANT chose, so
  // without this the order still goes in-house and the rider — now working for somebody else —
  // cannot see it at all.
  const pinned = await call('PUT', '/api/delivery-providers/policy', merchant,
    { preferredProviderId: company.id });
  pinned.ok
    ? ok('the merchant hands dispatch to them')
    : bad('pinning the carrier', `HTTP ${pinned.code} ${pinned.text.slice(0, 140)}`);

  // ---------------------------------------------------------------- 4. an order, up to READY

  const store = (need(await call('GET', '/api/stores/mine', merchant), 'merchant shops')
    .content ?? [])[0];
  const product = (need(
    await call('GET', `/api/stores/${store.id}/products?size=50`, customer), 'shop products',
  ).content ?? [])[0];
  if (!product) {
    bad('the merchant shop has nothing to sell',
      'run the order-lifecycle scenario first — it publishes a fixture product');
    throw new Error('no product');
  }

  const order = need(await call('POST', '/api/orders', customer, {
    items: [{ productId: product.id, qty: 1 }],
    deliveryAddress: `Carrier run ${RUN}, Hamra, Beirut`,
    contactPhone: '+96170123456',
    paymentMethod: 'CASH',
  }), 'placing the order');
  ok('a customer orders', `${order.id.slice(0, 8)} · ${product.name}`);

  for (const action of ['accept', 'prepare', 'ready']) {
    need(await call('POST', `/api/orders/${order.id}/${action}`, merchant), `merchant ${action}`);
  }
  ok('the merchant works it to ready');

  // Dispatch runs at READY and not before, so this is the first moment the order has an owner.
  const routed = need(await call('GET', `/api/orders/${order.id}`, backoffice), 'reading it back');
  routed.deliveryProviderId === company.id
    ? ok('dispatch gave it to the company', company.name)
    : bad('dispatch did not route to the pinned carrier',
      `deliveryProviderId is ${routed.deliveryProviderId ?? 'null'}; if the company is paused or `
      + 'does not serve this merchant, chooseFor falls back and the pin is silently ignored');

  // ---------------------------------------------------------------- 5. whose board is it on?

  const onCarrierList = await waitFor(async () => {
    const list = await call('GET', '/api/orders/carrier?page=0&size=50', carrier);
    return (list.json?.content ?? []).some((o) => o.id === order.id) || null;
  }, 30);
  onCarrierList
    ? ok('it is on the carrier\'s own job list')
    : bad('the carrier cannot see the order they were given',
      'the company was handed the work and has no way to see it');

  const onRiderBoard = await waitFor(async () => {
    const board = await call('GET', '/api/orders/available?page=0&size=50', rider);
    return (board.json?.content ?? []).some((o) => o.id === order.id) || null;
  }, 30);
  onRiderBoard
    ? ok('and on their rider\'s board')
    : bad('the company\'s own rider cannot see it',
      'the board is scoped to the rider\'s fleet, so this means the membership did not take');

  // ---------------------------------------------------------------- 6 & 7. carried, and paid

  const before = (await call('GET', '/api/orders/carrier/earnings', carrier)).json;

  for (const action of ['claim', 'pick-up', 'deliver']) {
    const res = await call('POST', `/api/orders/${order.id}/${action}`, rider);
    res.ok ? null : bad(`rider ${action}`, `HTTP ${res.code} ${res.text.slice(0, 140)}`);
  }
  const delivered = need(await call('GET', `/api/orders/${order.id}`, backoffice), 'final read');
  delivered.status === 'DELIVERED'
    ? ok('their rider carries it to the door', delivered.status)
    : bad('the order did not reach DELIVERED', delivered.status);

  const legs = await waitFor(async () => {
    const res = await call('GET', `/api/accounting/orders/${order.id}`, backoffice);
    const rows = Array.isArray(res.json)
      ? res.json
      : (res.json?.transactions ?? res.json?.legs ?? []);
    return rows.length ? rows : null;
  }, 120);
  if (!legs) {
    bad('settlement posted nothing', 'the customer paid at the door and nobody was credited');
  } else {
    const names = legs.map((l) => `${l.leg}:${l.amount}`).join('  ');
    // The leg that only exists because somebody else did the carrying. Its absence would mean
    // the platform kept the delivery fee for work it did not do.
    legs.some((l) => l.leg === 'PROVIDER_CREDIT')
      ? ok('settlement credits the carrier', names)
      : bad('no PROVIDER_CREDIT leg', `${names} — the company carried this and was not paid`);
  }

  const after = (await call('GET', '/api/orders/carrier/earnings', carrier)).json;
  after
    ? ok('the carrier\'s earnings answer', JSON.stringify(after).slice(0, 140))
    : bad('carrier earnings', 'the company cannot see what it earned');
  if (before && after && JSON.stringify(before) === JSON.stringify(after)) {
    console.log('        (unchanged from before the delivery — worth a look if the fee was non-zero)');
  }
} catch (e) {
  bad('the scenario stopped early', e.message);
} finally {
  // ---------------------------------------------------------------- put the world back
  //
  // In a finally, because this is the whole point. Leaving the pin or the membership behind makes
  // every subsequent in-house order on this environment undeliverable, and the next person to
  // look will find a platform where orders reach READY and stop.
  console.log('\n--- putting the environment back ---');
  const unpinned = await call('PUT', '/api/delivery-providers/policy', merchant,
    { preferredProviderId: null });
  unpinned.ok
    ? ok('dispatch is back with the platform')
    : bad('could not unpin the merchant', `HTTP ${unpinned.code} — DO THIS BY HAND`);

  const released = await call('DELETE', `/api/delivery-providers/riders/${riderSub}`, backoffice);
  released.code === 204 || released.code === 404
    ? ok('the rider is back in the in-house fleet')
    : bad('could not release the rider', `HTTP ${released.code} — DO THIS BY HAND`);
}

console.log(`\n=== ${pass} passed, ${fail} failed ===\n`);
process.exit(fail ? 1 : 0);
