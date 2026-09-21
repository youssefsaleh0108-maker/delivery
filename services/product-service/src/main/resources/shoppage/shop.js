/*
  The only script on the shop page, and it may only ever hide things or mark them.

  The rule to keep if this file is ever edited: nothing fetched, no markup built, no row the
  document did not arrive with. The whole catalogue is in the HTML the server sent, so a phone with
  scripting off, a phone that gave up on this file, a chat app's preview and a crawler all see the
  complete shelf. PublicShopPageFindingTest holds it to that by reading the served file.

  Two things live here and neither is load-bearing: the search field, and the mark, the sideways
  scroll and the arrow keys on a bar of section links that already navigates on its own.

  ES5 on purpose: the handset is whatever was to hand, and a syntax error in an old WebView takes
  the search box down with it. Comments are short for the same reason — this file crosses a 3G
  network, and ShopPageHtml, where the reasoning lives, does not.
*/
(function () {
  var menu = document.querySelector('.menu');
  if (!menu) { return; }

  var find = menu.querySelector('.find');
  var field = find && find.querySelector('.q');
  var box = find && find.querySelector('input');
  var empty = find && find.querySelector('.qn');
  var bar = menu.querySelector('.bar');
  var chips = bar ? bar.getElementsByTagName('a') : [];
  var rtl = document.documentElement.dir === 'rtl';

  /*
    Arabic is typed several ways for one word: with or without the hamza on an alef, a ta marbuta
    where a reader types a ha, the vowel marks most people skip, a kashida stretching a letter for
    looks. Folded away, so either side's spelling finds the other's.
  */
  function fold(text) {
    return text.toLowerCase()
      .replace(/[\u064B-\u0652\u0640\u0670]/g, '')
      .replace(/[\u0622\u0623\u0625\u0671]/g, '\u0627')
      .replace(/\u0629/g, '\u0647')
      .replace(/[\u0649\u0626]/g, '\u064A')
      .replace(/\u0624/g, '\u0648')
      .replace(/\s+/g, ' ')
      .trim();
  }

  // Indexed once, off the document, so typing never touches the DOM to read. Unpaired, the bar
  // keeps its links and loses only the marking.
  var blocks = menu.querySelectorAll('.sec');
  var paired = !!bar && chips.length === blocks.length;
  var sections = [];
  for (var s = 0; s < blocks.length; s++) {
    var rows = blocks[s].querySelectorAll('.items > li');
    var items = [];
    for (var r = 0; r < rows.length; r++) {
      // Name and description both, so "sesame" finds the kaak whose name never says so.
      var name = rows[r].querySelector('.n');
      var about = rows[r].querySelector('.d');
      items.push({
        row: rows[r],
        text: fold((name ? name.textContent : '') + ' ' + (about ? about.textContent : ''))
      });
    }
    sections.push({ block: blocks[s], items: items, chip: paired ? chips[s] : null });
  }
  if (!sections.length) { return; }

  // ---------------------------------------------------------------- the bar

  var marked = null;

  // The chip into view, sideways, without moving the page. Physical rectangles and a scrollLeft
  // that always counts from the left edge, so these two lines mirror under rtl for free.
  function reveal(chip) {
    var strip = bar.getBoundingClientRect();
    var here = chip.getBoundingClientRect();
    if (here.left < strip.left + 12) {
      bar.scrollLeft += here.left - strip.left - 12;
    } else if (here.right > strip.right - 12) {
      bar.scrollLeft += here.right - strip.right + 12;
    }
  }

  function mark(section) {
    if (section === marked) { return; }
    if (marked && marked.chip) { marked.chip.removeAttribute('aria-current'); }
    marked = section;
    if (section && section.chip) {
      // What a screen reader understands and the stylesheet draws from: one fact, not two.
      section.chip.setAttribute('aria-current', 'true');
      reveal(section.chip);
    }
  }

  // Which section is being read: the last one whose top has gone under the bar, asked of the bar
  // rather than from its height written down twice. A dozen rectangle reads per scroll and no
  // write unless the answer changed — and a short section is not a special case, as it would be
  // for an observer.
  function spy() {
    if (!bar || bar.hidden) { return; }
    // Twelve: a section tapped on the bar lands eight below it and has to count as arrived.
    var line = bar.getBoundingClientRect().bottom + 12;
    var here = null;
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].block.hidden) { continue; }
      // The first section standing, until one has gone under: above the menu there is no answer.
      if (here === null || sections[i].block.getBoundingClientRect().top <= line) {
        here = sections[i];
      }
    }
    mark(here);
  }

  // Arrow keys along the row. Every chip keeps its own tab stop, because with no script they are
  // all a keyboard has, so this only moves focus — and mirrors under rtl.
  function along(event) {
    var key = event.key;
    var step = 0;
    if (key === 'ArrowRight') {
      step = rtl ? -1 : 1;
    } else if (key === 'ArrowLeft') {
      step = rtl ? 1 : -1;
    } else if (key !== 'Home' && key !== 'End') {
      return;
    }
    var to = -1;
    for (var i = 0; i < chips.length; i++) {
      if (chips[i] === event.target) { to = i; }
    }
    if (to < 0) { return; }
    if (key === 'Home') { to = -1; step = 1; }
    if (key === 'End') { to = chips.length; step = -1; }
    // Past any chip a search has hidden: focus on one of those does nothing at all.
    do { to += step; } while (chips[to] && chips[to].hidden);
    if (!chips[to]) { return; }
    event.preventDefault();
    chips[to].focus();
  }

  // ---------------------------------------------------------------- the search

  function filter() {
    var wanted = fold(box.value);
    var hits = 0;
    for (var i = 0; i < sections.length; i++) {
      var shown = 0;
      var items = sections[i].items;
      for (var j = 0; j < items.length; j++) {
        var keep = !wanted || items[j].text.indexOf(wanted) >= 0;
        items[j].row.hidden = !keep;
        if (keep) { shown++; }
      }
      sections[i].block.hidden = !shown;
      // The bar narrows to the sections still standing, rather than vanishing out from under the
      // field being typed into and taking its height with it.
      if (sections[i].chip) { sections[i].chip.hidden = !shown; }
      hits += shown;
    }
    if (empty) { empty.hidden = !wanted || hits > 0; }
    if (bar) { bar.hidden = !hits; }
    spy();
  }

  if (field && box) {
    field.hidden = false;
    box.addEventListener('input', filter);
    // A search term restored by the browser on a back-navigation, before anything is typed.
    if (box.value) { filter(); }
  }
  if (bar) {
    bar.addEventListener('keydown', along);
    window.addEventListener('scroll', spy);
    window.addEventListener('resize', spy);
    // A jump the browser may finish without a scroll event to notice it by.
    window.addEventListener('hashchange', spy);
    spy();
  }
})();
