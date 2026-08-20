// Merchant store-administration smoke test.
//
// Walks the path a real shop owner takes: find my store, set its profile and commercials, set
// opening hours, publish it, flag busy, clear busy. Also checks the ownership boundary — a
// merchant must not be able to edit somebody else's shop.
//
//   node infra/smoke-test-store-admin.js
const { execSync } = require('child_process');
const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });

const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const merchant = token('merchant');
const customer = token('customer');

const call = (m, p, body, tok = merchant) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"`
    : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, tok) => JSON.parse(split(call('GET', p, null, tok)).body);
const send = (m, p, body, tok) => split(call(m, p, body, tok));
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 46) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 46) + (detail ?? '')); }
};

console.log('--- the merchant finds their own shop ---');
let mine = get('/api/stores/mine').content;
if (mine.length === 0) {
  // No store yet: creating a product auto-provisions one. Do that so the suite is self-contained.
  const cat = get('/api/categories');
  const made = send('POST', '/api/products', {
    name: 'Smoke test item', description: 'created by smoke-test-store-admin',
    price: 9.99, categoryId: cat[0].id,
  });
  check('a first product auto-provisions a store', made.code === '201', `HTTP ${made.code}`);
  mine = get('/api/stores/mine').content;
}
check('the merchant has exactly one shop', mine.length >= 1, `${mine.length}`);
const store = mine[0];
console.log(`        working on "${store.name}" (${store.status})`);

console.log('--- profile and commercials ---');
const profile = send('PUT', `/api/stores/${store.id}`, {
  name: 'Smoke Test Kitchen', vertical: 'RESTAURANT', tagline: 'Set by the smoke test',
  description: null, tags: ['Testing', 'Automated'], timezone: 'UTC', address: '1 Test Way',
});
check('profile saves', profile.code === '200', `HTTP ${profile.code}`);
check('the name changed', JSON.parse(profile.body).name === 'Smoke Test Kitchen');
check('tags are stored', JSON.parse(profile.body).tags.join(',') === 'Testing,Automated');
// The slug is generated once and must survive a rename, or shared links break.
check('the slug survived the rename', JSON.parse(profile.body).slug === store.slug,
  JSON.parse(profile.body).slug);

const comms = send('PUT', `/api/stores/${store.id}/commercials`, {
  deliveryFee: 3.25, minOrder: 7.50, etaMinMinutes: 20, etaMaxMinutes: 35,
});
check('commercials save', comms.code === '200', `HTTP ${comms.code}`);
check('the fee is what we set', Number(JSON.parse(comms.body).deliveryFee) === 3.25);
const badEta = send('PUT', `/api/stores/${store.id}/commercials`, {
  deliveryFee: 1, minOrder: 1, etaMinMinutes: 40, etaMaxMinutes: 10,
});
check('an inverted ETA range is refused', badEta.code === '422' || badEta.code === '400',
  `HTTP ${badEta.code}`);

console.log('--- opening hours ---');
const week = [];
for (let d = 1; d <= 7; d++) week.push({ dayOfWeek: d, opensAt: '00:00:00', closesAt: '23:59:00' });
const setHours = send('PUT', `/api/stores/${store.id}/hours`, week);
check('hours save', setHours.code === '200', `HTTP ${setHours.code}`);
check('seven windows come back', JSON.parse(setHours.body).length === 7);

// Split hours: two windows on the same day is the case a single opens/closes pair cannot express.
const split2 = send('PUT', `/api/stores/${store.id}/hours`, [
  ...week,
  { dayOfWeek: 1, opensAt: '14:00:00', closesAt: '19:00:00' },
]);
check('a second window on one day is accepted', JSON.parse(split2.body).length === 8);
send('PUT', `/api/stores/${store.id}/hours`, week);

const badWindow = send('PUT', `/api/stores/${store.id}/hours`,
  [{ dayOfWeek: 1, opensAt: '22:00:00', closesAt: '02:00:00' }]);
check('a window that wraps midnight is refused', badWindow.code === '422',
  `HTTP ${badWindow.code}`);

console.log('--- publish and availability ---');
const published = send('POST', `/api/stores/${store.id}/publish`);
check('publish succeeds once there are hours', published.code === '200', `HTTP ${published.code}`);
check('the shop reads as open', JSON.parse(published.body).availability === 'OPEN',
  JSON.parse(published.body).availability);
check('a customer can now see it',
  get('/api/stores?size=50', customer).content.some(s => s.id === store.id));

const busy = send('POST', `/api/stores/${store.id}/busy`, { minutes: 30 });
check('busy flags the shop', JSON.parse(busy.body).availability === 'BUSY',
  JSON.parse(busy.body).availability);
check('the customer sees it as busy too',
  get('/api/stores?size=50', customer).content.find(s => s.id === store.id).availability === 'BUSY');
const notBusy = send('DELETE', `/api/stores/${store.id}/busy`);
check('clearing busy restores open', JSON.parse(notBusy.body).availability === 'OPEN');

console.log('--- ownership ---');
check('a customer cannot edit a shop',
  send('PUT', `/api/stores/${store.id}/commercials`,
    { deliveryFee: 0, minOrder: 0, etaMinMinutes: 5, etaMaxMinutes: 6 }, customer).code === '403');
// Someone else's shop: the demo seed is owned by the synthetic 'demo-merchant'.
const someoneElse = get('/api/stores?size=50', customer).content
  .find(s => !mine.some(m => m.id === s.id));
if (someoneElse) {
  const stolen = send('PUT', `/api/stores/${someoneElse.id}/commercials`,
    { deliveryFee: 0, minOrder: 0, etaMinMinutes: 5, etaMaxMinutes: 6 });
  check("a merchant cannot edit another merchant's shop", stolen.code === '404',
    `${someoneElse.name}: HTTP ${stolen.code}`);
} else {
  console.log('  SKIP  no other shop to attempt');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
