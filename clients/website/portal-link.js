// Points every "sign in" link on this site at the portal the deployment actually has.
//
// Three pages leave for the portal — /admin's "Open the Backoffice", the footer's "Sign in" and
// the note above the application form — and each spelled https://portal-dev.youdrop.shop in its
// own markup. So the site had four places that decided which environment it belonged to (those
// three and config.js), and pointing www at production meant finding all of them. Now config.js
// decides, as it already does for the API and the realm.
//
// The anchors ship with NO href on purpose. A shipped one would be a fourth answer to the same
// question — and a stale one at that, since the whole point is that this value moves. The only
// way to see an anchor with no href is for this file to have failed to load at all, which on a
// static site served from its own origin means the deployment is broken; a link to the wrong
// environment would be the worse of the two outcomes.
(function () {
  // The same shape register.js uses: the deployment's value, or the address a developer running
  // the whole stack on their own machine would have (`flutter run --web-port 5010`).
  var base = window.DELIVERY_PORTAL_BASE || 'http://127.0.0.1:5010';
  // No trailing slash, so a link that wants a path can carry its own.
  base = base.replace(/\/+$/, '');

  function apply() {
    var links = document.querySelectorAll('[data-portal-link]');
    for (var i = 0; i < links.length; i++) {
      // The attribute's value, when it has one, is the path within the portal.
      var path = links[i].getAttribute('data-portal-link') || '';
      links[i].setAttribute('href', base + path);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply);
  } else {
    apply();
  }
})();
