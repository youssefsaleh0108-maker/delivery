// Store logo/cover upload smoke test.
//
// Walks the real three-step flow — presign, PUT the bytes straight to MinIO, confirm — and then
// checks the picture actually reaches a customer browsing the storefront, which is the whole point.
//
//   node infra/smoke-test-store-images.js
const { execSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
/** Status code of a bare curl. Never use -o /dev/null with -w here: curl exits 23 on this shell. */
const status = (c) => sh(c + ' -w "~~%{http_code}"').split('~~').pop().trim();
const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const merchant = token('merchant');
const customer = token('customer');
const call = (m, p, body, tok = merchant) => {
  const data = body ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
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

/** A real 8x8 PNG, built here so the suite carries no binary fixture. */
function png() {
  const w = 8, h = 8;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  let o = 0;
  for (let y = 0; y < h; y++) {
    raw[o++] = 0;                       // filter: none
    for (let x = 0; x < w; x++) { raw[o++] = 0xd3; raw[o++] = 0x2f; raw[o++] = 0x2f; }
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2; // 8-bit, truecolour
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return crc ^ 0xffffffff;
}

const stores = get('/api/stores/mine').content;
if (stores.length === 0) {
  console.error('The merchant has no store; run smoke-test-store-admin.js first.');
  process.exit(1);
}
const store = stores[0];
console.log(`--- uploading to "${store.name}" ---`);

const file = path.join(os.tmpdir(), 'delivery-smoke-logo.png');
fs.writeFileSync(file, png());

for (const slot of ['logo', 'cover']) {
  const presigned = send('POST', `/api/stores/${store.id}/images/${slot}/presign`,
    { contentType: 'image/png' });
  check(`${slot}: presign returns a URL`, presigned.code === '201', `HTTP ${presigned.code}`);
  const upload = JSON.parse(presigned.body);
  check(`${slot}: key is namespaced to the store`,
    upload.objectKey.includes(`stores/${store.id}/${slot}`), upload.objectKey);

  // Step 2: straight to MinIO. No Authorization header — a presigned URL carries its own, and
  // S3-compatible storage rejects a request presenting both.
  const put = status(`curl -s -X PUT --data-binary "@${file}" -H "Content-Type: image/png" "${upload.uploadUrl}"`);
  check(`${slot}: bytes upload straight to storage`, put === '200', `HTTP ${put}`);

  const confirmed = send('POST', `/api/stores/${store.id}/images/${slot}/${upload.fileId}/confirm`);
  check(`${slot}: confirm attaches it`, confirmed.code === '200', `HTTP ${confirmed.code}`);
  const url = JSON.parse(confirmed.body)[`${slot}Url`];
  check(`${slot}: the store now has a ${slot}Url`, !!url, url ? url.split('?')[0] : 'null');

  // The URL must actually serve the bytes — a reference to an object that 404s is worse than none.
  if (url) {
    const fetched = status(`curl -s "${url}"`);
    check(`${slot}: the URL serves the image`, fetched === '200', `HTTP ${fetched}`);
  }
}

console.log('--- the customer sees it ---');
const card = get('/api/stores?size=50', customer).content.find(s => s.id === store.id);
check('the storefront card carries the logo', !!card && !!card.logoUrl,
  card && card.logoUrl ? 'present' : 'missing');
check('the storefront card carries the cover', !!card && !!card.coverUrl,
  card && card.coverUrl ? 'present' : 'missing');
const searched = get(`/api/stores?search=${encodeURIComponent(store.name.split(' ')[0])}`, customer);
check('a search result carries the logo',
  searched.content.some(s => s.id === store.id && !!s.logoUrl),
  `${searched.totalElements} result(s)`);

console.log('--- ownership ---');
check('a customer cannot presign for a shop',
  send('POST', `/api/stores/${store.id}/images/logo/presign`,
    { contentType: 'image/png' }, customer).code === '403');
const other = get('/api/stores?size=50', customer).content.find(s => s.id !== store.id);
if (other) {
  check("a merchant cannot upload to another merchant's shop",
    send('POST', `/api/stores/${other.id}/images/logo/presign`,
      { contentType: 'image/png' }).code === '404', other.name);
}
check('an unknown slot is rejected',
  send('POST', `/api/stores/${store.id}/images/banner/presign`,
    { contentType: 'image/png' }).code === '422');

console.log('--- removal ---');
const removed = send('DELETE', `/api/stores/${store.id}/images/cover`);
check('cover can be removed', removed.code === '200' && !JSON.parse(removed.body).coverUrl);
check('the logo is untouched by removing the cover', !!JSON.parse(removed.body).logoUrl);

fs.unlinkSync(file);
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
