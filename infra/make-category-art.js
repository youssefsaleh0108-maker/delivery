// Generates transparent-background artwork for the home category strip, and uploads it.
//
//   node infra/make-category-art.js            # draw + upload
//   node infra/make-category-art.js --draw     # draw to infra/category-art/ only
//
// The art is drawn here rather than sourced from the web on purpose: images found through an image
// search are copyrighted almost without exception, and shipping them in a product invites a
// takedown. These are original flat-colour illustrations on a transparent field, which is what the
// tile needs — it keeps a constant pale fill, so anything with a baked-in white background would
// show as a card-on-a-card.
//
// PNG is written by hand (colour type 6, RGBA) because the alpha channel is the whole point and
// this box has no image library. Shapes are rasterised with 4x supersampling and composited
// source-over, so the curves do not look like stairs at the 58px the strip renders them at and
// colours can overlap the way a stacked vector drawing does.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { execSync } = require('child_process');

const SIZE = 256;
const SS = 4; // supersampling factor

/// A small shared palette, so seven separate illustrations still look like one set.
///
/// Nothing here is white or cream as a *dominant* mass: the tile behind these is a very pale pink,
/// and a pale illustration on it reads as a smudge. Lights are used for highlights only.
const C = {
  rose: [0xc4, 0x1d, 0x4e],
  roseDark: [0x8e, 0x12, 0x35],
  roseLight: [0xe8, 0x50, 0x6e],
  blush: [0xff, 0xe3, 0xe9],
  bun: [0xe8, 0xa9, 0x52],
  bunDark: [0xd0, 0x8e, 0x3c],
  meat: [0x8b, 0x4a, 0x2b],
  cheese: [0xf2, 0xc1, 0x4e],
  leaf: [0x5f, 0xb5, 0x4a],
  leafDark: [0x3f, 0x8e, 0x33],
  tomato: [0xd9, 0x4a, 0x3d],
  orange: [0xf0, 0x9a, 0x3e],
  coffee: [0x5b, 0x37, 0x21],
  kraft: [0xd9, 0xa5, 0x66],
  kraftDark: [0xbe, 0x8a, 0x4e],
  slate: [0x37, 0x47, 0x4f],
  slateLight: [0x62, 0x7c, 0x8a],
  sky: [0x4f, 0xc3, 0xf7],
  medical: [0x2e, 0x9e, 0x5b],
  brick: [0x8d, 0x6e, 0x63],
  brickDark: [0x5d, 0x40, 0x37],
  steam: [0xb9, 0xa4, 0xac],
};

// ---------------------------------------------------------------- geometry

const dist = (x, y, cx, cy) => Math.hypot(x - cx, y - cy);

/** Distance from a point to a line segment — the basis for every rounded bar and stroke here. */
function distToSegment(px, py, x1, y1, x2, y2) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) return dist(px, py, x1, y1);
  let t = ((px - x1) * dx + (py - y1) * dy) / lenSq;
  t = Math.max(0, Math.min(1, t));
  return dist(px, py, x1 + t * dx, y1 + t * dy);
}

const shapes = {
  /** Rounded rectangle. r = 0 gives a plain one. */
  rect: (x, y, w, h, r = 0) => (px, py) => {
    if (px < x || py < y || px > x + w || py > y + h) return false;
    if (r <= 0) return true;
    const cx = Math.min(Math.max(px, x + r), x + w - r);
    const cy = Math.min(Math.max(py, y + r), y + h - r);
    return dist(px, py, cx, cy) <= r;
  },
  circle: (cx, cy, r) => (px, py) => dist(px, py, cx, cy) <= r,
  ellipse: (cx, cy, rx, ry) => (px, py) =>
    ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1,
  /** A line with round caps — every "bar" in these glyphs. */
  bar: (x1, y1, x2, y2, r) => (px, py) => distToSegment(px, py, x1, y1, x2, y2) <= r,
  /** Ray casting, so concave outlines (the knife blade) work. */
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
  /**
   * Everything on one side of the line `a*x + b*y + c = 0`.
   *
   * Splitting a rotated shape (the pill) with hand-placed polygons is guesswork; a half-plane
   * through its midpoint, perpendicular to its axis, is exact.
   */
  half: (a, b, c) => (px, py) => a * px + b * py + c <= 0,
  /** Intersection — used to keep only the top half of a ring, making an arc. */
  and: (...tests) => (px, py) => tests.every((t) => t(px, py)),
  not: (test) => (px, py) => !test(px, py),
};

// ---------------------------------------------------------------- raster

