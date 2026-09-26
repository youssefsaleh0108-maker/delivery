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
  // Where a round goes and where its ticket is read back — paths, so same-origin whichever
  // hostname served the page — and every word for what happens after the tap. All of them as
  // ShopPageHtml prints them and ShopPageText spells them.
  panel.setAttribute('data-s', '/api/table-orders');
  panel.setAttribute('data-ss', '/api/table-orders/status/');
  panel.setAttribute('data-g', options.arabic ? 'يُرسل…' : 'Sending…');
  panel.setAttribute('data-sd', 'DELIVERED|CANCELLED');
  panel.setAttribute('data-st', options.arabic
    ? 'PLACED=أُرسل إلى المطبخ. لم يُستلم بعد.|ACCEPTED=المطبخ استلم طلبك.|PREPARING=يُجهّز الآن.'
      + '|READY=جاهز.|PICKED_UP=جاهز.|DELIVERED=قُدّم. بالهناء والشفاء.'
      + '|CANCELLED=أُلغي هذا الطلب. اسأل الموظفين.'
    : 'PLACED=Sent to the kitchen. Not picked up yet.|ACCEPTED=The kitchen has your order.'
      + '|PREPARING=Being made now.|READY=Ready.|PICKED_UP=Ready.'
      + '|DELIVERED=Served. Enjoy your meal.|CANCELLED=This order was cancelled. '
      + 'Please ask the staff.');
  panel.setAttribute('data-r', options.arabic
    ? 'TOO_MANY=أُرسلت طلبات كثيرة من هذه الطاولة. انتظر لحظة ثم أرسل مرة أخرى.'
      + '|REFUSED=لم يستطع المتجر استقبال هذا الطلب.'
      + '|PRICE_CHANGED=تغيّر السعر. راجع المجموع الجديد ثم أرسل مرة أخرى.'
      + '|FAILED=تعذّر إرسال طلبك الآن. حاول مرة أخرى أو اطلب من الموظفين.'
      + '|GONE=لم تعد هناك تحديثات لهذا الطلب. اسأل الموظفين عنه.'
    : 'TOO_MANY=That table has sent several orders just now. Wait a moment and send again.'
      + '|REFUSED=The shop could not take this order.'
      + '|PRICE_CHANGED=The price changed. Check the new total and send again.'
      + '|FAILED=Your order could not be sent just now. Try again, or order with the staff.'
      + '|GONE=There are no more updates for this order. Ask the staff about it.');

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
  const button = add(panel, ['.bkgo'], 'button');
  button.disabled = true;
  button.textContent = options.arabic ? 'أرسل إلى المطبخ' : 'Send to the kitchen';
  button.setAttribute('aria-disabled', 'true');
  // What this table has already sent, under the button that sends the next round. Hidden until
  // there is one, and filled by the script out of the answers it was given.
  const sent = add(panel, ['.bksent'], 'div');
  sent.hidden = true;
  add(sent, ['.bkgot'], 'ol');

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
  /*
    The page talks to three addresses now, and they answer differently, so each has its own arranged
    reply: `reply` is the quote's, as it always was, `back` is the send's and `read` is a ticket's
    own link. Each is {status, body}, or an array for one answer per call in order, or 'error' for a
    request that never arrives, or 'hold' for one that has not answered yet — which is the state a
    diner on a slow connection taps a second time in.
  */
  XHR.prototype.send = function (body) {
    const kind = this.url.indexOf('/quote') >= 0 ? 'quote'
      : (this.method === 'POST' ? 'send' : 'read');
    sent.push({ url: this.url, method: this.method, kind: kind,
      body: body ? JSON.parse(body) : null });
    let reply = kind === 'quote' ? options.reply
      : (kind === 'send' ? options.back : options.read);
    if (Array.isArray(reply)) {
      const turn = sent.filter(c => c.kind === kind).length - 1;
      reply = reply[Math.min(turn, reply.length - 1)];
    }
    if (reply === 'hold') { return; }
    if (reply === 'error' || (reply === undefined && kind !== 'quote')) {
      // A request nobody arranged an answer for went nowhere, which is a truer default than a
      // silent 200: a case that forgot one should notice.
      this.onerror();
      return;
    }
    this.status = reply && reply.status ? reply.status : (kind === 'send' ? 201 : 200);
    this.responseText = JSON.stringify(reply && reply.body !== undefined ? reply.body
      : (reply || {}));
    this.onload();
  };

  const sandbox = {
    document: {
      querySelector: s => root.querySelector(s),
      querySelectorAll: s => root.querySelectorAll(s),
      createElement: tag => element(tag),
      // A phone whose owner is looking at it. The script asks nothing while this is true.
      hidden: !!options.pocket
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
    go: root.querySelector('.bkgo'),
    sentBox: root.querySelector('.bksent'),
    got: root.querySelector('.bkgot'),
    sent: sent,
    aborted: () => aborted,
    /** Whether the one action on this page can be taken at all. */
    reachable() {
      return !this.go.disabled && this.go.getAttribute('aria-disabled') !== 'true';
    },
    /** Taps it, the way a diner does — and does nothing at all if it is dead, as they would. */
    send() {
      if (!this.go.disabled) { this.go.onclick(); }
      return this;
    },
    /** Every POST that reached the order service, in order: one per ticket, never more. */
    posts() {
      return sent.filter(call => call.method === 'POST' && call.url === '/api/table-orders');
    },
    reads() {
      return sent.filter(call => call.method === 'GET');
    },
    /** The rounds drawn under the button: what each one was, what it came to, where it has got to. */
    rounds() {
      return this.got.children.map(row => ({
        lines: row.children[0].children.map(had => had.children.map(c => c.textContent)),
        total: row.children[1].textContent,
        state: row.children[2].textContent
      }));
    },
    answers(read) { options.read = read; return this; },
    /** The phone goes in a pocket, or comes out of one. */
    pocketed(yes) { sandbox.document.hidden = yes; return this; },
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
    table: '7',
    says: [],
    // The one part of a quote that is not words: the order service's own request, for a pad that
    // could be sent as it stands. Its presence is the server saying so, and the page's only
    // business with it is to post it — which is why every field here is the order service's.
    send: SEND
  }, overrides || {});
}

