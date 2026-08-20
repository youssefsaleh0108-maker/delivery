// Storefront smoke test: the Store domain, filters, aisles, offers and favourites, end to end
// through the API Gateway.
//
// Node rather than the curl+jq-in-a-container pattern the other six suites use, because this one
// asserts on relationships between responses (aisle counts summing to the shelf, a favourite
// showing up on a later card) rather than on single field values, and that is painful in jq.
// Runs on the host against the loopback ports.
//
//   node infra/smoke-test-storefront.js
//
// Exits non-zero on the first failure count, so it is CI-usable as-is.
const { execSync } = require('child_process');
const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });

const tok = JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ' -d "client_id=mobile-app" -d "username=customer" -d "password=customer"'
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

// "~~" rather than a newline: a literal \n inside -w does not survive shell quoting on Windows.
const call = (m, p) => sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}" "http://127.0.0.1:8100${p}"`);
const get = (p) => JSON.parse(call('GET', p).split('~~')[0]);
const code = (m, p) => call(m, p).split('~~').pop().trim();
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 44) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 44) + (detail ?? '')); }
};

console.log('--- storefront ---');
const all = get('/api/stores?size=30');
check('lists stores', all.totalElements >= 10, `${all.totalElements} stores`);
// The invariant V13 restored is "every listed store has hours", not "every store is open right
// now" — availability is derived from the clock, so asserting on it made this check pass in the
// afternoon and fail at 4am. A listed store with no hours can never open, which is the real bug.
const hourless = all.content.filter(s => get(`/api/stores/${s.id}/hours`).length === 0);
check('every listed store has opening hours', hourless.length === 0,
  hourless.map(s => s.name).join(', ') || 'V13');
const states = [...new Set(all.content.map(s => s.availability))].sort();
check('renders several availability states', states.length >= 2, states.join(','));

console.log('--- filters ---');
const groc = get('/api/stores?vertical=GROCERY');
check('vertical filter', groc.content.every(s => s.vertical === 'GROCERY'), groc.content.map(s => s.name).join(', '));
const pizz = get('/api/stores?search=pizz');
check('search filter', pizz.totalElements > 0 && pizz.content.every(s => /pizz/i.test(s.name)), pizz.content.map(s => s.name).join(', '));
const rated = get('/api/stores?minRating=4.7');
check('rating filter', rated.content.every(s => s.rating >= 4.7), `${rated.totalElements} at 4.7+`);
const quick = get('/api/stores?maxEtaMinutes=30');
check('eta filter', quick.content.every(s => s.etaMaxMinutes <= 30), `${quick.totalElements} under 30min`);
check('search escapes wildcards', get('/api/stores?search=%25').totalElements === 0, 'literal % matches nothing');

console.log('--- store page ---');
const fresh = all.content.find(s => s.name === 'Fresh Market');
check('read by slug', get('/api/stores/fresh-market').id === fresh.id, 'fresh-market');
const store = get(`/api/stores/${fresh.id}`);
check('read by id', store.name === 'Fresh Market', `closesAt=${store.closesAt}`);
const prods = get(`/api/stores/${fresh.id}/products?size=100`);
check('shelf products', prods.totalElements === 14, `${prods.totalElements} products`);
check('products carry storeId', prods.content.every(p => p.storeId === fresh.id));
const aisles = get(`/api/stores/${fresh.id}/aisles`);
check('aisles derived from stock', aisles.length === 5, aisles.map(a => `${a.name}(${a.productCount})`).join(' '));
check('aisle counts sum to the shelf', aisles.reduce((a, x) => a + x.productCount, 0) === prods.totalElements);
const narrowed = get(`/api/stores/${fresh.id}/products?categoryId=${aisles[0].categoryId}`);
check('aisle filter narrows the shelf', narrowed.totalElements === aisles[0].productCount,
  `${aisles[0].name} -> ${narrowed.totalElements}`);
const hours = get(`/api/stores/${fresh.id}/hours`);
check('hours load outside the tx', hours.length === 7, `${hours.length} windows`);
const roast = get('/api/stores/roast-and-co');
check('split hours kept as separate windows', get(`/api/stores/${roast.id}/hours`).length === 14, '2 per day');

console.log('--- offers ---');
const platform = get('/api/stores/offers');
check('platform-wide offers', platform.content.length > 0 && platform.content.every(o => o.storeId === null), platform.content.map(o => o.title).join(', '));
const fo = get(`/api/stores/${fresh.id}/offers`).content;
check('store offers include platform-wide', fo.length === 2, fo.map(o => o.title).join(', '));

console.log('--- favourites ---');
check('star is 204', code('PUT', `/api/stores/${fresh.id}/favorite`) === '204');
check('star is idempotent', code('PUT', `/api/stores/${fresh.id}/favorite`) === '204', 'second call');
check('favourites list contains it', get('/api/stores/favorites').content.some(s => s.id === fresh.id));
check('card reflects favourite', get('/api/stores?search=Fresh').content[0].favorite === true);
check('unstar is 204', code('DELETE', `/api/stores/${fresh.id}/favorite`) === '204');
check('unstar is idempotent', code('DELETE', `/api/stores/${fresh.id}/favorite`) === '204', 'second call');
check('favourites list drops it', !get('/api/stores/favorites').content.some(s => s.id === fresh.id));

console.log('--- authorisation ---');
check('customer cannot list merchant stores', code('GET', '/api/stores/mine') === '403');
check('unknown store is 404', code('GET', '/api/stores/does-not-exist') === '404');
// No -o /dev/null: combined with -w it makes curl exit 23 (write error) on this shell, which
// execSync turns into a thrown error even though the status code came back fine.
check('anonymous is refused',
  sh('curl -s -w "~~%{http_code}" "http://127.0.0.1:8100/api/stores"').split('~~').pop().trim() === '401');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
