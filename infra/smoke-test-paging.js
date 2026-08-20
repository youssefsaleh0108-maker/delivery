// Paging smoke test.
//
// Every list endpoint must return a page, honour page/size, and report totals a client can page
// against. The failure this guards is not a 500 — it is an endpoint quietly returning a whole
// collection, which works fine with eight rows of demo data and falls over with eight thousand.
//
//   node infra/smoke-test-paging.js
const { execSync } = require('child_process');
const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });

const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const customer = token('customer');
const merchant = token('merchant');
const get = (p, tok = customer) =>
  JSON.parse(sh(`curl -s -H "Authorization: Bearer ${tok}" "http://127.0.0.1:8100${p}"`));
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 50) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 50) + (detail ?? '')); }
};

/** A paged envelope, not a bare array. */
function isPage(body) {
  return body !== null && typeof body === 'object' && !Array.isArray(body)
    && Array.isArray(body.content)
    && typeof body.page === 'number'
    && typeof body.totalElements === 'number'
    && typeof body.totalPages === 'number';
}

console.log('--- every list endpoint returns a page ---');
const paged = [
  ['/api/stores?size=3', customer],
  ['/api/stores/favorites?size=3', customer],
  ['/api/stores/offers?size=3', customer],
  ['/api/stores/mine?size=3', merchant],
];
for (const [path, tok] of paged) {
  const body = get(path, tok);
  check(`${path.split('?')[0]} is paged`, isPage(body),
    isPage(body) ? `${body.content.length}/${body.totalElements}` : 'bare array');
}

const store = get('/api/stores?size=50').content.find(s => s.name === 'Fresh Market')
  || get('/api/stores?size=50').content[0];
for (const path of [`/api/stores/${store.id}/products?size=3`, `/api/stores/${store.id}/offers?size=3`]) {
  const body = get(path);
  check(`${path.split('?')[0].replace(store.id, '{id}')} is paged`, isPage(body),
    isPage(body) ? `${body.content.length}/${body.totalElements}` : 'bare array');
}

console.log('--- size is honoured and pages do not overlap ---');
const all = get(`/api/stores/${store.id}/products?size=100`);
check('the shelf has enough rows to page', all.totalElements >= 4, `${all.totalElements} products`);

const p0 = get(`/api/stores/${store.id}/products?page=0&size=2`);
const p1 = get(`/api/stores/${store.id}/products?page=1&size=2`);
check('size=2 returns 2', p0.content.length === 2, `${p0.content.length}`);
check('page 0 and page 1 are different rows',
  p0.content.every(a => !p1.content.some(b => b.id === a.id)),
  `${p0.content.map(x => x.name).join(', ')} | ${p1.content.map(x => x.name).join(', ')}`);
check('totalElements is the whole shelf, not the page',
  p0.totalElements === all.totalElements, `${p0.totalElements} vs ${all.totalElements}`);
check('totalPages reflects the page size',
  p0.totalPages === Math.ceil(all.totalElements / 2), `${p0.totalPages}`);

// Walking every page must reconstruct the whole list exactly — no gaps, no repeats. This is what a
// client's infinite scroll actually does.
const walked = [];
for (let page = 0; page < p0.totalPages; page++) {
  walked.push(...get(`/api/stores/${store.id}/products?page=${page}&size=2`).content.map(x => x.id));
}
check('walking every page yields each row exactly once',
  walked.length === all.totalElements && new Set(walked).size === all.totalElements,
  `${walked.length} rows, ${new Set(walked).size} distinct`);

console.log('--- a page past the end is empty, not an error ---');
const beyond = get(`/api/stores/${store.id}/products?page=999&size=2`);
check('page 999 returns an empty page', isPage(beyond) && beyond.content.length === 0,
  `${beyond.content.length} rows`);

console.log('--- the ids filter (Buy Again) ---');
const wanted = all.content.slice(0, 2).map(p => p.id);
const byIds = get(`/api/stores/${store.id}/products?ids=${wanted.join(',')}&size=20`);
check('ids restricts the page', byIds.totalElements === 2, `${byIds.totalElements}`);
check('ids returns exactly what was asked for',
  byIds.content.every(p => wanted.includes(p.id)));
// Store-scoped as well as id-scoped: an id from another shop must not come back.
const otherStore = get('/api/stores?size=50').content.find(s => s.id !== store.id);
const foreign = get(`/api/stores/${otherStore.id}/products?size=1`).content[0];
if (foreign) {
  const leak = get(`/api/stores/${store.id}/products?ids=${foreign.id}&size=20`);
  check('an id from another shop is not returned', leak.totalElements === 0,
    `${leak.totalElements} from ${otherStore.name}`);
}

console.log('--- filters survive paging ---');
const groceries = get('/api/stores?vertical=GROCERY&page=0&size=2');
check('a filtered page still filters',
  groceries.content.every(s => s.vertical === 'GROCERY'), `${groceries.totalElements} total`);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