const SEND = {
  storeId: '8f14e45f-ceea-467a-9c2e-1e0a1b2c3d4e',
  table: 7,
  items: [{ productId: '11111111-2222-3333-4444-555555555555', qty: 1 }],
  expectedTotal: 1.50
};

/** A ticket, as the order service answers a send. */
function ticket(overrides) {
  return Object.assign({
    id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    table: 7,
    status: 'PLACED',
    shopName: 'Furn Beirut',
    items: [{ name: 'Hummus', qty: 1, unitPrice: 1.50, lineTotal: 1.50 }],
    total: 1.50,
    sentAt: '2026-09-23T17:00:00Z'
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

  // The shapes a real card has: a number, and nothing else.
  ['?t=7', '?t=12', '?a=1&t=3', '?t=3&lang=ar'].forEach(search => {
    const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
      search: search, reply: answer() });
    check('a pad for ' + search, page.panel.hidden, false);
    check('and a question for the server about ' + search, page.flush().sent.length, 1);
  });
}

heading('the table is shown, and it is the server that says which');
{
  // Asked on load with nothing chosen: the server is the only thing that knows whether this shop
  // really has the table the address named, and how to spell it in the page's language.
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=12', reply: answer({ table: '12' }) });
  page.flush();

  check('the empty pad still asked', page.sent[0].body.table, '12');
  check('the word and the number', page.table.textContent, 'Table 12');
  check('shown', page.table.hidden, false);
}

