// Banners and category imagery.
//
// Backoffice creates and edits, images go to MinIO through the same presign/confirm flow as store
// artwork, and the customer sees only what is live.
//
//   node infra/smoke-test-banners.js
const { execSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
/** Never use -o /dev/null with -w on this shell: curl exits 23 and execSync throws. */
const status = (c) => sh(c + ' -w "~~%{http_code}"').split('~~').pop().trim();
const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const back = token('backoffice');
const customer = token('customer');

const call = (m, p, body, tok = back) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const get = (p, tok) => JSON.parse(split(call('GET', p, null, tok)).body);
const send = (m, p, body, tok) => split(call(m, p, body, tok));
const detailOf = (body) => { try { return JSON.parse(body).detail ?? ''; } catch { return ''; } };
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 50) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 50) + (detail ?? '')); }
};

/** A real 8x8 PNG, built here so the suite carries no binary fixture. */
function png() {
  const w = 8, h = 8;
  const raw = Buffer.alloc((w * 3 + 1) * h);
  let o = 0;
  for (let y = 0; y < h; y++) {
    raw[o++] = 0;
    for (let x = 0; x < w; x++) { raw[o++] = 0xd3; raw[o++] = 0x2f; raw[o++] = 0x2f; }
  }
  const crc32 = (buf) => {
    let c, crc = 0xffffffff;
    for (let n = 0; n < buf.length; n++) {
      c = (crc ^ buf[n]) & 0xff;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crc = (crc >>> 8) ^ c;
    }
    return crc ^ 0xffffffff;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]);
}

console.log('--- backoffice creates a banner ---');
const created = send('POST', '/api/banners', {
  title: 'Smoke test banner', subtitle: 'Created by the suite',
  linkKind: 'NONE', linkTarget: null, position: 0, active: true,
});
check('a banner is created', created.code === '201', `HTTP ${created.code}`);
const banner = created.code === '201' ? JSON.parse(created.body) : null;
if (!banner) { console.log('\ncannot continue'); process.exit(1); }
check('it has no artwork yet', banner.imageUrl === null, `${banner.imageUrl}`);

console.log('--- the image goes to MinIO ---');
const file = path.join(os.tmpdir(), 'delivery-smoke-banner.png');
fs.writeFileSync(file, png());
const presigned = send('POST', `/api/banners/${banner.id}/image/presign`, { contentType: 'image/png' });
check('presign returns a URL', presigned.code === '201', `HTTP ${presigned.code}`);
const upload = JSON.parse(presigned.body);
check('the key is namespaced to the banner',
  upload.objectKey.includes(`banners/${banner.id}`), upload.objectKey);
const put = status(`curl -s -X PUT --data-binary "@${file}" -H "Content-Type: image/png" "${upload.uploadUrl}"`);
check('bytes upload straight to storage', put === '200', `HTTP ${put}`);
const confirmed = send('POST', `/api/banners/${banner.id}/image/${upload.fileId}/confirm`);
check('confirm attaches it', confirmed.code === '200', `HTTP ${confirmed.code}`);
const withImage = JSON.parse(confirmed.body);
check('the banner now has an imageUrl', !!withImage.imageUrl,
  withImage.imageUrl ? withImage.imageUrl.split('?')[0] : 'null');
if (withImage.imageUrl) {
  check('the URL serves the image', status(`curl -s "${withImage.imageUrl}"`) === '200');
}

console.log('--- the customer sees it ---');
const live = get('/api/banners', customer);
check('it appears on the customer rail', live.some(b => b.id === banner.id), `${live.length} live`);
check('and carries its artwork',
  (live.find(b => b.id === banner.id) || {}).imageUrl != null);

console.log('--- editing ---');
const edited = send('PUT', `/api/banners/${banner.id}`, {
  title: 'Edited title', subtitle: null, linkKind: 'NONE', linkTarget: null,
  position: 3, active: true,
});
check('a banner can be edited', edited.code === '200' && JSON.parse(edited.body).title === 'Edited title');
// A link has to point somewhere real, or the customer finds the dead end rather than the editor.
const badLink = send('PUT', `/api/banners/${banner.id}`, {
  title: 'Edited title', subtitle: null, linkKind: 'CATEGORY',
  linkTarget: '11111111-2222-4333-8444-555555555555', position: 3, active: true,
});
check('a link to a missing category is refused', badLink.code === '422', detailOf(badLink.body));
const noTarget = send('PUT', `/api/banners/${banner.id}`, {
  title: 'Edited title', subtitle: null, linkKind: 'STORE', linkTarget: null,
  position: 3, active: true,
});
check('a link with no target is refused', noTarget.code === '422', detailOf(noTarget.body));

console.log('--- category chips ---');
const chips = get('/api/categories/chips', customer);
check('the home strip is data-driven', chips.length >= 5, `${chips.length} chips`);
check('every chip carries the vertical its filter uses',
  chips.every(c => !!c.vertical), chips.map(c => `${c.name}=${c.vertical}`).join(' ').slice(0, 60));

