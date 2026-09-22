/*
  The basket, asked of basket.js by running it.

  Everything else about this feature is asserted against bytes the server sent, which is the right
  way round for markup and is blind to the half that lives in a browser: what a tap does, what
  survives a reload, what a second shop's page sees, and what the script believes about a number in
  a URL. None of that is in any response, so none of it could be caught by reading one.

  So this builds a document out of the elements the page really renders, runs the real, unmodified
  basket.js over it, and asserts what came out. The fake DOM is deliberately dumb — it stores text
  and children and nothing else — because the moment it starts being clever it is testing itself.

  Run: node basket.test.js <path to basket.js>
*/
'use strict';

const fs = require('fs');
const vm = require('vm');

const SOURCE = process.argv[2];
if (!SOURCE) {
  console.error('usage: node basket.test.js <path to basket.js>');
  process.exit(2);
}
const CODE = fs.readFileSync(SOURCE, 'utf8');

// ---------------------------------------------------------------- a document

function element(tag) {
  const el = {
    tag: tag,
    hidden: false,
    disabled: false,
    className: '',
    dir: '',
    type: '',
    id: '',
    attributes: {},
    children: [],
    matches: [],
    own: '',
    onclick: null,
    onchange: null,
    get childNodes() { return this.children; },
    get firstChild() { return this.children[0] || null; },
    get textContent() {
      return this.own + this.children.map(c => c.textContent).join('');
    },
    set textContent(value) {
      // A real node drops its children when its text is replaced, and the script relies on it:
      // a line's price is written and then a lira span is appended after it.
      this.children = [];
      this.own = value === undefined || value === null ? '' : String(value);
    },
    appendChild(child) { this.children.push(child); return child; },
    removeChild(child) {
      this.children = this.children.filter(c => c !== child);
      return child;
    },
    setAttribute(name, value) { this.attributes[name] = value; },
    getAttribute(name) {
      return Object.prototype.hasOwnProperty.call(this.attributes, name)
        ? this.attributes[name] : null;
    },
    addEventListener() {},
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; },
    querySelectorAll(selector) {
      const found = [];
      const walk = node => node.children.forEach(child => {
        if (child.matches.indexOf(selector) >= 0) { found.push(child); }
        walk(child);
      });
      walk(this);
      return found;
    }
  };
  return el;
}

function add(parent, selectors, tag) {
  const child = element(tag || 'div');
  child.matches = selectors;
  parent.children.push(child);
  return child;
}

/** The page as ShopPageHtml renders it, for one shop with `names` on its shelf. */
function buildPage(options) {
  const root = element('body');

  const menu = add(root, ['.menu'], 'section');
  const section = add(menu, ['.sec'], 'div');
  const list = add(section, ['.items'], 'ul');
  options.names.forEach((name, i) => {
    const row = add(list, ['.menu .sec .items > li'], 'li');
    const label = add(row, ['.n'], 'span');
    label.textContent = name;
    if (!(options.gone || []).includes(i)) {
      const button = add(row, ['.a'], 'button');
      button.textContent = 'Add';
      button.hidden = true;
    }
  });

  const offline = add(root, ['.bkno'], 'p');
  offline.textContent = 'Ordering from the table needs JavaScript.';

  const panel = add(root, ['.bk'], 'div');
  panel.hidden = true;
  // A path, as the page prints it: same-origin whichever host served the page, and carrying the
  // language so the total is spelled the way the page around it is.
  panel.setAttribute('data-q',
    '/s/' + options.slug + '/quote?lang=' + (options.lang || 'en'));
  panel.setAttribute('data-v', options.version);
  panel.setAttribute('data-e', 'The total could not be worked out just now.');
  panel.setAttribute('data-nt', 'Scan the code on your table to order from here.');

  const table = add(panel, ['.bktab'], 'p');
  table.hidden = true;
  table.setAttribute('data-l', 'Table');
  add(panel, ['.bkn'], 'p').hidden = true;
  add(panel, ['.bkempty'], 'p');
  const lines = add(panel, ['.bl'], 'ul');
  lines.setAttribute('data-more', 'Add one more');
  lines.setAttribute('data-less', 'Remove one');
  lines.setAttribute('data-note', 'A note for the kitchen');
  lines.setAttribute('data-eg', 'no onions');
  add(panel, ['.bksum'], 'div');
  add(panel, ['.bkwhat'], 'p').hidden = true;
  add(panel, ['.bksays'], 'p');
  add(panel, ['.bkgo'], 'button').disabled = true;

  const peek = add(root, ['.peek'], 'a');
  peek.hidden = true;
  peek.textContent = 'Your order';

  return root;
}

