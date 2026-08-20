/*
  The public site's only moving part: the sign-in chooser.

  Applying used to live here too, as a dialog. It is now its own page at /register — see
  register.js — because a flow that asks somebody to leave and fetch a code from their inbox needs
  to survive a reload, and a sheet that closes on a stray click does not.

  No framework and no build step. The whole page is a few files a browser reads directly, which
  matters more here than anywhere else in the platform: this is the one thing a stranger loads
  before they have any reason to trust us, and it should be quick and it should not break.
*/

const signin = document.getElementById('signin');

document.querySelectorAll('[data-open="signin"]').forEach((button) => {
  button.addEventListener('click', () => signin.showModal());
});

// Clicking the backdrop closes the sheet. A modal with no obvious way out is the reason people
// reload the page — which is harmless here, and was not when this file also held the application
// form.
signin.addEventListener('click', (event) => {
  if (event.target === signin) signin.close();
});