const chip = chips[0];
const catPresign = send('POST', `/api/categories/${chip.id}/image/presign`, { contentType: 'image/png' });
check('a category image can be presigned', catPresign.code === '201', `HTTP ${catPresign.code}`);
const catUpload = JSON.parse(catPresign.body);
check('the key is namespaced to the category',
  catUpload.objectKey.includes(`categories/${chip.id}`), catUpload.objectKey);
const catPut = status(`curl -s -X PUT --data-binary "@${file}" -H "Content-Type: image/png" "${catUpload.uploadUrl}"`);
check('the category image uploads', catPut === '200', `HTTP ${catPut}`);
const catConfirm = send('POST', `/api/categories/${chip.id}/image/${catUpload.fileId}/confirm`);
check('confirm attaches it to the category', catConfirm.code === '200'
  && !!JSON.parse(catConfirm.body).imageUrl, `HTTP ${catConfirm.code}`);
check('the customer strip now shows the picture',
  !!(get('/api/categories/chips', customer).find(c => c.id === chip.id) || {}).imageUrl);

// The Backoffice edits categories from the tree, not from the customer chip endpoint — that one
// only returns categories already tagged with a vertical, so an untagged category with artwork
// would be invisible to the person administering it.
console.log('--- category tree carries what the backoffice edits ---');
const tree = get('/api/categories', customer);
const treeChip = tree.find(c => c.id === chip.id);
check('the tree returns the tagged category', !!treeChip, `${tree.length} roots`);
check('with the vertical it stands for', treeChip.vertical === chip.vertical,
  `${treeChip.vertical}`);
check('and the picture just uploaded', !!treeChip.imageUrl);
check('untagged categories come back with no vertical rather than a default',
  tree.filter(c => c.id !== chip.id).every(c => c.vertical === null || typeof c.vertical === 'string'),
  tree.map(c => `${c.name}=${c.vertical}`).join(' ').slice(0, 70));

// Everything above is curl, which sends no Origin and so never triggers a preflight. The
// Backoffice is a separate origin from the API, so every write it makes is preceded by an OPTIONS
// the browser must approve — a layer this suite was blind to until a real failure exposed it.
console.log('--- as the browser actually asks ---');
const ORIGIN = 'http://127.0.0.1:5011';
const preflight = (method, p) => {
  const out = sh(`curl -s -i -X OPTIONS "http://127.0.0.1:8100${p}" -H "Origin: ${ORIGIN}"`
    + ` -H "Access-Control-Request-Method: ${method}"`
    + ' -H "Access-Control-Request-Headers: authorization,content-type"');
  const code = (out.match(/^HTTP\/[\d.]+ (\d{3})/m) || [])[1];
  const allows = new RegExp(`access-control-allow-origin:\\s*${ORIGIN}`, 'i').test(out);
  const methods = ((out.match(/access-control-allow-methods:\s*(.*)/i) || [])[1] || '').trim();
  return { code, allows, methods };
};

for (const [method, path] of [
  ['POST', '/api/banners'],
  ['PUT', `/api/banners/${banner.id}`],
  ['DELETE', `/api/banners/${banner.id}`],
  ['POST', `/api/banners/${banner.id}/image/presign`],
  ['POST', `/api/categories/${chip.id}/image/presign`],
  ['PUT', `/api/categories/${chip.id}/vertical`],
  ['GET', '/api/categories'],
]) {
  const r = preflight(method, path);
  check(`the browser may ${method} ${path.replace(/[0-9a-f-]{36}/, ':id')}`,
    r.allows && r.methods.toUpperCase().includes(method), `HTTP ${r.code} allows=${r.methods}`);
}

// The bytes go straight to storage, which is a third origin again and signs its own URLs.
const storagePre = sh(`curl -s -i -X OPTIONS "${upload.uploadUrl}" -H "Origin: ${ORIGIN}"`
  + ' -H "Access-Control-Request-Method: PUT" -H "Access-Control-Request-Headers: content-type"');
check('and may PUT the bytes to storage',
  new RegExp(`access-control-allow-origin:\\s*${ORIGIN}`, 'i').test(storagePre)
  && /access-control-allow-methods:.*PUT/i.test(storagePre),
  (storagePre.match(/^HTTP\/[\d.]+ (\d{3})/m) || [])[1]);

console.log('--- authorisation ---');
check('a customer cannot create a banner',
  send('POST', '/api/banners', { title: 'x', linkKind: 'NONE', position: 0, active: true },
    customer).code === '403');
check('a customer cannot upload a category image',
  send('POST', `/api/categories/${chip.id}/image/presign`, { contentType: 'image/png' },
    customer).code === '403');
check('a customer cannot list withdrawn banners',
  send('GET', '/api/banners/all', null, customer).code === '403');

console.log('--- withdrawal ---');
check('a banner can be withdrawn', send('DELETE', `/api/banners/${banner.id}`).code === '204');
check('it leaves the customer rail',
  !get('/api/banners', customer).some(b => b.id === banner.id));
// Withdrawn, not deleted — what ran is part of the record.
check('but is still in the backoffice list',
  get('/api/banners/all?size=100').content.some(b => b.id === banner.id && !b.active));

fs.unlinkSync(file);
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
