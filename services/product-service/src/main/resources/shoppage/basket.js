/*
  The order pad on a shop's menu, for a diner sitting at one of its tables: what they are choosing,
  what it comes to, the one action that sends it to the kitchen, and what the kitchen is doing with
  what they already sent.

  Three rules, and none survives the others being relaxed.

  1. IT NEVER WORKS OUT A PRICE. Every figure a diner sees — a line, the total, a receipt for a
     round already sent — arrives from /s/{slug}/quote already added up and already spelled in their
     language, and is printed as the string it arrived as. Nothing here adds, multiplies, rounds or
     compares a figure, and there is nothing in the answer to do it with: the one number in that
     document is inside `send`, the request this file posts to the order service and reads no field
     of. A sealed envelope is not a price in a browser.

  2. IT WRITES TEXT, NEVER MARKUP. A shop is allowed to call a dish "<script>", and a diner may
     type anything into a note. The server escapes both on the way out; textContent is the other
     door, and there is no third.

  3. NO TABLE, NO PAD. Without ?t=<code> in the address this file reveals nothing at all and the
     page stays the menu it has always been. A shop's link travels in WhatsApp, and somebody
     across the city holding it is not sitting at one of its tables. The server refuses such an
     order too — this is the half a diner can see, not the half that protects the kitchen.

  And one more, which is the reason this file was written: 4. EVERY REFUSAL IS SAID. A shop that is
  closed, a dish that ran out, a card for a table that does not exist, a kitchen that has had enough
  orders from one table this minute, a price that moved between the quote and the tap — each of them
  reaches the diner as a sentence the server spelled, above a button that is dead for exactly as
  long as the reason lasts. A dead control with nothing beside it is the defect this page shipped
  with. There is one silence left and it is a third of a second long: between a tap on the pad and
  the answer that reprices it, because sending the pad from before a change is worse.

  It may build its own rows, which is what separates it from shop.js — that file may only show, hide
  and mark, and must stay that way, because the catalogue is what a bad connection depends on.

  ES5 and XMLHttpRequest on purpose: the handset is whatever was to hand. The reasoning lives in
  ShopPageHtml, PublicShopPageService and ShopBasket.Send, which do not cross a 3G network.
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
    The table, off the address. A number is what the card carries (ShopTableCodes), and anything
    that is not one is dropped here rather than cleaned up. This is the cheap half of the rule:
    the server checks the number against the tables this shop actually says it has, and only its
    answer decides whether there is a table at all.
  */
  function tableFromUrl() {
    var name = panel.getAttribute('data-t') || 't';
    var found = new RegExp('[?&]' + name + '=([^&#]*)').exec(window.location.search);
    if (!found) { return null; }
    var raw;
    try { raw = decodeURIComponent(found[1].replace(/\+/g, ' ')); } catch (bad) { return null; }
    return /^[0-9]{1,3}$/.test(raw) ? raw : null;
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
  var SENT = 'yd.s.' + slug + '.' + table;
  // Twelve hours: exactly how long the server answers one of these orders for, whatever the
  // kitchen did with it (TableOrderLink.FROM_SENDING). Past it there is nothing left to ask.
  var TOLD = 43200000;
  // Rounds kept. A phone is not an order history; there is no account to make one out of.
  var ROUNDS = 10;

  var list = panel.querySelector('.bl');
  var empty = panel.querySelector('.bkempty');
  var sums = panel.querySelector('.bksum');
  var about = panel.querySelector('.bkwhat');
  var says = panel.querySelector('.bksays');
  var counter = panel.querySelector('.bkn');
  var go = panel.querySelector('.bkgo');
  var goLabel = go.textContent;
  var sentBox = panel.querySelector('.bksent');
  var got = panel.querySelector('.bkgot');
  var peek = document.querySelector('.peek');
  var peekLabel = peek ? peek.textContent : '';
  var more = list.getAttribute('data-more') || '';
  var less = list.getAttribute('data-less') || '';
  var noteLabel = list.getAttribute('data-note') || '';
  var noteEg = list.getAttribute('data-eg') || '';

  // Paths, printed by the page: same-origin whichever hostname served it. ShopPageHtml.SEND_PATH.
  var sendPath = panel.getAttribute('data-s');
  var statusPath = panel.getAttribute('data-ss');

  // "KEY=words|KEY=words", in the page's language: what a ticket's state means at a table, and why
  // a send was refused. A lookup, so nothing here decides what to say — ShopPageText spelled it.
  function spelled(attribute) {
    var words = {};
    var all = (panel.getAttribute(attribute) || '').split('|');
    for (var i = 0; i < all.length; i++) {
      var at = all[i].indexOf('=');
      if (at > 0) { words[all[i].slice(0, at)] = all[i].slice(at + 1); }
    }
    return words;
  }

  var states = spelled('data-st');
  var refusals = spelled('data-r');
  var sendingLabel = panel.getAttribute('data-g') || '';
  // The states nothing follows (ShopPageHtml.TERMINAL_STATES), so this file holds no opinion about
  // a ticket beyond "keep asking or stop", and how often it asks while somebody is looking.
  var settled = (panel.getAttribute('data-sd') || '').split('|');
  var WAIT = 30000;

  /** The sentence for a key, from either list. Never a key, and never a guess. */
  function saying(key) {
    return states[key] || refusals[key] || '';
  }

  // ---------------------------------------------------------------- what is on it

  // [[position, count, note], ...] and nothing else. No name and no price: the page has the names
  // and the server has the prices, and a copy of either in a browser is a copy that goes stale.
  var lines = [];

  /*
    This browser's memory of this table — the pad above and the rounds already sent below — which is
    the only memory either of them has: no account, and no copy on any server. Every door is wrapped
    because private mode and a full quota both throw rather than politely failing, and neither is a
    reason for a pad to stop working for the visit it is in.
  */
  function keep(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch (full) { /* this visit only */ }
  }

  function lose(key) {
    try { localStorage.removeItem(key); } catch (gone) { /* nothing to do about it */ }
  }

  function held(key) {
    var raw;
    try { raw = localStorage.getItem(key); } catch (blocked) { return null; }
    if (!raw) { return null; }
    try { return JSON.parse(raw); } catch (bad) { lose(key); return null; }
  }

  function store() {
    if (!lines.length) { lose(KEY); return; }
    keep(KEY, { v: version, l: lines, u: Date.now() });
  }

  function forget() {
    lines = [];
    lose(KEY);
  }

  function load() {
    var was = held(KEY);
    if (!was) { return; }
    // The shelf it was chosen from, and how long ago. Either one wrong and it goes: positions
    // against a menu that has changed name something else.
    if (was.v !== version || !was.u || (Date.now() - was.u) > KEEP) {
      forget();
      return;
    }
    var kept = [];
    for (var i = 0; i < (was.l || []).length; i++) {
      var line = was.l[i];
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

  // ---------------------------------------------------------------- what has already gone

  /*
    The rounds this phone sent from this table, newest last: the ticket's id, the state it was last
    in, and the receipt — counts, names, line prices, total and its label, every one of them a
    string the server spelled for the pad that went. Strings because a receipt is a record, not
    something to recompute from; so switching language re-words the state and never the receipt.
  */
  var told = [];

  function storeSent() {
    if (!told.length) { told = []; lose(SENT); return; }
    keep(SENT, { r: told });
  }

  /** A ticket id and nothing else, because this one goes into an address. */
  function ticketId(raw) {
    return typeof raw === 'string' && /^[0-9a-fA-F-]{36}$/.test(raw) ? raw : null;
  }

  function loadSent() {
    var was = held(SENT);
    var rounds = (was && was.r) || [];
    for (var i = 0; i < rounds.length; i++) {
      var round = rounds[i];
      // Older than the server would answer for, or not shaped like a round: dropped.
      if (round && round.u && (Date.now() - round.u) < TOLD && round.l && round.l.length) {
        told.push(round);
      }
    }
    storeSent();
  }

  /** Whether a ticket has stopped moving. GONE is a link that has run out of life. */
  function stopped(state) {
    return !!state && (settled.indexOf(state) >= 0 || state === 'GONE');
  }

  /** A figure with the lira note under it, which is how this page draws every price. */
  function lira(node, note) {
    if (note) { node.appendChild(text('span', 'l', note)); }
    return node;
  }

  /* One sent round: what it was, what it came to, and where it has got to. Text, as ever. */
  function drawSent() {
    while (got.firstChild) { got.removeChild(got.firstChild); }
    for (var i = 0; i < told.length; i++) {
      var round = told[i];
      var row = text('li', '', '');
      var was = text('ul', 'bkwas', '');
      for (var j = 0; j < round.l.length; j++) {
        var had = text('li', '', '');
        had.appendChild(text('span', 'c', round.l[j][0]));
        had.appendChild(text('span', 'n', round.l[j][1]));
        had.appendChild(lira(text('span', 'p', round.l[j][2]), round.l[j][3]));
        was.appendChild(had);
      }
      row.appendChild(was);
      var sum = text('p', 'bkwassum', '');
      sum.appendChild(text('span', '', round.k));
      sum.appendChild(lira(text('span', 'v', round.t), round.tl));
      row.appendChild(sum);
      // Empty only for a state nobody spelled: a sentence missing, never a wrong one shown.
      row.appendChild(text('p', 'bkstate', saying(round.s)));
      got.appendChild(row);
    }
    sentBox.hidden = !told.length;
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
    // Dead until this pad has been priced again: see hold().
    hold();
    ask();
  }

  function noted(at, text) {
    var i = find(at);
    if (i < 0) { return; }
    lines[i][2] = text.slice(0, 60);
    store();
    hold();
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

  /*
    No total, and no way to send one. Both because they are the same fact: the figure on the screen
    and the button under it are the server's last answer, and until there is a new one there is
    neither.
  */
  function clear() {
    while (sums.firstChild) { sums.removeChild(sums.firstChild); }
    about.hidden = true;
    hold();
  }

  /*
    Dead, and never silently: the reason is in .bksays whenever the shop is the reason. It also goes
    dead the instant the pad changes, because what it sends is a body built for the pad the server
    priced — a tap between a change and its answer would send the pad from before the change while
    the screen showed the one after. Briefly busy is not a refusal; sending food nobody chose is.
  */
  function hold() {
    ready = null;
    go.disabled = true;
    go.setAttribute('aria-disabled', 'true');
  }

  /*
    Alive, because the server said this pad could be a ticket: `send` is on a quote the shop could
    act on and absent from every other. Nothing here decides it. The receipt is taken from the same
    answer as the body, so what the diner is shown they sent and what went cannot be two pads.
  */
  function allow(answer) {
    ready = { body: answer.send, of: answer };
    go.disabled = false;
    go.setAttribute('aria-disabled', 'false');
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

    // Which table the kitchen would be told, spelled by the server in the page's own language —
    // and absent when the server does not recognise the number the address carried, which is the
    // only thing that decides whether this pad has anywhere to go.
    var where = panel.querySelector('.bktab');
    if (where) {
      where.textContent = answer.table ? where.getAttribute('data-l') + ' ' + answer.table : '';
      where.hidden = !answer.table;
    }

    clear();
    money(answer.totalLabel, answer.total, answer.totalLbp);
    about.hidden = !lines.length;
    if (answer.send) { allow(answer); }

    var trouble = '';
    for (var s = 0; s < (answer.says || []).length; s++) {
      trouble += (s ? ' ' : '') + answer.says[s];
    }
    says.textContent = trouble;
    counter.textContent = answer.count;
    counter.hidden = !lines.length;
    if (peek) {
      peek.textContent = peekLabel + ' · ' + answer.count + ' · ' + answer.total;
      peek.hidden = !lines.length;
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

  /*
    Asked even for an empty pad, once, on load. Two things come back that nothing else can answer:
    whether this shop really has the table the address named — a card peeled off table 7 and stuck
    on the wall, or a number somebody typed — and how to spell it in the language the page is in.
    A diner who scanned a code for a table that does not exist should be told before they choose
    the food, not after.
  */
  function ask() {
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

  // ---------------------------------------------------------------- to the kitchen

  /*
    The one action on this page. What goes is `send`, exactly as the quote that priced this pad
    handed it over, and THIS FILE READS NO FIELD OF IT: it appears below once, as the argument of
    one JSON.stringify. That is how a total crosses a browser without being a number in one.
    ShopBasket.Send has the whole of the reasoning; ShopBasketScriptTest asserts the property.
  */
  var ready = null;
  var going = null;

  function fire() {
    // One tap at a time. A second ROUND is a second ticket, which is what the server makes of it.
    if (!ready || going) { return; }
    going = ready;
    hold();
    go.textContent = sendingLabel;
    says.textContent = '';
    var request = new XMLHttpRequest();
    request.open('POST', sendPath, true);
    request.setRequestHeader('Content-Type', 'application/json');
    request.onload = function () { landed(request); };
    request.onerror = function () { refused('FAILED'); };
    request.send(JSON.stringify(going.body));
  }

  /*
    201 and the kitchen has it. The case worth care is a 201 whose body cannot be read: the order
    EXISTS, so it is kept as sent with what this phone knows and no id to ask after. Calling that a
    failure would invite the diner to send the same food twice.
  */
  function landed(request) {
    if (request.status !== 201) { refused(reasonFor(request)); return; }
    var sent = going;
    var answer = null;
    going = null;
    go.textContent = goLabel;
    try { answer = JSON.parse(request.responseText); } catch (bad) { answer = null; }
    kept(sent, answer && ticketId(answer.id),
        answer && states[answer.status] ? answer.status : 'PLACED');
  }

  /*
    Which sentence a refusal gets, by the code the order service sends — never its prose, which is
    in the language that service speaks rather than the one the diner is reading. 422 is the shop
    refusing: closed, not that card, an item gone, items not on its menu. Which one it was is the
    quote's to say, in the diner's own language and about the shop as it is this second.
  */
  function reasonFor(request) {
    if (request.status === 429) { return 'TOO_MANY'; }
    if (request.status !== 409 && request.status !== 422) { return 'FAILED'; }
    var answer = null;
    try { answer = JSON.parse(request.responseText); } catch (bad) { answer = null; }
    if (answer && answer.code === 'PRICE_CHANGED') { return 'PRICE_CHANGED'; }
    return request.status === 422 ? 'REFUSED' : 'FAILED';
  }

  /* Refused, in words, always — and then priced again, because the quote owns the reason. */
  function refused(why) {
    var sent = going;
    going = null;
    go.textContent = goLabel;
    says.textContent = refusals[why] || refusals.FAILED || '';
    if (why === 'FAILED') {
      // Nothing was learnt about the pad — the request may never have left the phone — so it is not
      // repainted: lines, total and button as they were, and the diner decides to try again.
      if (sent) { allow(sent.of); }
      return;
    }
    hold();
    ask();
  }

  /*
    Sent: the pad is emptied, because the kitchen has this food and a pad still holding it invites
    sending it twice. Nothing is lost — it is in the receipt below, spelled by the server, beside
    what the kitchen is doing with it.
  */
  function kept(sent, id, state) {
    var round = { i: id, s: state, u: Date.now(), t: sent.of.total, tl: sent.of.totalLbp,
      k: sent.of.totalLabel, l: [] };
    var was = sent.of.lines || [];
    for (var i = 0; i < was.length; i++) {
      round.l.push([was[i].qty, was[i].name, was[i].price, was[i].priceLbp || '']);
    }
    told.push(round);
    if (told.length > ROUNDS) { told.splice(0, told.length - ROUNDS); }
    storeSent();
    drawSent();
    watch();
    forget();
    draw();
    // One more question, so the empty pad says what an empty pad says and the table line stays.
    ask();
  }

  /*
    And then the kitchen's turn. A ticket still moving is asked about every half minute and one that
    has stopped is not asked again — and only while somebody is looking, which is what keeps forty
    tables off a restaurant's order service all evening. A 404 is that link's life running out, not
    a failure, and it is said as one.
  */
  var watching = null;

  function watch() {
    if (watching) { window.clearTimeout(watching); watching = null; }
    for (var i = 0; i < told.length; i++) {
      if (told[i].i && !stopped(told[i].s)) {
        watching = window.setTimeout(look, WAIT);
        return;
      }
    }
  }

  function look() {
    watching = null;
    if (document.hidden !== true) {
      for (var i = 0; i < told.length; i++) {
        if (told[i].i && !stopped(told[i].s)) { refresh(told[i]); }
      }
    }
    watch();
  }

  function refresh(round) {
    var request = new XMLHttpRequest();
    request.open('GET', statusPath + round.i, true);
    request.onload = function () {
      var answer = null;
      if (request.status === 404) {
        round.s = 'GONE';
      } else if (request.status === 200) {
        try { answer = JSON.parse(request.responseText); } catch (bad) { return; }
        if (!answer || !states[answer.status]) { return; }
        round.s = answer.status;
      } else {
        // A proxy, or the service having a moment: the round keeps the state it had.
        return;
      }
      storeSent();
      drawSent();
      watch();
    };
    request.onerror = function () { /* asked again on the next turn */ };
    request.send();
  }

  // ---------------------------------------------------------------- starting up

  load();
  loadSent();
  drawSent();
  watch();
  go.onclick = fire;

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
