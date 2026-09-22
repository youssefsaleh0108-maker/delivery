/*
  The order pad on a shop's menu, for a diner sitting at one of its tables.

  Three rules, and none survives the others being relaxed.

  1. IT NEVER WORKS OUT A PRICE. Every figure a diner sees — a line, the total — arrives from
     /s/{slug}/quote already added up and already spelled in their language, and is printed as the
     string it arrived as. There is no number in the answer to add to another one.

  2. IT WRITES TEXT, NEVER MARKUP. A shop is allowed to call a dish "<script>", and a diner may
     type anything into a note. The server escapes both on the way out; textContent is the other
     door, and there is no third.

  3. NO TABLE, NO PAD. Without ?t=<code> in the address this file reveals nothing at all and the
     page stays the menu it has always been. A shop's link travels in WhatsApp, and somebody
     across the city holding it is not sitting at one of its tables. The server refuses such an
     order too — this is the half a diner can see, not the half that protects the kitchen.

  It may build its own rows, which is what separates it from shop.js — that file may only hide
  things and must stay that way, because the catalogue is what a bad connection depends on.

  ES5 and XMLHttpRequest on purpose: the handset is whatever was to hand. The reasoning lives in
  ShopPageHtml and PublicShopPageService, which do not cross a 3G network.
*/
(function () {
  var panel = document.querySelector('.bk');
  if (!panel) { return; }

  var quoteUrl = panel.getAttribute('data-q');
  var version = panel.getAttribute('data-v');
  if (!quoteUrl || !version) { return; }

  var rows = document.querySelectorAll('.menu .sec .items > li');
  if (!rows.length) { return; }

  var offline = document.querySelector('.bkno');

  /*
    The table, off the address. A short plain code is what a sticker carries — 7, 12, B4 — and
    anything else is dropped rather than cleaned up: this string is drawn on the phone and would
    be drawn on a kitchen's ticket. The server applies the same rule to the value it is sent, and
    only the server's answer decides anything.
  */
  function tableFromUrl() {
    var found = /[?&]t=([^&#]*)/.exec(window.location.search);
    if (!found) { return null; }
    var raw;
    try { raw = decodeURIComponent(found[1].replace(/\+/g, ' ')); } catch (bad) { return null; }
    return /^[A-Za-z0-9-]{1,8}$/.test(raw) ? raw : null;
  }

  var table = tableFromUrl();
  if (!table) {
    // No pad, and the line that would have said "this needs JavaScript" says why instead. The
    // menu above is untouched: it is the whole reason most people open this page.
    if (offline) { offline.textContent = panel.getAttribute('data-nt') || ''; }
    return;
  }

  var slug = quoteUrl.replace(/^.*\/s\//, '').replace(/\/quote.*$/, '');
  var KEY = 'yd.t.' + slug + '.' + table;
  // A meal. Long enough that a table ordering in waves keeps one pad across the evening, short
  // enough that tomorrow's diner at table 7 does not inherit last night's.
  var KEEP = 14400000;

  var list = panel.querySelector('.bl');
  var empty = panel.querySelector('.bkempty');
  var sums = panel.querySelector('.bksum');
  var about = panel.querySelector('.bkwhat');
  var says = panel.querySelector('.bksays');
  var counter = panel.querySelector('.bkn');
  var go = panel.querySelector('.bkgo');
  var peek = document.querySelector('.peek');
  var peekLabel = peek ? peek.textContent : '';
  var more = list.getAttribute('data-more') || '';
  var less = list.getAttribute('data-less') || '';
  var noteLabel = list.getAttribute('data-note') || '';
  var noteEg = list.getAttribute('data-eg') || '';

  // ---------------------------------------------------------------- what is on it

  // [[position, count, note], ...] and nothing else. No name and no price: the page has the names
  // and the server has the prices, and a copy of either in a browser is a copy that goes stale.
  var lines = [];

  function drop() {
    try { localStorage.removeItem(KEY); } catch (gone) { /* nothing to do about it */ }
  }

  function store() {
    if (!lines.length) { drop(); return; }
    try {
      localStorage.setItem(KEY, JSON.stringify({ v: version, l: lines, u: Date.now() }));
    } catch (full) { /* private mode, or the quota: it still works for this visit. */ }
  }

  function forget() {
    lines = [];
    drop();
  }

  function load() {
    var raw;
    try { raw = localStorage.getItem(KEY); } catch (blocked) { return; }
    if (!raw) { return; }
    var held;
    try { held = JSON.parse(raw); } catch (bad) { forget(); return; }
    // The shelf it was chosen from, and how long ago. Either one wrong and it goes: positions
    // against a menu that has changed name something else.
    if (!held || held.v !== version || !held.u || (Date.now() - held.u) > KEEP) {
      forget();
      return;
    }
    var kept = [];
    for (var i = 0; i < (held.l || []).length; i++) {
      var line = held.l[i];
      if (line && typeof line[0] === 'number' && typeof line[1] === 'number'
          && line[0] >= 0 && line[0] < rows.length && line[1] > 0) {
        kept.push([line[0], Math.min(line[1], 20), typeof line[2] === 'string' ? line[2] : '']);
      }
    }
    lines = kept;
  }

  function find(at) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i][0] === at) { return i; }
    }
    return -1;
  }

  function change(at, by) {
    var i = find(at);
    if (i < 0) {
      if (by > 0 && lines.length < 20) { lines.push([at, 1, '']); }
    } else {
      lines[i][1] += by;
      if (lines[i][1] < 1) { lines.splice(i, 1); }
      // What one table plausibly orders in a round. Past it is somebody playing.
      if (lines[i] && lines[i][1] > 20) { lines[i][1] = 20; }
    }
    store();
    draw();
    ask();
  }

  function noted(at, text) {
    var i = find(at);
    if (i < 0) { return; }
    lines[i][2] = text.slice(0, 60);
    store();
    ask();
  }

  // ---------------------------------------------------------------- drawing it

  function text(tag, className, value) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (value) { node.textContent = value; }
    return node;
  }

  function step(at, by, label, name) {
    var button = text('button', 'q', by > 0 ? '+' : '−');
    button.type = 'button';
    button.setAttribute('aria-label', label + ' ' + name);
    button.onclick = function () { change(at, by); };
    return button;
  }

  /* What the diner wants done with it. The only thing anybody types on this page. */
  function noteField(at, value, name) {
    var field = text('input', 'nt', '');
    field.type = 'text';
    field.maxLength = 60;
    field.value = value || '';
    field.placeholder = noteEg;
    field.setAttribute('aria-label', noteLabel + ': ' + name);
    field.onchange = function () { noted(at, field.value); };
    return field;
  }

  /* The lines, off the page's own rows: names and counts only, never money. */
  function draw() {
    while (list.firstChild) { list.removeChild(list.firstChild); }
    for (var i = 0; i < lines.length; i++) {
      var at = lines[i][0];
      var name = nameOf(at);
      var row = text('li', '', '');
      row.appendChild(step(at, -1, less, name));
      row.appendChild(text('span', 'c', String(lines[i][1])));
      row.appendChild(step(at, 1, more, name));
      row.appendChild(text('span', 'n', name));
      row.appendChild(text('span', 'p', ''));
      row.appendChild(noteField(at, lines[i][2], name));
      list.appendChild(row);
    }
    var anything = lines.length > 0;
    empty.hidden = anything;
    list.hidden = !anything;
    if (!anything) {
      clear();
      says.textContent = '';
      counter.hidden = true;
      if (peek) { peek.hidden = true; }
    }
  }

  function nameOf(at) {
    var label = rows[at] ? rows[at].querySelector('.n') : null;
    return label ? label.textContent : '';
  }

  function clear() {
    while (sums.firstChild) { sums.removeChild(sums.firstChild); }
    about.hidden = true;
    // Disabled while there is nowhere for this to go. Sending is the next piece of work.
    go.disabled = true;
  }

  /* The server's answer, printed. Nothing here is computed, compared or rounded. */
  function show(answer) {
    if (answer.stale) {
      // The menu moved under a pad already in this browser. It goes, and the diner is told why
      // rather than shown a total for rows that are no longer these rows.
      forget();
      draw();
      says.textContent = (answer.says && answer.says[0]) || '';
      return;
    }
    var kids = list.childNodes;
    for (var i = 0; i < (answer.lines || []).length && i < kids.length; i++) {
      var line = answer.lines[i];
      var cells = kids[i].childNodes;
      cells[1].textContent = line.qty;
      cells[3].textContent = line.name;
      cells[4].textContent = line.price;
      if (line.priceLbp) { cells[4].appendChild(text('span', 'l', line.priceLbp)); }
      // The note as the server holds it — cut to length and escaped — rather than whatever this
      // phone still had lying about.
      cells[5].value = line.note || '';
      if (line.gone) {
        kids[i].className = 'gone';
        cells[3].appendChild(text('span', 'x', line.gone));
      }
    }

    clear();
    money(answer.totalLabel, answer.total, answer.totalLbp);
    about.hidden = false;

    var trouble = '';
    for (var s = 0; s < (answer.says || []).length; s++) {
      trouble += (s ? ' ' : '') + answer.says[s];
    }
    says.textContent = trouble;
    counter.textContent = answer.count;
    counter.hidden = false;
    if (peek) {
      peek.textContent = peekLabel + ' · ' + answer.count + ' · ' + answer.total;
      peek.hidden = false;
    }
  }

  /* One figure, because a table's order has one: the food. */
  function money(label, value, lira) {
    if (!value) { return; }
    var row = text('div', 'sum', '');
    row.appendChild(text('span', '', label));
    var right = text('span', 'v', value);
    if (lira) { right.appendChild(text('span', 'l', lira)); }
    row.appendChild(right);
    sums.appendChild(row);
  }

  // ---------------------------------------------------------------- asking the server

  var pending = null;
  var inFlight = null;

  function ask() {
    if (!lines.length) { return; }
    // A diner tapping + four times is one question, not four.
    if (pending) { window.clearTimeout(pending); }
    pending = window.setTimeout(send, 250);
  }

  function send() {
    pending = null;
    if (inFlight) { inFlight.abort(); }
    var body = { version: version, table: table, lines: [] };
    for (var i = 0; i < lines.length; i++) {
      body.lines.push({ at: lines[i][0], qty: lines[i][1], note: lines[i][2] });
    }
    var request = new XMLHttpRequest();
    inFlight = request;
    request.open('POST', quoteUrl, true);
    request.setRequestHeader('Content-Type', 'application/json');
    request.onload = function () {
      inFlight = null;
      if (request.status !== 200) { failed(); return; }
      var answer;
      try { answer = JSON.parse(request.responseText); } catch (bad) { failed(); return; }
      show(answer);
    };
    request.onerror = function () { inFlight = null; failed(); };
    request.send(JSON.stringify(body));
  }

  /*
    No total, rather than a total this page worked out. The lines and the counts are the diner's
    own and stay on the screen; the money does not appear at all until the server has said what
    it is.
  */
  function failed() {
    clear();
    says.textContent = panel.getAttribute('data-e') || '';
    if (peek) { peek.hidden = true; }
  }

  // ---------------------------------------------------------------- starting up

  var where = panel.querySelector('.bktab');
  if (where) {
    // The word is the page's own, in the diner's language. The code goes after it in its own
    // element, left to right: it is an identifier off a sticker, not a count, so it is neither
    // turned into another set of digits nor reordered beside Arabic text.
    where.textContent = where.getAttribute('data-l') + ' ';
    var code = text('span', '', table);
    code.dir = 'ltr';
    where.appendChild(code);
    where.hidden = false;
  }

  load();

  for (var r = 0; r < rows.length; r++) {
    var button = rows[r].querySelector('.a');
    if (!button) { continue; }
    button.hidden = false;
    // "Add" and the row's own name, so a menu of a hundred rows is not a hundred buttons called
    // the same thing. Assigned, never written into markup.
    button.setAttribute('aria-label', button.textContent + ' ' + nameOf(r));
    button.onclick = (function (at) {
      return function () { change(at, 1); };
    })(r);
  }

  panel.hidden = false;
  if (offline) { offline.hidden = true; }
  draw();
  ask();
})();
