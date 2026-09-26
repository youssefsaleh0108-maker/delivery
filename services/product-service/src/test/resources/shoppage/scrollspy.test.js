/*
  Which chip the bar marks, asked of shop.js itself.

  The rule is geometry, and geometry is the one thing a MockMvc test cannot see: every other test of
  this page reads the bytes the server sent, and none of them could have caught a bar that names an
  aisle the reader has already scrolled past. So this runs the real, unmodified shop.js over a
  document made of numbers — the numbers measured on a real page at a real width, written down
  here — and asks which chip came out marked.

  It is not a layout engine and must never become one. The Beirut Grill rectangles were read off the
  live page with getBoundingClientRect at each scroll position and pasted in; this replays them, and
  if the page's layout changes they are re-measured rather than adjusted until the test passes. The
  cases after them are built by hand, for shapes a real page has but that shop does not.

  Run: node scrollspy.test.js <path to shop.js>
*/
'use strict';

const fs = require('fs');
const vm = require('vm');

const SOURCE = process.argv[2];
if (!SOURCE) {
  console.error('usage: node scrollspy.test.js <path to shop.js>');
  process.exit(2);
}

// ---------------------------------------------------------------- a document made of numbers

function element(tag, rect) {
  const el = {
    tag: tag,
    hidden: false,
    scrollLeft: 0,
    children: [],
    attributes: {},
    textContent: '',
    rect: rect || { top: 0, bottom: 0, left: 0, right: 0 },
    getBoundingClientRect() {
      return this.rect;
    },
    id: '',
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
    removeAttribute(name) {
      delete this.attributes[name];
    },
    getAttribute(name) {
      return Object.prototype.hasOwnProperty.call(this.attributes, name)
        ? this.attributes[name] : null;
    },
    addEventListener() {},
    focus() {},
    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null;
    },
    querySelectorAll(selector) {
      const found = [];
      const walk = node => node.children.forEach(child => {
        if (child.matches.indexOf(selector) >= 0) { found.push(child); }
        walk(child);
      });
      walk(this);
      return found;
    },
    getElementsByTagName(name) {
      const found = [];
      const walk = node => node.children.forEach(child => {
        if (child.tag === name) { found.push(child); }
        walk(child);
      });
      walk(this);
      return found;
    },
    matches: []
  };
  return el;
}

function add(parent, child, selectors) {
  child.matches = selectors;
  parent.children.push(child);
  return child;
}

/**
 * One rendering of the menu, at one scroll position.
 *
 * @param at {barBottom, innerHeight, pageYOffset, sections:[{name, top, bottom, hidden}]}
 */
function build(at) {
  const menu = element('section');
  menu.matches = ['.menu'];

  const find = add(menu, element('div'), ['.find']);
  add(find, element('p'), ['.q']);
  const box = add(find, element('input'), ['input']);
  box.value = '';
  add(find, element('p'), ['.qn']);

  const bar = add(menu, element('nav', {
    top: at.barBottom - 54, bottom: at.barBottom, left: 0, right: 375
  }), ['.bar']);

  at.sections.forEach((section, i) => {
    // The chips all sit inside the bar, so revealing one scrolls nothing and cannot skew a result.
    const chip = add(bar, element('a', { top: 0, bottom: 39, left: 16, right: 100 }), []);
    chip.textContent = section.name;

    const block = add(menu, element('div', {
      top: section.top, bottom: section.bottom, left: 0, right: 375
    }), ['.sec']);
    block.id = 's' + (i + 1);
    chip.setAttribute('href', '#' + block.id);
    block.hidden = !!section.hidden;
    const list = add(block, element('ul'), ['.items']);
    const row = add(list, element('li'), ['.items > li']);
    const name = add(row, element('span'), ['.n']);
    name.textContent = section.name + ' item ' + i;
  });

  const documentElement = element('html');
  documentElement.dir = 'ltr';
  const doc = element('#document');
  doc.children.push(menu);
  doc.documentElement = documentElement;

  // The section a shop with table ordering OFF ships hidden: a sibling of the menu, not part of
  // it. Absent unless a case asks for one, so not a single scroll-spy case above can feel it.
  if (at.staffOnly) {
    const off = add(doc, element('section'), ['.bkoff']);
    off.hidden = true;
    off.setAttribute('data-t', 't');
    doc.off = off;
  }

  const listeners = {};
  const win = {
    innerHeight: at.innerHeight,
    pageYOffset: at.pageYOffset,
    location: { hash: at.hash || '', search: at.search || '' },
    addEventListener(name, handler) {
      (listeners[name] = listeners[name] || []).push(handler);
    },
    document: doc,
    Math: Math
  };
  win.window = win;

  return {
    win: win,
    doc: doc,
    bar: bar,
    fire(name) {
      (listeners[name] || []).forEach(handler => handler());
    }
  };
}