// ---------------------------------------------------------------- a browser around it

/** One visit to one page. `store` and `now` are shared so a reload is a second visit. */
function visit(options) {
  const root = buildPage(options);
  const timers = [];
  const sent = [];
  let aborted = 0;

  function XHR() {
    this.status = 200;
    this.responseText = '';
  }
  XHR.prototype.open = function (method, url) { this.method = method; this.url = url; };
  XHR.prototype.setRequestHeader = function () {};
  XHR.prototype.abort = function () { aborted++; };
  XHR.prototype.send = function (body) {
    sent.push({ url: this.url, method: this.method, body: JSON.parse(body) });
    const reply = options.reply;
    if (reply === 'error') { this.onerror(); return; }
    this.status = reply && reply.status ? reply.status : 200;
    this.responseText = JSON.stringify(reply && reply.body ? reply.body : reply || {});
    this.onload();
  };

  const sandbox = {
    document: {
      querySelector: s => root.querySelector(s),
      querySelectorAll: s => root.querySelectorAll(s),
      createElement: tag => element(tag)
    },
    window: {
      location: { search: options.search || '' },
      setTimeout: fn => timers.push(fn),
      clearTimeout: i => { timers[i - 1] = null; }
    },
    localStorage: options.store,
    XMLHttpRequest: XHR,
    Date: Date,
    JSON: JSON,
    Math: Math,
    String: String,
    console: console
  };
  sandbox.window.setTimeout = fn => { timers.push(fn); return timers.length; };

  vm.runInNewContext(CODE, sandbox);

  const page = {
    root: root,
    panel: root.querySelector('.bk'),
    lines: root.querySelector('.bl'),
    peek: root.querySelector('.peek'),
    says: root.querySelector('.bksays'),
    sums: root.querySelector('.bksum'),
    table: root.querySelector('.bktab'),
    sent: sent,
    aborted: () => aborted,
    /** Runs whatever the debounce was holding. */
    flush() {
      const due = timers.splice(0, timers.length);
      due.forEach(fn => { if (fn) { fn(); } });
      return this;
    },
    addRow(i) {
      root.querySelectorAll('.menu .sec .items > li')[i].querySelector('.a').onclick();
      return this;
    },
    /** The two counters on a basket line: 0 is minus, 2 is plus. */
    tap(line, which) {
      this.lines.children[line].children[which].onclick();
      return this;
    },
    names() {
      return this.lines.children.map(row => row.children[3].textContent);
    },
    counts() {
      return this.lines.children.map(row => row.children[1].textContent);
    },
    prices() {
      return this.lines.children.map(row => row.children[4].textContent);
    },
    reply(body) { options.reply = body; return this; }
  };
  return page;
}

/** A browser's localStorage: one map for the whole browser, keyed however the script keys it. */
function browser() {
  const held = {};
  return {
    getItem: k => (Object.prototype.hasOwnProperty.call(held, k) ? held[k] : null),
    setItem: (k, v) => { held[k] = String(v); },
    removeItem: k => { delete held[k]; },
    keys: () => Object.keys(held),
    raw: k => held[k]
  };
}

/**
 * A quote as the server sends one: words, one figure, and no part of a sum.
 *
 * There is no subtotal and no fee here because there is none to send — a table's order is the
 * food, and a second money line appearing in this fixture would be the first sign of one
 * appearing on the bill.
 */
function answer(overrides) {
  return Object.assign({
    ok: true,
    count: '1 item',
    lines: [{ at: 0, name: 'Hummus', qty: '1×', price: '$1.50', priceLbp: '135,000 LBP' }],
    total: '$1.50',
    totalLbp: '135,000 LBP',
    totalLabel: 'Total',
    says: []
  }, overrides || {});
}

// ---------------------------------------------------------------- the cases

let failures = 0;

