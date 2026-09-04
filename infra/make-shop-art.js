// Draws original flat-colour artwork for the demo storefront — a logo tile per shop and a
// product tile per catalogue line — and writes them to a local directory shaped exactly like
// the product-images bucket keys the database will reference:
//
//   node infra/make-shop-art.js <catalog.json> <outdir>
//
// catalog.json: { "stores": [{id, slug, vertical}], "products": [{id, name, vertical}] }
//
// Drawn here rather than sourced from the web for the same reason the category art is: found
// images are copyrighted almost without exception. These are flat two-tone illustrations —
// an opaque tinted ground with a simple white glyph — which photograph the app well without
// pretending to be photography.
//
// The raster/PNG machinery is make-category-art.js's, copied rather than imported: these are
// one-shot seed tools, and a shared module would couple two scripts that evolve for different
// screens (transparent strip tiles there, opaque cards here).
'use strict';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const SIZE = 512;
const SS = 3;

// ---------------------------------------------------------------- geometry (as category art)

const dist = (x, y, cx, cy) => Math.hypot(x - cx, y - cy);

function distToSegment(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const l2 = dx * dx + dy * dy;
  let t = l2 === 0 ? 0 : ((px - x1) * dx + (py - y1) * dy) / l2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
}

const shapes = {
  rect: (x, y, w, h, r = 0) => (px, py) => {
    const qx = Math.max(x + r - px, px - (x + w - r), 0);
    const qy = Math.max(y + r - py, py - (y + h - r), 0);
    if (px < x || px > x + w || py < y || py > y + h) return false;
    return qx * qx + qy * qy <= r * r || (px >= x + r && px <= x + w - r) || (py >= y + r && py <= y + h - r)
      ? Math.hypot(qx, qy) <= r || (qx === 0 || qy === 0)
      : false;
  },
  circle: (cx, cy, r) => (px, py) => dist(px, py, cx, cy) <= r,
  bar: (x1, y1, x2, y2, r) => (px, py) => distToSegment(px, py, x1, y1, x2, y2) <= r,
  poly: (points) => (px, py) => {
    let inside = false;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
      const [xi, yi] = points[i];
      const [xj, yj] = points[j];
      if ((yi > py) !== (yj > py) && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  },
  half: (a, b, c) => (px, py) => a * px + b * py + c <= 0,
  and: (...tests) => (px, py) => tests.every((t) => t(px, py)),
  not: (test) => (px, py) => !test(px, py),
};

// ---------------------------------------------------------------- raster + png (as category art)

function render(ops) {
  const n = SIZE * SS;
  const px4 = SIZE * SIZE;
  const dr = new Float32Array(px4);
  const dg = new Float32Array(px4);
  const db = new Float32Array(px4);
  const da = new Float32Array(px4);

  for (const op of ops) {
    const hit = new Uint8Array(px4);
    for (let sy = 0; sy < n; sy++) {
      const py = (sy + 0.5) / SS;
      for (let sx = 0; sx < n; sx++) {
        const px = (sx + 0.5) / SS;
        if (op.shape(px, py)) hit[Math.floor(py) * SIZE + Math.floor(px)]++;
      }
    }
    const max = SS * SS;
    const [sr, sg, sb] = op.color ?? [0, 0, 0];
    for (let i = 0; i < px4; i++) {
      const sa = hit[i] / max;
      if (sa === 0) continue;
      const outA = sa + da[i] * (1 - sa);
      if (outA === 0) continue;
      dr[i] = (sr * sa + dr[i] * da[i] * (1 - sa)) / outA;
      dg[i] = (sg * sa + dg[i] * da[i] * (1 - sa)) / outA;
      db[i] = (sb * sa + db[i] * da[i] * (1 - sa)) / outA;
      da[i] = outA;
    }
  }

  const raw = Buffer.alloc((SIZE * 4 + 1) * SIZE);
  let o = 0;
  for (let y = 0; y < SIZE; y++) {
    raw[o++] = 0;
    for (let x = 0; x < SIZE; x++) {
      const i = y * SIZE + x;
      raw[o++] = Math.round(dr[i]);
      raw[o++] = Math.round(dg[i]);
      raw[o++] = Math.round(db[i]);
      raw[o++] = Math.round(da[i] * 255);
    }
  }
  return raw;
}

function crc32(buf) {
  let crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    let c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function png(raw) {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(SIZE, 0);
  ihdr.writeUInt32BE(SIZE, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const fill = (color, shape) => ({ shape, color });

// ---------------------------------------------------------------- palette

const white = [0xff, 0xff, 0xff];
const verticalHue = {
  RESTAURANT: [0xe1, 0x5b, 0x3c],
  COFFEE: [0x6d, 0x4c, 0x41],
  GROCERY: [0x43, 0xa0, 0x47],
  CONVENIENCE: [0x53, 0x5b, 0xd6],
  PHARMACY: [0x2e, 0x9e, 0x8f],
  ELECTRONICS: [0x37, 0x47, 0x4f],
  FLOWERS_GIFTS: [0xc2, 0x50, 0x8c],
  BAKERY: [0xc7, 0x8a, 0x3b],
};
const soften = ([r, g, b], k) => [
  Math.round(r + (255 - r) * k),
  Math.round(g + (255 - g) * k),
  Math.round(b + (255 - b) * k),
];
const shade = ([r, g, b], k) => [Math.round(r * k), Math.round(g * k), Math.round(b * k)];

// ---------------------------------------------------------------- the glyphs
//
// Every glyph paints in WHITE, centred in a 512 canvas, sized for the middle ~55%.

const C = SIZE / 2;
const glyphs = {
  flame: (c) => [
    fill(c, shapes.circle(C, C + 45, 95)),
    fill(c, shapes.poly([[C, C - 150], [C + 88, C + 15], [C - 88, C + 15]])),
    fill(c, shapes.and(shapes.circle(C + 20, C - 15, 42), shapes.not(shapes.circle(C + 42, C - 35, 40)))),
  ],
  pizza: (c) => [
    fill(c, shapes.poly([[C, C + 130], [C - 105, C - 95], [C + 105, C - 95]])),
    fill(shade(c, 0.001), shapes.bar(C - 105, C - 95, C + 105, C - 95, 16)),
    fill(shade(c, 0.001), shapes.circle(C - 25, C - 35, 16)),
    fill(shade(c, 0.001), shapes.circle(C + 32, C - 20, 13)),
    fill(shade(c, 0.001), shapes.circle(C, C + 40, 13)),
  ],
  cup: (c) => [
    fill(c, shapes.rect(C - 80, C - 45, 160, 135, 26)),
    fill(c, shapes.and(shapes.circle(C + 105, C + 10, 45), shapes.not(shapes.circle(C + 105, C + 10, 22)))),
    fill(c, shapes.bar(C - 40, C - 95, C - 32, C - 70, 9)),
    fill(c, shapes.bar(C, C - 105, C + 8, C - 70, 9)),
    fill(c, shapes.bar(C + 40, C - 95, C + 48, C - 70, 9)),
  ],
  basket: (c) => [
    fill(c, shapes.poly([[C - 110, C - 35], [C + 110, C - 35], [C + 75, C + 115], [C - 75, C + 115]])),
    fill(c, shapes.bar(C - 55, C - 40, C - 10, C - 125, 11)),
    fill(c, shapes.bar(C + 55, C - 40, C + 10, C - 125, 11)),
  ],
  moon: (c) => [
    fill(c, shapes.and(shapes.circle(C, C, 115), shapes.not(shapes.circle(C + 62, C - 48, 100)))),
    fill(c, shapes.circle(C + 72, C + 12, 12)),
    fill(c, shapes.circle(C + 32, C - 62, 8)),
  ],
  cross: (c) => [
    fill(c, shapes.rect(C - 32, C - 110, 64, 220, 20)),
    fill(c, shapes.rect(C - 110, C - 32, 220, 64, 20)),
  ],
  bolt: (c) => [
    fill(c, shapes.poly([
      [C + 22, C - 140], [C - 62, C + 18], [C - 6, C + 18],
      [C - 22, C + 140], [C + 62, C - 22], [C + 6, C - 22],
    ])),
  ],
  bread: (c) => [
    fill(c, shapes.and(shapes.circle(C, C + 20, 112), shapes.half(0, -1, C + 20))),
    fill(c, shapes.rect(C - 112, C + 20, 224, 55, 18)),
    fill(shade(c, 0.001), shapes.bar(C - 45, C - 25, C - 25, C + 15, 8)),
    fill(shade(c, 0.001), shapes.bar(C + 5, C - 32, C + 25, C + 8, 8)),
  ],
  bottle: (c) => [
    fill(c, shapes.rect(C - 48, C - 40, 96, 175, 28)),
    fill(c, shapes.rect(C - 20, C - 105, 40, 75, 10)),
    fill(c, shapes.rect(C - 26, C - 130, 52, 26, 8)),
  ],
  plate: (c) => [
    fill(c, shapes.and(shapes.circle(C, C, 115), shapes.not(shapes.circle(C, C, 88)))),
    fill(c, shapes.circle(C, C, 62)),
  ],
  leaf: (c) => [
    fill(c, shapes.and(shapes.circle(C - 45, C + 25, 105), shapes.circle(C + 65, C - 55, 105))),
    fill(c, shapes.bar(C - 65, C + 95, C + 45, C - 45, 8)),
  ],
  pill: (c) => [
    fill(c, shapes.bar(C - 62, C - 62, C + 62, C + 62, 52)),
    fill(shade(c, 0.001), shapes.and(shapes.bar(C - 62, C - 62, C + 62, C + 62, 40), shapes.half(1, 1, -(C + C)))),
  ],
  flower: (c) => [
    fill(c, shapes.circle(C, C - 62, 40)),
    fill(c, shapes.circle(C - 55, C - 20, 40)),
    fill(c, shapes.circle(C + 55, C - 20, 40)),
    fill(c, shapes.circle(C - 34, C + 42, 40)),
    fill(c, shapes.circle(C + 34, C + 42, 40)),
    fill(shade(c, 0.001), shapes.circle(C, C, 30)),
    fill(c, shapes.bar(C, C + 60, C, C + 135, 9)),
  ],
  box: (c) => [
    fill(c, shapes.rect(C - 95, C - 70, 190, 165, 22)),
    fill(shade(c, 0.001), shapes.rect(C - 95, C - 12, 190, 22, 0)),
    fill(c, shapes.bar(C, C - 70, C, C - 120, 10)),
  ],
};

// Which glyph a product gets, by the first keyword its name matches. The fallback plate keeps
// an unknown item honest — a dish, not a guess at what it looks like.
const productRules = [
  [/pizza|margherita|pepperoni|calzone/i, 'pizza'],
  [/coffee|espresso|latte|cappuccino|americano|mocha|tea/i, 'cup'],
  [/water|cola|juice|soda|drink|ayran|milk/i, 'bottle'],
  [/croissant|bread|manakish|manoushe|bake|cake|dessert|knefeh|baklava|cookie|brownie/i, 'bread'],
  [/salad|tabbouleh|fattoush|greens|veg|herb|mint|parsley/i, 'leaf'],
  [/panadol|aspirin|vitamin|med|tablet|capsule|syrup/i, 'pill'],
  [/charger|cable|power|battery|bank|adapter|usb|earbud|speaker|headphone/i, 'bolt'],
  [/grill|taouk|shawarma|kebab|kafta|skewer|mixed/i, 'flame'],
  [/chips|snack|chocolate|gum|candy|noodles/i, 'moon'],
  [/rice|eggs|flour|sugar|oil|labneh|cheese|za'?atar|hummus|basket|produce|banana|apple|tomato/i, 'basket'],
  [/rose|flower|bouquet|orchid|lily/i, 'flower'],
];

const storeGlyph = {
  RESTAURANT: 'flame',
  COFFEE: 'cup',
  GROCERY: 'basket',
  CONVENIENCE: 'moon',
  PHARMACY: 'cross',
  ELECTRONICS: 'bolt',
  BAKERY: 'bread',
  FLOWERS_GIFTS: 'flower',
};

// A per-item hue nudge so a shelf of tiles reads varied, not stamped.
function nudge([r, g, b], i) {
  const k = ((i * 37) % 5) - 2; // -2..2
  const f = 1 + k * 0.05;
  return [Math.min(255, Math.round(r * f)), Math.min(255, Math.round(g * f)), Math.min(255, Math.round(b * f))];
}

function tile(base, glyphName, opts = {}) {
  const ground = opts.soft ? soften(base, 0.82) : base;
  const ink = opts.soft ? base : white;
  const ops = [fill(ground, shapes.rect(0, 0, SIZE, SIZE, 0))];
  if (opts.soft) {
    // A quiet corner disc gives the card depth without competing with the glyph.
    ops.push(fill(soften(base, 0.68), shapes.circle(SIZE - 70, 70, 150)));
  }
  const draw = glyphs[glyphName] ?? glyphs.plate;
  ops.push(...draw(ink).map((op) => (op.color === ink && !opts.soft ? op : op)));
  return png(render(ops));
}

// ---------------------------------------------------------------- main

function main() {
  const [, , catalogPath, outDir] = process.argv;
  if (!catalogPath || !outDir) {
    console.error('usage: node make-shop-art.js <catalog.json> <outdir>');
    process.exit(1);
  }
  const catalog = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));

  let n = 0;
  for (const store of catalog.stores) {
    const hue = verticalHue[store.vertical] ?? verticalHue.RESTAURANT;
    const file = path.join(outDir, 'stores', store.id, 'logo.png');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, tile(hue, storeGlyph[store.vertical] ?? 'plate'));
    n++;
  }
  let i = 0;
  for (const product of catalog.products) {
    const base = verticalHue[product.vertical] ?? verticalHue.RESTAURANT;
    const rule = productRules.find(([re]) => re.test(product.name));
    const file = path.join(outDir, 'products', product.id, '1.png');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, tile(nudge(base, i++), rule ? rule[1] : 'plate', { soft: true }));
    n++;
  }
  console.log(`${n} tiles written to ${outDir}`);
}

main();
