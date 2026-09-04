// Fetches real, freely-licensed photographs for the demo storefront from Wikimedia Commons —
// a cover per shop and a photo per product — into a directory shaped like the product-images
// bucket keys:
//
//   node infra/fetch-shop-photos.js <catalog.json> <outdir>
//
// catalog.json: { "stores": [{id, slug, vertical}], "products": [{id, name, vertical}] }
//
// Commons rather than a stock-photo API because it needs no key and its files are freely
// licensed (public domain and Creative Commons). This is a dev seed; a production catalogue is
// merchant photography uploaded through the app. Items with no usable match are simply skipped —
// the flat-art tile already in place stays, which beats a wrong photograph.
'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');

const UA = 'YouDropDevSeeder/1.0 (dev catalogue; youssef.saleh0108@gmail.com)';

function get(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': UA } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return resolve(get(res.headers.location));
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function findPhoto(keyword) {
  const api = 'https://commons.wikimedia.org/w/api.php?action=query&format=json'
    + '&generator=search&gsrnamespace=6&gsrlimit=8'
    + `&gsrsearch=${encodeURIComponent('filetype:bitmap ' + keyword)}`
    + '&prop=imageinfo&iiprop=url|mime|size&iiurlwidth=900';
  const res = await get(api);
  if (res.status !== 200) return null;
  let pages;
  try {
    pages = Object.values(JSON.parse(res.body.toString('utf8')).query?.pages ?? {});
  } catch {
    return null;
  }
  pages.sort((a, b) => (a.index ?? 99) - (b.index ?? 99));
  for (const page of pages) {
    const info = page.imageinfo?.[0];
    if (!info) continue;
    if (info.mime !== 'image/jpeg') continue;
    if ((info.width ?? 0) < 500 || (info.height ?? 0) < 400) continue;
    const img = await get(info.thumburl ?? info.url);
    if (img.status === 200 && img.body.length > 10_000) return img.body;
  }
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// What to actually search for. Product names are dishes and SKUs; a couple of words of context
// makes "Mains" less of a lottery.
const coverKeyword = {
  'beirut-grill': 'lebanese grill restaurant food',
  'nonnas-pizzeria': 'pizza wood fired oven',
  'roast-and-co': 'espresso coffee cafe',
  'fresh-market': 'grocery store produce',
  'nightowl': 'convenience store shelves night',
  'carefirst-pharmacy': 'pharmacy interior shelves',
  'voltedge': 'electronics gadgets desk',
};
const verticalFallback = {
  RESTAURANT: 'lebanese food mezze',
  COFFEE: 'coffee pastry',
  GROCERY: 'fresh produce market',
  CONVENIENCE: 'snack food packet',
  PHARMACY: 'medicine pharmacy',
  ELECTRONICS: 'electronic accessory',
  BAKERY: 'bakery bread',
  FLOWERS_GIFTS: 'flower bouquet',
};

function cleanName(name) {
  return name.replace(/\(.*?\)/g, '').replace(/\b\d+(g|ml|l|kg|pcs?)\b/gi, '').trim();
}

async function main() {
  const [, , catalogPath, outDir] = process.argv;
  if (!catalogPath || !outDir) {
    console.error('usage: node fetch-shop-photos.js <catalog.json> <outdir>');
    process.exit(1);
  }
  const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
  let hits = 0;
  let misses = 0;

  for (const store of catalog.stores) {
    const kw = coverKeyword[store.slug] ?? verticalFallback[store.vertical] ?? store.slug;
    const photo = await findPhoto(kw);
    await sleep(350);
    if (!photo) { misses++; console.log(`  miss  cover ${store.slug}`); continue; }
    const file = path.join(outDir, 'stores', store.id, 'cover.jpg');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, photo);
    hits++;
    console.log(`  ok    cover ${store.slug} (${kw})`);
  }

  for (const product of catalog.products) {
    const kw = cleanName(product.name) + ' food';
    let photo = await findPhoto(cleanName(product.name));
    if (!photo) photo = await findPhoto(kw);
    await sleep(350);
    if (!photo) { misses++; console.log(`  miss  ${product.name}`); continue; }
    const file = path.join(outDir, 'products', product.id, 'photo.jpg');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, photo);
    hits++;
    console.log(`  ok    ${product.name}`);
  }

  console.log(`\n${hits} photos fetched, ${misses} kept their drawn tile.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