function check(what, got, wanted) {
  const a = JSON.stringify(got);
  const b = JSON.stringify(wanted);
  if (a === b) {
    console.log('  ok   ' + what);
  } else {
    failures++;
    console.log('  FAIL ' + what + '\n         got    ' + a + '\n         wanted ' + b);
  }
}

function heading(what) { console.log(what); }


// --- no table, no pad

heading('a page opened without a table code has no pad at all');
{
  const store = browser();
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '', reply: answer() });

  check('the panel stays hidden', page.panel.hidden, true);
  check('no Add button is revealed',
    page.root.querySelectorAll('.menu .sec .items > li')
      .map(r => r.querySelector('.a').hidden), [true]);
  check('the line says why, instead of saying JavaScript is missing',
    page.root.querySelector('.bkno').textContent,
    'Scan the code on your table to order from here.');
  check('and nothing is asked of the server', page.sent.length, 0);
  check('nothing is written down either', store.keys(), []);
}

heading('anything that is not a table code is not a table');
{
  const nonsense = [
    '?t=<img src=x onerror=alert(1)>',
    '?t=%3Cscript%3E',
    '?t=' + encodeURIComponent('7" onmouseover="x'),
    '?t=' + encodeURIComponent('../../etc/passwd'),
    '?t=' + encodeURIComponent('٧'),
    '?t=ABCDEFGHIJ',
    '?t=',
    '?t=%E2%80%AE7'
  ];
  nonsense.forEach(search => {
    const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
      search: search, reply: answer() });
    check('no pad for ' + search, [page.panel.hidden, page.table.hidden], [true, true]);
  });

  // The shapes a real sticker has.
  ['?t=7', '?t=12', '?t=B12', '?a=1&t=3', '?t=3&lang=ar'].forEach(search => {
    const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
      search: search, reply: answer() });
    check('a pad for ' + search, [page.panel.hidden, page.table.hidden], [false, false]);
  });
}

heading('the table is shown, after the page’s own word');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=B12', reply: answer() });

  check('the word and the code', page.table.textContent, 'Table B12');
  check('the code itself reads left to right', page.table.children[0].dir, 'ltr');
}

// --- filling the pad

heading('a pad is filled, changed and emptied');
{
  const store = browser();
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus', 'Fattoush'], store: store,
    search: '?t=7', reply: answer() });

  check('the panel is revealed and the no-script line hidden',
    [page.panel.hidden, page.root.querySelector('.bkno').hidden], [false, true]);
  check('every Add button is revealed',
    page.root.querySelectorAll('.menu .sec .items > li')
      .map(r => r.querySelector('.a').hidden), [false, false]);
  check('a button says what it adds',
    page.root.querySelectorAll('.menu .sec .items > li')[1].querySelector('.a')
      .getAttribute('aria-label'), 'Add Fattoush');
  check('nothing is asked of the server for an empty pad', page.sent.length, 0);

  page.addRow(0).flush();
  check('one line, named off the page', page.names(), ['Hummus']);
  check('the server was asked, with the shelf and the table it was asked about',
    page.sent[0].body,
    { version: 'v1', table: '7', lines: [{ at: 0, qty: 1, note: '' }] });

  page.addRow(0).flush();
  check('adding the same dish again is a count, not a second line',
    [page.lines.children.length, page.sent[1].body.lines],
    [1, [{ at: 0, qty: 2, note: '' }]]);

  page.addRow(1).flush();
  check('a second dish is a second line', page.names(), ['Hummus', 'Fattoush']);

  page.tap(1, 2).flush();
  check('the + counter raises one line only', page.sent[3].body.lines,
    [{ at: 0, qty: 2, note: '' }, { at: 1, qty: 2, note: '' }]);

  page.tap(1, 0).tap(1, 0).flush();
  check('taking the last one away removes the line', page.names(), ['Hummus']);

  page.tap(0, 0).tap(0, 0);
  check('emptying it says so and hides the strip',
    [page.lines.children.length, page.panel.querySelector('.bkempty').hidden, page.peek.hidden],
    [0, false, true]);
}

heading('one table cannot order more than a table plausibly orders');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer() });
  page.addRow(0);
  for (let i = 0; i < 60; i++) { page.tap(0, 2); }
  page.flush();
  check('the count stops at twenty', page.sent[page.sent.length - 1].body.lines,
    [{ at: 0, qty: 20, note: '' }]);
}