function markedChip(page) {
  const marked = page.bar.getElementsByTagName('a')
    .filter(chip => chip.getAttribute('aria-current') !== null);
  if (marked.length > 1) {
    return '<' + marked.length + ' chips marked at once>';
  }
  return marked.length ? marked[0].textContent : null;
}

const script = new vm.Script(fs.readFileSync(SOURCE, 'utf8'), { filename: SOURCE });

function run(at) {
  const page = build(at);
  const sandbox = {
    window: page.win,
    document: page.doc,
    Math: Math,
    requestAnimationFrame(fn) { fn(); }
  };
  sandbox.globalThis = sandbox;
  // shop.js runs its own spy() once as it starts, which is the state a reader lands on.
  script.runInNewContext(sandbox);
  // Then whatever the reader did: scrolled here, or tapped a chip to get here.
  page.fire(at.hash ? 'hashchange' : 'scroll');
  return markedChip(page);
}

// ---------------------------------------------------------------- what a real page measured

/**
 * Beirut Grill at 375x812 — three aisles, six items, the shop a dekkane actually is.
 *
 * <p>Every number below was read off the live page with getBoundingClientRect at that exact scroll
 * position, including where the bar was: for most of the descent it has not pinned yet, and a case
 * that assumed a pinned bar with unpinned aisles would be testing a page that cannot exist.
 */
function grill(y, barBottom, boxes) {
  return {
    barBottom: barBottom,
    innerHeight: 812,
    pageYOffset: y,
    sections: [
      { name: 'Desserts', top: boxes[0], bottom: boxes[1] },
      { name: 'Mains', top: boxes[1], bottom: boxes[2] },
      { name: 'Sides', top: boxes[2], bottom: boxes[3] }
    ]
  };
}

const cases = [
  {
    // The whole menu is still below the fold and nothing has been scrolled.
    what: 'Beirut Grill, before anything is scrolled',
    at: grill(0, 1163.66, [1166, 1286, 1492, 1783]),
    expect: 'Desserts'
  },
  {
    what: 'Beirut Grill, with the first aisle coming into view',
    at: grill(700, 463.66, [466, 586, 792, 1083]),
    expect: 'Desserts'
  },
  {
    what: 'Beirut Grill, with the second aisle filling the middle of the screen',
    at: grill(900, 263.66, [266, 386, 592, 883]),
    expect: 'Mains'
  },
  {
    // The bug as it was reported: two whole aisles on the screen, and the bar naming a 20 px
    // sliver of a third that the reader had all but left behind.
    what: 'Beirut Grill, near the foot of the scroll (the reported case)',
    at: grill(1200, 54, [-34, 86, 292, 583]),
    expect: 'Mains'
  },
  {
    // Sides begins at 95 with the scroll spent, so under the old rule it could never be named at
    // any scroll position at all. This is the case the whole change exists for.
    what: 'Beirut Grill, scrolled to the very foot of the document',
    at: grill(1397, 54, [-231, -111, 95, 386]),
    expect: 'Sides'
  },
  {
    // Nothing to scroll at all: the whole shop is on one screen. The bar introduces the shelf
    // rather than going blank, and rather than naming whichever aisle happens to be longest.
    what: 'a menu that fits on one screen, with nothing scrolled',
    at: {
      barBottom: 54, innerHeight: 812, pageYOffset: 0,
      sections: [
        { name: 'Bread', top: 70, bottom: 200 },
        { name: 'Drinks', top: 200, bottom: 480 },
        { name: 'Household', top: 480, bottom: 600 }
      ]
    },
    expect: 'Bread'
  },
  {
    what: 'a long menu, at the top, before anything has been scrolled',
    at: {
      barBottom: 54, innerHeight: 812, pageYOffset: 0,
      sections: [
        { name: 'Bread', top: 900, bottom: 2400 },
        { name: 'Drinks', top: 2400, bottom: 3900 }
      ]
    },
    expect: 'Bread'
  },
  {
    what: 'a long menu, deep inside the second aisle',
    at: {
      barBottom: 54, innerHeight: 812, pageYOffset: 3000, sections: [
        { name: 'Bread', top: -2100, bottom: -600 },
        { name: 'Drinks', top: -600, bottom: 900 },
        { name: 'Household', top: 900, bottom: 2400 }
      ]
    },
    expect: 'Drinks'
  },
  {
    // A search has emptied the middle aisle, so it draws nothing and the one below it moves up.
    // Its chip is hidden too, and the mark steps over it.
    what: 'an aisle a search has hidden is never the one marked',
    at: {
      barBottom: 54, innerHeight: 812, pageYOffset: 3000, sections: [
        { name: 'Bread', top: -2100, bottom: -600 },
        { name: 'Drinks', top: -600, bottom: -600, hidden: true },
        { name: 'Household', top: -600, bottom: 900 }
      ]
    },
    expect: 'Household'
  },
  {
    // Tapping a two-row aisle: it lands under the bar with the long aisle beneath it filling the
    // rest of the screen, and the bar must still name the one the reader asked for.
    what: 'a short aisle tapped on the bar is the one marked',
    at: {
      barBottom: 54, innerHeight: 812, pageYOffset: 600, hash: '#s2', sections: [
        { name: 'Bread', top: -540, bottom: 62 },
        { name: 'Sauces', top: 62, bottom: 122 },
        { name: 'Mains', top: 122, bottom: 1400 }
      ]
    },
    expect: 'Sauces'
  },
  {
    what: 'the last aisle, once the reader has reached the end of a long menu',
    at: {
      barBottom: 54, innerHeight: 812, pageYOffset: 4200, sections: [
        { name: 'Bread', top: -3300, bottom: -1800 },
        { name: 'Drinks', top: -1800, bottom: -300 },
        { name: 'Household', top: -300, bottom: 700 }
      ]
    },
    expect: 'Household'
  }
];

