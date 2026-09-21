/*
  The only script on the shop page, and it may only ever hide things.

  The whole catalogue is in the HTML the server sent, so a phone with scripting off, a phone that
  gave up on this file, a chat app's preview and a crawler all see the complete shelf. The rule to
  keep if this file is ever edited: nothing fetched, no markup built, no row the document did not
  arrive with. PublicShopPageFindingTest holds it to that by reading the served file.

  The search field starts hidden in the markup and is revealed here, because a box that did nothing
  when tapped is worse than no box. The jump links beside it are plain anchors and need none of it.

  ES5 on purpose: the handset is whatever was to hand, and a syntax error in an old WebView takes
  the search box down along with the arrow function that caused it.
*/
(function () {
  var find = document.querySelector('.find');
  if (!find) { return; }
  var field = find.querySelector('.q');
  var box = find.querySelector('input');
  var empty = find.querySelector('.qn');
  var jump = find.querySelector('.jump');
  if (!field || !box) { return; }

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

  // Indexed once, off the document, so typing never touches the DOM to read.
  var sections = [];
  var blocks = document.querySelectorAll('.menu .sec');
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
    sections.push({ block: blocks[s], items: items });
  }
  if (!sections.length) { return; }

  function filter() {
    var wanted = fold(box.value);
    var hits = 0;
    for (var s = 0; s < sections.length; s++) {
      var shown = 0;
      var items = sections[s].items;
      for (var i = 0; i < items.length; i++) {
        var keep = !wanted || items[i].text.indexOf(wanted) >= 0;
        items[i].row.hidden = !keep;
        if (keep) { shown++; }
      }
      sections[s].block.hidden = !shown;
      hits += shown;
    }
    if (empty) { empty.hidden = !wanted || hits > 0; }
    // The jump links point at sections a search has just hidden, so they step aside while it runs.
    if (jump) { jump.hidden = !!wanted; }
  }

  field.hidden = false;
  box.addEventListener('input', filter);
  // A search term restored by the browser on a back-navigation, before anything is typed.
  if (box.value) { filter(); }
})();