// --- the note

heading('a note for the kitchen');
{
  const store = browser();
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '?t=7', reply: answer() });
  page.addRow(0).flush();

  const field = page.lines.children[0].children[5];
  check('the field says which dish it is about',
    field.getAttribute('aria-label'), 'A note for the kitchen: Hummus');
  check('and shows an example of one', field.placeholder, 'no onions');

  field.value = 'no onions';
  field.onchange();
  page.flush();
  check('what was typed goes with the line',
    page.sent[page.sent.length - 1].body.lines, [{ at: 0, qty: 1, note: 'no onions' }]);
  check('and is kept with the pad', JSON.parse(store.raw('yd.t.furn.7')).l, [[0, 1, 'no onions']]);

  // The server holds the authoritative copy — cut to length and escaped — and hands it back.
  page.reply(answer({ lines: [{ at: 0, name: 'Hummus', qty: '1×', price: '$1.50',
    note: 'no onions' }] }));
  page.addRow(0).flush();
  check('the server’s copy is what the field then shows',
    page.lines.children[0].children[5].value, 'no onions');
}

// --- surviving, and staying apart

heading('a pad survives a reload of the same table');
{
  const store = browser();
  visit({ slug: 'furn', version: 'v1', names: ['Hummus', 'Fattoush'], store: store,
    search: '?t=7', reply: answer() }).addRow(1).addRow(1).flush();

  const again = visit({ slug: 'furn', version: 'v1', names: ['Hummus', 'Fattoush'], store: store,
    search: '?t=7', reply: answer({ lines: [{ at: 1, name: 'Fattoush', qty: '2×',
      price: '$4.50' }] }) });
  again.flush();

  check('the line came back', again.names(), ['Fattoush']);
  check('and so did the count', again.sent[0].body.lines, [{ at: 1, qty: 2, note: '' }]);
  check('nothing but positions, counts and notes was kept',
    Object.keys(JSON.parse(store.raw('yd.t.furn.7'))).sort(), ['l', 'u', 'v']);
  check('one key, named for this shop and this table', store.keys(), ['yd.t.furn.7']);
}

heading('two tables in one restaurant keep two pads');
{
  const store = browser();
  visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store, search: '?t=7',
    reply: answer() }).addRow(0).flush();
  const twelve = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '?t=12', reply: answer() });

  check('table 12 opens empty', twelve.lines.children.length, 0);
  check('and asks the server nothing', twelve.sent.length, 0);

  twelve.addRow(0).flush();
  check('two pads, two keys', store.keys().sort(), ['yd.t.furn.12', 'yd.t.furn.7']);
  check('table 7 is untouched', JSON.parse(store.raw('yd.t.furn.7')).l, [[0, 1, '']]);
}

heading('two restaurants keep two pads');
{
  const store = browser();
  visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store, search: '?t=7',
    reply: answer() }).addRow(0).flush();
  const other = visit({ slug: 'dekkane', version: 'v9', names: ['Manakish'], store: store,
    search: '?t=7', reply: answer() });

  check('the other restaurant’s table 7 opens empty', other.lines.children.length, 0);
  other.addRow(0).flush();
  check('two keys', store.keys().sort(), ['yd.t.dekkane.7', 'yd.t.furn.7']);
}

heading('a pad is dropped when it can no longer mean anything');
{
  const store = browser();
  visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store, search: '?t=7',
    reply: answer() }).addRow(0).flush();

  // The same shop, a shelf that has moved: the positions name something else now.
  const moved = visit({ slug: 'furn', version: 'v2', names: ['Aa hummus', 'Hummus'],
    store: store, search: '?t=7', reply: answer() });
  check('a pad from another shelf is not carried over', moved.lines.children.length, 0);
  check('and is not left lying in storage either', store.raw('yd.t.furn.7'), undefined);

  // And one from this morning.
  const old = browser();
  old.setItem('yd.t.furn.7', JSON.stringify(
    { v: 'v1', l: [[0, 3, '']], u: Date.now() - (14400000 * 2) }));
  const stale = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: old,
    search: '?t=7', reply: answer() });
  check('a pad older than a meal is dropped', stale.lines.children.length, 0);
}