heading('a number this shop does not have is not a table');
{
  // The card said 99; the room seats twelve. The script cannot know that, so it sends it and the
  // server declines to name a table — which is the whole of the rule.
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=99',
    reply: { ok: false, count: '', lines: [], total: '', totalLabel: '',
      says: ['Scan the code on your table to order from here.'] } });
  page.flush();

  check('nothing is shown as a table', [page.table.hidden, page.table.textContent], [true, '']);
  check('and the diner is told', page.says.textContent,
    'Scan the code on your table to order from here.');
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

// --- the one action

/*
  THE CASE THIS FEATURE SHIPPED WITHOUT.

  Everything else about ordering at a table was built, merged, deployed and covered — the endpoint,
  the ledger proof, a smoke test that calls it with curl — and none of it opened the page and pressed
  the button, so a diner could build a correct, server-priced order and had nowhere to send it. The
  button was `disabled` in a line of this script, with no explanation on the screen.

  So: a shop that takes table orders, a code off a card, food on the pad, and the question is whether
  the diner can act. If the button is ever dead or inert while the server says the pad can be sent,
  this fails.
*/
heading('a pad the server says can be sent HAS a button, and it reaches the kitchen');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(), back: { status: 201, body: ticket() } });
  page.addRow(0).flush();

  check('the button is alive', page.reachable(), true);
  check('and says so to a screen reader', page.go.getAttribute('aria-disabled'), 'false');

  page.send();
  check('one POST, to the path the page was given', page.posts().map(c => c.url),
    ['/api/table-orders']);
  check('carrying the server’s own body, byte for byte and nothing added',
    page.posts()[0].body, SEND);
}

heading('nothing is sent while the server has not said it can be');
{
  // The refusals, each one arriving as the absence of `send` AND a sentence. Both halves: a dead
  // button with nothing beside it is the defect, and a sentence with a live button would send food
  // to a closed kitchen.
  const refusals = [
    { what: 'a closed kitchen', reply: answer({ ok: false, send: undefined,
      says: ['The kitchen is closed right now, so this cannot be sent.'] }),
    words: 'The kitchen is closed right now, so this cannot be sent.' },
    { what: 'something that ran out', reply: answer({ ok: false, send: undefined,
      says: ['Something on your order has run out. Remove it to send the rest.'] }),
    words: 'Something on your order has run out. Remove it to send the rest.' },
    { what: 'a shop that does not take table orders', reply: answer({ ok: false, send: undefined,
      lines: [], says: ['This shop does not take orders from the table online.'] }),
    words: 'This shop does not take orders from the table online.' },
    { what: 'a table this shop does not have', reply: answer({ ok: false, send: undefined,
      table: undefined, says: ['Scan the code on your table to order from here.'] }),
    words: 'Scan the code on your table to order from here.' }
  ];
  refusals.forEach(one => {
    const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
      search: '?t=7', reply: one.reply });
    page.addRow(0).flush();
    check('the button is dead for ' + one.what, page.reachable(), false);
    check('and the diner is told why, in words', page.says.textContent, one.words);
    page.send();
    check('and nothing reached the kitchen', page.posts().length, 0);
  });
}

heading('a pad that changed since the quote cannot be sent until it is priced again');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus', 'Fattoush'],
    store: browser(), search: '?t=7', reply: answer(), back: { status: 201, body: ticket() } });
  page.addRow(0).flush();
  check('sendable', page.reachable(), true);

  page.addRow(1);
  check('a tap kills the button, because the body in hand is for the pad before the tap',
    page.reachable(), false);
  page.send();
  check('so nothing goes', page.posts().length, 0);

  page.flush();
  check('and the fresh answer brings it back', page.reachable(), true);
}