/**
 * Renders a list of ops to RGBA bytes.
 *
 * Ops paint in order, each one composited source-over onto what is already there, so a later shape
 * covers an earlier one exactly as a stacked vector drawing would. `erase` clears back to
 * transparent instead, which is how the shopfront's door and window are cut out rather than
 * painted in a colour that would only work over one background.
 *
 * Colour is tracked separately from alpha (straight, not premultiplied) because that is what PNG
 * stores — premultiplying here would darken every antialiased edge against the pale tile.
 */
function render(ops) {
  const n = SIZE * SS;
  const px4 = SIZE * SIZE;
  const dr = new Float32Array(px4);
  const dg = new Float32Array(px4);
  const db = new Float32Array(px4);
  const da = new Float32Array(px4);

  for (const op of ops) {
    const hit = new Uint8Array(px4); // subsamples covered, per output pixel
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
      if (op.erase) {
        da[i] *= 1 - sa;
        continue;
      }
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
    raw[o++] = 0; // filter: none
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
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // colour type 6 = RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------------------------------------------------------------- the seven glyphs

const fill = (color, shape) => ({ shape, color, erase: false });
const erase = (shape) => ({ shape, erase: true });
const { rect, circle, ellipse, bar, poly, half, and, not } = shapes;

/** Top half of a ring: a filled circle, hollowed, then clipped to above its centre. */
const archTop = (cx, cy, outer, inner) =>
  and(circle(cx, cy, outer), not(circle(cx, cy, inner)), rect(0, 0, SIZE, cy));

/** A dome — the top half of an ellipse. Bun tops and awnings. */
const dome = (cx, cy, rx, ry) => and(ellipse(cx, cy, rx, ry), rect(0, 0, SIZE, cy));

// Each is a stack of flat colour shapes, painted back to front. Layers overlap by a pixel or two
// on purpose: two antialiased edges that merely touch leave a hairline of background between them.
const ART = {
  // A burger, built the way one is: bottom bun, patty, cheese, lettuce, top bun.
  RESTAURANT: [
    fill(C.bunDark, rect(48, 158, 160, 42, 18)),
    fill(C.meat, rect(44, 128, 168, 34, 14)),
    fill(C.cheese, poly([[50, 118], [206, 118], [206, 134], [176, 152], [146, 132], [116, 152], [86, 132], [50, 134]])),
    fill(C.leaf, rect(46, 104, 164, 20, 8)),
    fill(C.leaf, circle(72, 122, 12)),
    fill(C.leaf, circle(112, 124, 12)),
    fill(C.leaf, circle(152, 124, 12)),
    fill(C.leaf, circle(190, 122, 12)),
    fill(C.bun, dome(128, 108, 82, 62)),
    fill(C.bun, rect(46, 96, 164, 14)),
    // Sesame. Three, unevenly placed, because a regular grid reads as a pattern not a bun.
    fill(C.blush, ellipse(100, 76, 8, 5)),
    fill(C.blush, ellipse(140, 64, 8, 5)),
    fill(C.blush, ellipse(172, 84, 8, 5)),
  ],
  // Handle behind the cup, so the join is hidden rather than drawn.
  COFFEE: [
    fill(C.steam, bar(104, 34, 100, 62, 6)),
    fill(C.steam, bar(136, 24, 140, 62, 6)),
    fill(C.rose, and(circle(184, 130, 34), not(circle(184, 130, 20)))),
    fill(C.rose, poly([[60, 84], [180, 84], [166, 194], [74, 194]])),
    // The coffee itself, sitting just inside the rim.
    fill(C.coffee, ellipse(120, 92, 54, 13)),
    fill(C.roseDark, bar(54, 208, 186, 208, 12)),
  ],
  // A kraft bag with produce over the top, rather than an empty basket.
  GROCERY: [
    fill(C.leafDark, bar(112, 70, 96, 44, 9)),
    fill(C.leaf, ellipse(88, 44, 26, 15)),
    fill(C.tomato, circle(150, 66, 30)),
    fill(C.orange, circle(104, 78, 26)),
    fill(C.kraft, poly([[56, 96], [200, 96], [190, 210], [66, 210]])),
    fill(C.kraftDark, rect(54, 92, 148, 24, 6)),
  ],
  // A shopfront. The app's own logo is a bag, and two bags at two sizes read as the same thing
  // twice — so this category gets the building instead.
  CONVENIENCE: [
    fill(C.brick, rect(60, 96, 136, 112, 8)),
    fill(C.brickDark, rect(112, 138, 44, 70, 6)),
    fill(C.sky, rect(76, 122, 28, 28, 4)),
    // Striped awning, scalloped along its lower edge.
    fill(C.rose, poly([[44, 58], [212, 58], [200, 96], [56, 96]])),
    fill(C.blush, poly([[78, 58], [102, 58], [94, 96], [70, 96]])),
    fill(C.blush, poly([[128, 58], [152, 58], [146, 96], [122, 96]])),
    fill(C.blush, poly([[178, 58], [200, 58], [194, 96], [172, 96]])),
    erase(circle(66, 96, 12)),
    erase(circle(98, 96, 12)),
    erase(circle(130, 96, 12)),
    erase(circle(162, 96, 12)),
    erase(circle(194, 96, 12)),
  ],
  // A medical cross with a capsule across it, so it is not mistaken for a plus sign.
  //
  // The capsule runs from (96,176) to (176,96), so its axis is x-y and its midpoint is where
  // x-y = 0. Each half is that capsule clipped to one side of that line — exact, rather than two
  // polygons eyeballed to meet in the middle.
  PHARMACY: [
    fill(C.medical, rect(102, 48, 52, 156, 16)),
    fill(C.medical, rect(48, 102, 160, 52, 16)),
    fill(C.blush, and(bar(96, 176, 176, 96, 25), half(1, -1, 0))),
    fill(C.rose, and(bar(96, 176, 176, 96, 25), half(-1, 1, 0))),
  ],
  ELECTRONICS: [
    fill(C.slate, rect(80, 34, 96, 188, 20)),
    fill(C.sky, rect(92, 56, 72, 134, 8)),
    fill(C.slateLight, bar(118, 45, 138, 45, 4)),
    fill(C.slateLight, circle(128, 206, 9)),
  ],
  // Gift box with a gold ribbon and a bow — the ribbon is drawn, not carved, so it can be its own
  // colour.
  FLOWERS_GIFTS: [
    fill(C.rose, rect(56, 106, 144, 102, 10)),
    fill(C.roseDark, rect(46, 80, 164, 34, 8)),
    fill(C.cheese, rect(116, 80, 24, 128)),
    fill(C.cheese, and(circle(102, 78, 26), not(circle(102, 78, 12)))),
    fill(C.cheese, and(circle(154, 78, 26), not(circle(154, 78, 12)))),
  ],
};

// ---------------------------------------------------------------- upload

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });

function token(user) {
  return JSON.parse(
    sh(
      'curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"' +
        ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"` +
        ' -d "grant_type=password" -d "scope=openid"'
    )
  ).access_token;
}

function main() {
  const outDir = path.join(__dirname, 'category-art');
  fs.mkdirSync(outDir, { recursive: true });

  const files = {};
  for (const [name, ops] of Object.entries(ART)) {
    const file = path.join(outDir, `${name.toLowerCase()}.png`);
    fs.writeFileSync(file, png(render(ops)));
    files[name] = file;
    console.log(`  drew  ${name.padEnd(16)} ${fs.statSync(file).size} bytes`);
  }

  if (process.argv.includes('--draw')) return;

  const back = token('backoffice');
  const api = (m, p, body) => {
    const data =
      body !== undefined
        ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"`
        : '';
    return sh(`curl -s -X ${m} -H "Authorization: Bearer ${back}"${data} "http://127.0.0.1:8100${p}"`);
  };

  const chips = JSON.parse(api('GET', '/api/categories/chips'));
  console.log(`\n  ${chips.length} categories tagged with a vertical`);

  let done = 0;
  for (const chip of chips) {
    const file = files[chip.vertical];
    if (!file) {
      console.log(`  SKIP  ${chip.name} — no art for vertical ${chip.vertical}`);
      continue;
    }
    const upload = JSON.parse(
      api('POST', `/api/categories/${chip.id}/image/presign`, { contentType: 'image/png' })
    );
    const put = sh(
      `curl -s -X PUT --data-binary "@${file}" -H "Content-Type: image/png" -w "~~%{http_code}" "${upload.uploadUrl}"`
    )
      .split('~~')
      .pop()
      .trim();
    if (put !== '200') {
      console.log(`  FAIL  ${chip.name} — storage returned ${put}`);
      continue;
    }
    const confirmed = JSON.parse(
      api('POST', `/api/categories/${chip.id}/image/${upload.fileId}/confirm`)
    );
    console.log(`  OK    ${chip.name.padEnd(16)} ${confirmed.imageUrl ? 'live' : 'no url!'}`);
    done++;
  }
  console.log(`\n${done}/${chips.length} categories now carry transparent artwork`);
}

main();