// ------------------------------------------------- and the sentence a scanned card is owed

/**
 * "This shop does not take orders from the table online. Please order with the staff."
 *
 * <p>It is in the document of every shop that has table ordering off, which is nearly every shop
 * there is — a pharmacy, an electronics shop, a florist — because the document is one document and
 * a table code never reaches the server that renders it. So it ships hidden, and the whole of what
 * reveals it is an address carrying a code off a card. These cases are that rule, run.
 *
 * <p>The shapes that are not a card are the shapes basket.js already refuses, because a reader who
 * typed something into the query string has not scanned anything.
 */
function revealed(search) {
  const page = build({
    staffOnly: true, search: search,
    barBottom: 54, innerHeight: 812, pageYOffset: 0,
    sections: [{ name: 'Mezze', top: 54, bottom: 600 }]
  });
  const sandbox = {
    window: page.win,
    document: page.doc,
    Math: Math,
    requestAnimationFrame(fn) { fn(); }
  };
  sandbox.globalThis = sandbox;
  script.runInNewContext(sandbox);
  return !page.doc.off.hidden;
}

const sentenceCases = [
  { what: 'a page shared in a chat, with no code at all, does not mention tables', search: '', expect: false },
  { what: 'the language link on the same page does not either', search: '?lang=ar', expect: false },
  { what: 'a scanned card is told, in words, to order with the staff', search: '?t=7', expect: true },
  { what: 'and so is a two-digit table', search: '?t=12', expect: true },
  { what: 'with the code among other parameters', search: '?lang=ar&t=3', expect: true },
  { what: 'an empty code is not a code', search: '?t=', expect: false },
  { what: 'nor is a word', search: '?t=ABCDEFGHIJ', expect: false },
  { what: 'nor markup somebody typed', search: '?t=%3Cscript%3E', expect: false },
  { what: 'nor an Arabic-Indic seven, which no card carries', search: '?t=%D9%A7', expect: false },
  { what: 'nor a number longer than any card', search: '?t=7777', expect: false }
];

let failed = 0;
cases.forEach(one => {
  const got = run(one.at);
  const ok = got === one.expect;
  if (!ok) { failed++; }
  console.log((ok ? '  ok  ' : 'FAIL  ') + one.what
    + '\n        expected ' + one.expect + ', marked ' + got);
});

sentenceCases.forEach(one => {
  const got = revealed(one.search);
  const ok = got === one.expect;
  if (!ok) { failed++; }
  console.log((ok ? '  ok  ' : 'FAIL  ') + one.what
    + '\n        expected shown=' + one.expect + ', got shown=' + got);
});

const total = cases.length + sentenceCases.length;
console.log(failed ? failed + ' of ' + total + ' failed' : 'all ' + total + ' passed');
process.exit(failed ? 1 : 0);