heading('the server can say the shelf moved, and the pad goes');
{
  const store = browser();
  visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store, search: '?t=7',
    reply: answer() }).addRow(0).flush();

  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '?t=7',
    reply: { ok: false, stale: true, count: '', lines: [], total: '', totalLabel: '',
      says: ['This shop’s menu changed, so your order was cleared.'] } });
  page.flush();

  check('the pad is emptied', page.lines.children.length, 0);
  check('the diner is told why',
    page.says.textContent, 'This shop’s menu changed, so your order was cleared.');
  check('and nothing is left in storage', store.raw('yd.t.furn.7'), undefined);
}

// --- the money

heading('every figure on the screen came from the server');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7',
    reply: answer({ count: '2 items', lines: [{ at: 0, name: 'Hummus', qty: '٢×',
      price: '٣٫٠٠ $', priceLbp: '٢٧٠٬٠٠٠ ل.ل.' }],
    total: '٣٫٠٠ $', totalLbp: '٢٧٠٬٠٠٠ ل.ل.', totalLabel: 'المجموع' }) });
  page.addRow(0).flush();

  check('the count is the server’s word, not a number counted here', page.counts(), ['٢×']);
  check('so is the line', page.prices(), ['٣٫٠٠ $٢٧٠٬٠٠٠ ل.ل.']);
  check('the receipt is one row, because a table’s order has one figure',
    page.sums.children.map(r => r.children[0].textContent), ['المجموع']);
  check('and it is the one the server sent',
    page.sums.children[0].children[1].textContent, '٣٫٠٠ $٢٧٠٬٠٠٠ ل.ل.');
  check('the strip says what is on the pad and what it comes to',
    page.peek.textContent, 'Your order · 2 items · ٣٫٠٠ $');
}

heading('when the server cannot be asked, there is no total at all');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: 'error' });
  page.addRow(0).flush();

  check('the lines the diner chose are still there', page.names(), ['Hummus']);
  check('and not one figure is invented',
    [page.sums.children.length, page.prices()], [0, ['']]);
  check('the diner is told', page.says.textContent,
    'The total could not be worked out just now.');
  check('and the strip is not offering a total it does not have', page.peek.hidden, true);
}

heading('Send never beckons while there is nowhere to send to');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer({ ok: true }) });
  page.addRow(0).flush();
  check('the button is dead even on a pad with nothing wrong with it',
    page.panel.querySelector('.bkgo').disabled, true);
}

heading('what is wrong with a pad is said, above the button');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7',
    reply: answer({ ok: false, says: ['The kitchen is closed right now.', 'Something ran out.'] }) });
  page.addRow(0).flush();
  check('every sentence the server sent', page.says.textContent,
    'The kitchen is closed right now. Something ran out.');
}

heading('a dish that ran out is marked on its own line');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7',
    reply: answer({ ok: false, lines: [{ at: 0, name: 'Hummus', qty: '1×', price: '$1.50',
      gone: 'Out of stock' }], says: ['Something on your order has run out.'] }) });
  page.addRow(0).flush();
  check('the line says so', page.names(), ['HummusOut of stock']);
  check('and is drawn as gone', page.lines.children[0].className, 'gone');
}

// --- the debounce

heading('four taps are one question');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer() });
  page.addRow(0).addRow(0).addRow(0).addRow(0);
  check('nothing has gone yet', page.sent.length, 0);
  page.flush();
  check('and then exactly one did, with the count it ended on',
    [page.sent.length, page.sent[0].body.lines], [1, [{ at: 0, qty: 4, note: '' }]]);
}

// --- a browser that refuses to remember

heading('a browser with storage switched off still has a pad for this visit');
{
  const blocked = {
    getItem() { throw new Error('denied'); },
    setItem() { throw new Error('denied'); },
    removeItem() { throw new Error('denied'); }
  };
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: blocked,
    search: '?t=7', reply: answer() });
  page.addRow(0).flush();
  check('it works, it just will not be there after a reload', page.names(), ['Hummus']);
}

console.log(failures === 0 ? 'basket cases passed' : failures + ' basket cases FAILED');
process.exit(failures === 0 ? 0 : 1);