heading('what the diner sees after sending');
{
  const store = browser();
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '?t=7',
    reply: answer({ count: '2 items', lines: [{ at: 0, name: 'Hummus', qty: '2×',
      price: '$3.00', priceLbp: '270,000 LBP' }], total: '$3.00', totalLbp: '270,000 LBP' }),
    back: { status: 201, body: ticket() } });
  page.addRow(0).addRow(0).flush();
  page.send();

  check('what they ordered, priced as the server spelled it, not as this page could have',
    page.rounds()[0].lines, [['2×', 'Hummus', '$3.00270,000 LBP']]);
  check('the total, labelled, the server’s own string',
    page.rounds()[0].total, 'Total$3.00270,000 LBP');
  check('and where the kitchen has got to', page.rounds()[0].state,
    'Sent to the kitchen. Not picked up yet.');
  check('the receipt is shown at all', page.sentBox.hidden, false);

  check('the pad is emptied, so the same food cannot be sent twice by accident',
    [page.lines.children.length, page.panel.querySelector('.bkempty').hidden], [0, false]);
  check('and the button with it', page.reachable(), false);
  check('the table is still named', page.table.textContent, 'Table 7');
  check('what is kept is the receipt and the ticket, under this table’s own key',
    store.keys().sort(), ['yd.s.furn.7']);
}

heading('a second round is a second ticket, not a replacement');
{
  const store = browser();
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus', 'Fattoush'], store: store,
    search: '?t=7', reply: answer(), back: [{ status: 201, body: ticket() },
      { status: 201, body: ticket({ id: 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' }) }] });
  page.addRow(0).flush();
  page.send();

  page.reply(answer({ lines: [{ at: 1, name: 'Fattoush', qty: '1×', price: '$2.25' }],
    total: '$2.25' }));
  page.addRow(1).flush();
  check('the pad fills again', page.names(), ['Fattoush']);
  page.send();

  check('two POSTs', page.posts().length, 2);
  check('and two rounds on the screen, in the order they were sent',
    page.rounds().map(r => r.lines[0][1]), ['Hummus', 'Fattoush']);
  check('the second did not replace the first in storage',
    JSON.parse(store.raw('yd.s.furn.7')).r.map(r => r.i),
    ['aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff']);
}

heading('a reload at the same table remembers what was already sent');
{
  const store = browser();
  const first = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '?t=7', reply: answer(), back: { status: 201, body: ticket() } });
  first.addRow(0).flush();
  first.send();

  const again = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '?t=7', reply: answer({ lines: [], total: '', ok: false, send: undefined,
      says: [] }), read: { status: 200, body: ticket({ status: 'PREPARING' }) } });

  check('the round is on the screen before anything is asked', again.rounds()[0].lines,
    [['1×', 'Hummus', '$1.50135,000 LBP']]);
  check('with the state it was last known to be in', again.rounds()[0].state,
    'Sent to the kitchen. Not picked up yet.');
  check('the pad itself is empty, because it was sent', again.lines.children.length, 0);

  // And then the kitchen's turn: the ticket is asked after, once, and what comes back is drawn.
  again.flush();
  check('the ticket was read back with its own link', again.reads().map(c => c.url),
    ['/api/table-orders/status/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee']);
  check('and the diner is told what the kitchen is doing', again.rounds()[0].state,
    'Being made now.');
  check('which is remembered too', JSON.parse(store.raw('yd.s.furn.7')).r[0].s, 'PREPARING');
}

heading('a ticket that has stopped moving is not asked about again');
{
  const store = browser();
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: store,
    search: '?t=7', reply: answer(),
    back: { status: 201, body: ticket() },
    read: { status: 200, body: ticket({ status: 'DELIVERED' }) } });
  page.addRow(0).flush();
  page.send();
  page.flush();

  check('served, in words', page.rounds()[0].state, 'Served. Enjoy your meal.');
  const asked = page.reads().length;
  page.flush().flush();
  check('and nothing is asked after that', page.reads().length, asked);
}

