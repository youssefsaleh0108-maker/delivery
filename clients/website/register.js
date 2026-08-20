/*
  Applying, one step at a time.

  The whole reason this is a page with steps rather than one form: two of the fields cannot be
  filled in by typing. They need somebody to leave, open a message, and come back — and a form that
  asks for that has to hold its state while they do, show them where they are, and let them out of
  the part that is optional.

  No framework, same as the rest of the site. The state is four variables and a step number.
*/

const API = window.DELIVERY_API_BASE || 'http://127.0.0.1:8100';

const state = {
  step: 1,
  kind: 'MERCHANT',
  email: null,          // the NORMALISED address, as the server returned it
  emailToken: null,
  phone: null,
  phoneToken: null,
  skippedPhone: false,
};

const $ = (id) => document.getElementById(id);

/** The same form for both, with the nouns changed. */
const WORDING = {
  MERCHANT: {
    heading: 'Apply as a shop',
    sub: 'Put your menu in front of the whole city. A few short steps.',
    business: 'Shop name',
    notes: 'What do you sell, and where are you?',
  },
  CARRIER: {
    heading: 'Apply as a delivery company',
    sub: 'Bring your fleet onto the platform. A few short steps.',
    business: 'Company name',
    notes: 'How many riders, and which areas do you cover?',
  },
};

// ------------------------------------------------------------------ arriving

// The landing page links here with the choice already made, so somebody who clicked "Apply as a
// carrier" does not land on a form defaulted to a shop and have to notice.
const requestedKind = new URLSearchParams(location.search).get('kind');
if (requestedKind === 'CARRIER' || requestedKind === 'MERCHANT') {
  state.kind = requestedKind;
  document.querySelector(`input[name="kind"][value="${requestedKind}"]`).checked = true;
}
applyWording();

document.querySelectorAll('input[name="kind"]').forEach((radio) => {
  radio.addEventListener('change', () => {
    state.kind = radio.value;
    applyWording();
  });
});

function applyWording() {
  const words = WORDING[state.kind];
  $('apply-heading').textContent = words.heading;
  $('apply-sub').textContent = words.sub;
  $('business-label').textContent = words.business;
  $('notes-label').textContent = words.notes;
  document.title = `${words.heading} — Delivery`;
}

// ------------------------------------------------------------------ steps

document.querySelectorAll('[data-next]').forEach((button) => {
  button.addEventListener('click', () => {
    if (button.dataset.next === '2' && !validateBusiness()) return;
    if (button.dataset.next === '4') fillSummary();
    go(button.dataset.next);
  });
});

document.querySelectorAll('[data-back]').forEach((button) => {
  button.addEventListener('click', () => go(button.dataset.back));
});