heading('a ticket the kitchen has not touched is not redrawn');
{
  // .bkgot is a live region: rebuilding it announces the whole thing again. So a poll that brings
  // back the state the round already had must leave the rows it is looking at alone.
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(), back: { status: 201, body: ticket() },
    read: { status: 200, body: ticket() } });
  page.addRow(0).flush();
  page.send();
  const drawn = page.got.children[0];

  page.flush();
  check('the ticket was asked after', page.reads().length, 1);
  check('and the row a screen reader is on is the same row', page.got.children[0] === drawn, true);

  page.answers({ status: 200, body: ticket({ status: 'READY' }) }).flush();
  check('a state that did change is drawn', page.rounds()[0].state, 'Ready.');
  check('which is a new row', page.got.children[0] === drawn, false);
}

heading('a phone in a pocket asks nothing');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(), back: { status: 201, body: ticket() } });
  page.addRow(0).flush();
  page.send();

  page.pocketed(true).flush();
  check('no ticket was read while nobody was looking', page.reads().length, 0);
  page.answers({ status: 200, body: ticket({ status: 'READY' }) }).pocketed(false).flush();
  check('and it catches up when the diner looks again', page.rounds()[0].state, 'Ready.');
}

heading('a link that has run out of life is the end of the story, said as one');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(),
    back: { status: 201, body: ticket() }, read: { status: 404, body: { title: 'Not found' } } });
  page.addRow(0).flush();
  page.send();
  page.flush();

  check('the round is still there, with what was ordered on it',
    page.rounds()[0].lines[0][1], 'Hummus');
  check('and the diner is told rather than left with a blank line', page.rounds()[0].state,
    'There are no more updates for this order. Ask the staff about it.');
  const asked = page.reads().length;
  page.flush();
  check('nothing is asked after that either', page.reads().length, asked);
}

// --- every refusal of a send, in words

heading('every way a send can be refused is a sentence on the screen');
{
  const refusals = [
    { what: 'too many from one table', back: { status: 429,
      body: { code: 'TABLE_ORDER_REFUSED', refusal: 'TOO_MANY' } },
    words: 'That table has sent several orders just now. Wait a moment and send again.' },
    { what: 'the shop refusing it', back: { status: 422,
      body: { code: 'TABLE_ORDER_REFUSED', refusal: 'NOT_TAKING_TABLE_ORDERS' } },
    words: 'The shop could not take this order.' },
    { what: 'a price that moved', back: { status: 409,
      body: { code: 'PRICE_CHANGED', expectedTotal: 1.50, total: 1.75 } },
    words: 'The price changed. Check the new total and send again.' },
    { what: 'an item that has gone', back: { status: 422, body: { title: 'Item unavailable' } },
      words: 'The shop could not take this order.' },
    { what: 'nothing serving that path at all', back: { status: 404, body: {} },
      words: 'Your order could not be sent just now. Try again, or order with the staff.' },
    { what: 'the service falling over', back: { status: 503, body: {} },
      words: 'Your order could not be sent just now. Try again, or order with the staff.' },
    { what: 'a request that never left the phone', back: 'error',
      words: 'Your order could not be sent just now. Try again, or order with the staff.' }
  ];
  refusals.forEach(one => {
    const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
      search: '?t=7', reply: answer(), back: one.back });
    page.addRow(0).flush();
    page.send();

    check('refused for ' + one.what + ', in words', page.says.textContent, one.words);
    check('no round is drawn for an order the kitchen never got', page.rounds().length, 0);
    check('the pad still holds what was chosen', page.names(), ['Hummus']);
    check('and the button says what it always says', page.go.textContent, 'Send to the kitchen');
  });
}

heading('a refusal the shop owns is priced again, so the reason is current');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(),
    back: { status: 409, body: { code: 'PRICE_CHANGED' } } });
  page.addRow(0).flush();
  const asked = page.sent.length;

  page.reply(answer({ total: '$1.75', totalLbp: '157,500 LBP' }));
  page.send();
  page.flush();

  check('the pad was asked again', page.sent.length > asked, true);
  check('and it is the new total on the screen',
    page.sums.children[0].children[1].textContent, '$1.75157,500 LBP');
  check('the button is alive again, because the diner decides whether to send it',
    page.reachable(), true);
}

heading('a request that failed can be tried again without asking anything else');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(), back: ['error', { status: 201, body: ticket() }] });
  page.addRow(0).flush();
  page.send();

  check('told', page.says.textContent,
    'Your order could not be sent just now. Try again, or order with the staff.');
  check('and the button is back, with the pad exactly as it was',
    [page.reachable(), page.names()], [true, ['Hummus']]);

  page.send();
  check('the second attempt is the same body', page.posts().map(c => c.body), [SEND, SEND]);
  check('and this time there is a round', page.rounds().length, 1);
}

heading('one tap is one ticket, whatever a diner does with a slow connection');
{
  // A send in flight answers nothing yet: every further tap must do nothing at all, because the
  // second one would be a second ticket for food already on its way.
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(), back: 'hold' });
  page.addRow(0).flush();

  page.go.onclick();
  check('the label says what is happening', page.go.textContent, 'Sending…');
  check('and the button is dead while it happens', page.reachable(), false);
  page.go.onclick();
  page.go.onclick();
  check('three taps, one POST', page.posts().length, 1);
  check('and no round claimed for an answer nobody has had yet', page.rounds().length, 0);
}

heading('a 201 nobody can read is an order that exists, not a failure');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(), back: { status: 201, body: 'not json at all' } });
  page.addRow(0).flush();
  page.send();

  check('the round is recorded, because the kitchen has the food',
    page.rounds()[0].lines[0][1], 'Hummus');
  check('and said to be just sent', page.rounds()[0].state,
    'Sent to the kitchen. Not picked up yet.');
  check('with nothing to ask after, so nothing is asked', page.reads().length, 0);
  check('and no refusal claimed', page.says.textContent, '');
}

heading('a ticket id that is not one never reaches an address');
{
  const page = visit({ slug: 'furn', version: 'v1', names: ['Hummus'], store: browser(),
    search: '?t=7', reply: answer(),
    back: { status: 201, body: ticket({ id: '../../api/orders/mine' }) } });
  page.addRow(0).flush();
  page.send();
  page.flush();

  check('the round stands', page.rounds().length, 1);
  check('and not one request was built out of that', page.reads(), []);
}

heading('in Arabic, every one of those sentences is Arabic');
{
  const store = browser();
  const page = visit({ slug: 'furn', version: 'v1', names: ['حمص'], store: store, arabic: true,
    search: '?t=7', lang: 'ar',
    reply: answer({ count: '٢ أصناف', lines: [{ at: 0, name: 'حمص', qty: '٢×',
      price: '٣٫٠٠ $', priceLbp: '٢٧٠٬٠٠٠ ل.ل.' }], total: '٣٫٠٠ $',
    totalLbp: '٢٧٠٬٠٠٠ ل.ل.', totalLabel: 'المجموع', table: '٧' }),
    back: { status: 201, body: ticket() },
    read: { status: 200, body: ticket({ status: 'READY' }) } });
  page.addRow(0).addRow(0).flush();

  check('the button is alive on an Arabic page too', page.reachable(), true);
  page.send();
  page.flush();
  check('the receipt is the server’s Arabic, digits and all',
    [page.rounds()[0].lines[0][0], page.rounds()[0].total],
    ['٢×', 'المجموع٣٫٠٠ $٢٧٠٬٠٠٠ ل.ل.']);
  check('and the state is Arabic', page.rounds()[0].state, 'جاهز.');

  const refused = visit({ slug: 'furn', version: 'v1', names: ['حمص'], store: browser(),
    arabic: true, search: '?t=7', reply: answer(), back: { status: 429, body: {} } });
  refused.addRow(0).flush();
  refused.send();
  check('and so is a refusal', refused.says.textContent,
    'أُرسلت طلبات كثيرة من هذه الطاولة. انتظر لحظة ثم أرسل مرة أخرى.');
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