function go(step) {
  state.step = step;
  document.querySelectorAll('.step').forEach((section) => {
    section.hidden = section.dataset.step !== String(step);
  });
  document.querySelectorAll('#steps li').forEach((item) => {
    const n = Number(item.dataset.step);
    const current = Number(step);
    item.classList.toggle('current', n === current);
    // "Done" means passed, not merely visited: going back to change something must not leave the
    // steps after it still ticked.
    item.classList.toggle('done', Number.isFinite(current) ? n < current : true);
  });
  // To the step that just opened, not to the top of the document.
  //
  // Scrolling to the top puts the page heading and the progress rail on screen and the thing you
  // are meant to do next below the fold — so pressing Continue looks like it moved you backwards.
  // The panel is what changed, so the panel is what should be in front of you. scroll-margin-top on
  // .step keeps it clear of the sticky masthead.
  const panel = document.querySelector(`.step[data-step="${step}"]`);
  if (panel) panel.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function validateBusiness() {
  const error = $('page-error');
  if (!$('businessName').value.trim() || !$('contactName').value.trim()) {
    error.textContent = 'Please give the business name and your own name.';
    error.hidden = false;
    return false;
  }
  error.hidden = true;
  return true;
}

// ------------------------------------------------------------------ verifying

/**
 * Wires up one channel's send / confirm / resend.
 *
 * Written once and used twice. Email and phone differ in exactly two ways — which channel name goes
 * to the server, and whether the step can be skipped — and two near-identical copies would be two
 * places to fix the next thing found in either.
 */
function wireVerification(channel, ids, onVerified) {
  const destinationInput = $(ids.destination);
  const codeBox = $(ids.codeBox);
  const codeInput = $(ids.code);
  const errorBox = $(ids.error);
  const verifiedMark = $(ids.verified);
  const sendButton = $(ids.send);
  const confirmButton = $(ids.confirm);
  const resendButton = $(ids.resend);
  const expiryLabel = $(ids.expiry);

  let cooldown = null;

  const fail = (message) => {
    errorBox.textContent = message;
    errorBox.hidden = false;
  };

  const send = async (button) => {
    errorBox.hidden = true;
    const destination = destinationInput.value.trim();
    if (!destination) {
      fail(channel === 'EMAIL' ? 'Enter your email address.' : 'Enter a phone number.');
      return;
    }

    button.disabled = true;
    const original = button.textContent;
    button.textContent = 'Sending…';
    try {
      const response = await fetch(`${API}/api/onboarding/verifications`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ channel, destination }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.message || 'We could not send a code just now.');

      codeBox.hidden = false;
      codeInput.focus();
      startCooldown(new Date(body.expiresAt));
    } catch (e) {
      fail(e.message);
    } finally {
      button.disabled = false;
      button.textContent = original;
    }
  };

  sendButton.addEventListener('click', () => send(sendButton));
  resendButton.addEventListener('click', () => send(resendButton));

  confirmButton.addEventListener('click', async () => {
    errorBox.hidden = true;
    const destination = destinationInput.value.trim();
    const code = codeInput.value.trim();
    if (!code) {
      fail('Enter the code we sent you.');
      return;
    }

    confirmButton.disabled = true;
    confirmButton.textContent = 'Checking…';
    try {
      const response = await fetch(`${API}/api/onboarding/verifications/confirm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ channel, destination, code }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.message || 'That code was not accepted.');

      // The server's spelling of the address, not the one that was typed. It normalises — lower
      // case, punctuation out of phone numbers — and the application has to carry exactly what was
      // verified, or it is refused for a reason nobody can see on screen.
      destinationInput.value = body.destination;
      onVerified(body.destination, body.token);

      codeBox.hidden = true;
      verifiedMark.hidden = false;
      destinationInput.readOnly = true;
      sendButton.hidden = true;
      if (cooldown) clearInterval(cooldown);
    } catch (e) {
      fail(e.message);
    } finally {
      confirmButton.disabled = false;
      confirmButton.textContent = 'Verify';
    }
  });

  // Changing the address after verifying it un-verifies it. Otherwise somebody could confirm one
  // address, edit the field, and submit a different one — which the server would refuse, but only
  // after they had finished the whole form.
  destinationInput.addEventListener('input', () => {
    if (verifiedMark.hidden) return;
    verifiedMark.hidden = true;
    sendButton.hidden = false;
    destinationInput.readOnly = false;
    onVerified(null, null);
  });

  function startCooldown(expiresAt) {
    resendButton.disabled = true;
    if (cooldown) clearInterval(cooldown);

    const tick = () => {
      const secondsLeft = Math.max(0, Math.round((expiresAt - Date.now()) / 1000));
      if (secondsLeft === 0) {
        expiryLabel.textContent = 'That code has expired. ';
        resendButton.disabled = false;
        clearInterval(cooldown);
        return;
      }
      const minutes = Math.floor(secondsLeft / 60);
      const seconds = String(secondsLeft % 60).padStart(2, '0');
      expiryLabel.textContent = `Expires in ${minutes}:${seconds}. `;
      // The server refuses another code for the first minute. The button follows that rather than
      // letting somebody press it into a refusal.
      resendButton.disabled = (expiresAt - Date.now()) > (9 * 60 + 1) * 1000;
    };
    tick();
    cooldown = setInterval(tick, 1000);
  }
}

wireVerification('EMAIL', {
  destination: 'contactEmail', codeBox: 'email-code-box', code: 'email-code',
  error: 'email-error', verified: 'email-verified', send: 'email-send',
  confirm: 'email-confirm', resend: 'email-resend', expiry: 'email-expiry',
}, (destination, token) => {
  state.email = destination;
  state.emailToken = token;
  $('email-continue').disabled = !token;
});

wireVerification('PHONE', {
  destination: 'contactPhone', codeBox: 'phone-code-box', code: 'phone-code',
  error: 'phone-error', verified: 'phone-verified', send: 'phone-send',
  confirm: 'phone-confirm', resend: 'phone-resend', expiry: 'phone-expiry',
}, (destination, token) => {
  state.phone = destination;
  state.phoneToken = token;
  state.skippedPhone = false;
  $('phone-continue').disabled = !token;
});

// Skipping clears the number as well as the proof. A number left in the field but not verified
// would otherwise be submitted unverified and refused by the server.
$('phone-skip').addEventListener('click', () => {
  state.phone = null;
  state.phoneToken = null;
  state.skippedPhone = true;
  $('contactPhone').value = '';
  fillSummary();
  go(4);
});

// ------------------------------------------------------------------ sending

function fillSummary() {
  const rows = [
    ['Applying as', state.kind === 'CARRIER' ? 'A delivery company' : 'A shop'],
    [WORDING[state.kind].business, $('businessName').value.trim()],
    ['Your name', $('contactName').value.trim()],
    ['Email', `${state.email} ✓ verified`],
    ['Phone', state.phone ? `${state.phone} ✓ verified` : 'Not given'],
  ];
  const notes = $('notes').value.trim();
  if (notes) rows.push(['Notes', notes]);

  $('summary').innerHTML = rows
    .map(([term, value]) => `<dt></dt><dd></dd>`)
    .join('');
  // Set as text rather than interpolated into the HTML above: every value here was typed by
  // somebody, and building markup out of it is how a business name becomes a script tag.
  const terms = $('summary').querySelectorAll('dt');
  const values = $('summary').querySelectorAll('dd');
  rows.forEach(([term, value], i) => {
    terms[i].textContent = term;
    values[i].textContent = value;
  });
}

$('submit').addEventListener('click', async () => {
  const button = $('submit');
  const errorBox = $('submit-error');
  errorBox.hidden = true;
  button.disabled = true;
  button.textContent = 'Sending…';

  try {
    const response = await fetch(`${API}/api/onboarding/applications`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        kind: state.kind,
        businessName: $('businessName').value.trim(),
        contactName: $('contactName').value.trim(),
        contactEmail: state.email,
        emailVerificationToken: state.emailToken,
        contactPhone: state.phone,
        phoneVerificationToken: state.phoneToken,
        notes: $('notes').value.trim() || null,
      }),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(body.message || 'Something went wrong sending that. Please try again.');
    }

    $('reference').textContent = body.reference;
    go('done');
  } catch (e) {
    errorBox.textContent = e.message;
    errorBox.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = 'Send application';
  }
});

// ------------------------------------------------------------------ checking back

$('check').addEventListener('click', async () => {
  const line = $('status');
  const reference = $('reference').textContent.trim();
  if (!reference) return;

  line.hidden = false;
  line.textContent = 'Checking…';
  try {
    const response = await fetch(
      `${API}/api/onboarding/applications/by-reference/${encodeURIComponent(reference)}`);
    if (!response.ok) throw new Error('We could not find that reference.');
    line.textContent = describe(await response.json());
  } catch (e) {
    line.textContent = e.message;
  }
});

/** Plain words. An applicant should not have to know what PROVISIONED means. */
function describe(application) {
  switch (application.status) {
    case 'SUBMITTED':
      return 'Received — waiting for someone to read it.';
    case 'IN_REVIEW':
      return 'Someone is reading it now.';
    case 'APPROVED':
      return 'Approved. We are setting your account up.';
    case 'PROVISIONED':
      return 'Approved and ready — check your email to set a password.';
    case 'REJECTED':
      return `Not this time: ${application.rejectionReason}`;
    case 'FAILED':
      // Honest rather than reassuring: somebody has to look at it, and saying "approved" would
      // leave them waiting for an email that is not coming.
      return 'Approved, but setting your account up did not finish. We are on it.';
    default:
      return `Status: ${application.status}`;
  }
}
