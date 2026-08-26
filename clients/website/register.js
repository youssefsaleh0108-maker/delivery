/*
  Applying, one step at a time.

  The whole reason this is a page with steps rather than one form: two of the fields cannot be
  filled in by typing. They need somebody to leave, open a message, and come back — and a form that
  asks for that has to hold its state while they do, show them where they are, and let them out of
  the part that is optional.

  No framework, same as the rest of the site. The state is a handful of variables and a step name.

  Steps are named, not numbered, because the two kinds of applicant no longer walk the same path: a
  delivery company answers for its fleet and its papers, a shop does not. Numbers hard-coded into
  buttons could not survive that — "back to 3" means a different thing on each path — so the flow
  is one array per kind and every Back, Continue and progress figure is read off it.
*/

const API = window.DELIVERY_API_BASE || 'http://127.0.0.1:8100';

const state = {
  step: 'business',
  kind: 'MERCHANT',
  email: null,          // the NORMALISED address, as the server returned it
  emailToken: null,
  phone: null,
  phoneToken: null,
  skippedPhone: false,
};

const $ = (id) => document.getElementById(id);

/** The path each kind of applicant walks. The only place step order is written down. */
const FLOW = {
  MERCHANT: ['business', 'email', 'phone', 'review'],
  CARRIER: ['business', 'email', 'phone', 'documents', 'fleet', 'review'],
};

/** The same form for both, with the nouns changed. */
const WORDING = {
  MERCHANT: {
    hub: 'Merchant Hub',
    business: 'Shop name',
    contact: 'Your name',
    notes: 'What do you sell, and where are you?',
    fallbackCompany: 'Merchant Partner Application',
  },
  CARRIER: {
    hub: 'Carrier Hub',
    business: 'Company / Business Name',
    contact: 'Owner Full Name',
    notes: 'How many riders, and which areas do you cover?',
    fallbackCompany: 'Carrier Partner Application',
  },
};

/*
  What each step says: the heading and lede on the right, and the headline on the brand panel.

  The brand panel is not decoration that happens to be crimson — it is the half of the screen that
  says why the next thing is being asked for, and the design gives every frame its own line. A
  single fixed slogan would leave the documents step explaining nothing while it asks for papers.
*/
const COPY = {
  business: {
    MERCHANT: {
      title: 'Your business',
      lede: 'Tell us who is applying. Nothing here is published anywhere.',
      headline: 'Put your menu in front of the whole city.',
    },
    CARRIER: {
      title: 'Company Profile',
      lede: 'Provide official registration details of your business.',
      headline: 'Start your last-mile delivery partnership.',
    },
  },
  email: {
    title: 'Your email address',
    lede: 'We check it reaches you before anything else.',
    headline: 'One address, for everything that follows.',
  },
  phone: {
    title: 'A phone number',
    lede: 'Optional, and useful when an order needs sorting out quickly.',
    headline: 'A number for when something needs sorting fast.',
  },
  documents: {
    title: 'Regulatory Documents',
    lede: 'Upload high-quality scans of valid official certificates.',
    headline: 'Upload credentials to verify your fleet.',
  },
  fleet: {
    title: 'Fleet & Service Scope',
    lede: 'Define your capacity limits and operating capabilities.',
    headline: 'Configure your active service metrics.',
  },
  review: {
    title: 'Check and send',
    lede: 'This is what we will read. Go back and change anything that is not right.',
    headline: 'One last look before it reaches us.',
  },
};

/*
  The brand panel's paragraph. One per kind rather than one per step: the headline carries the step,
  and a paragraph that changed under it every time would be movement for its own sake.
*/
const BRAND_LEDE = {
  MERCHANT: 'Reach the whole city from one menu. Orders, riders and receipts arrive in one place, '
      + 'and we find the rider for you.',
  CARRIER: 'Connect your fleet to the most advanced last-mile delivery network in the region. '
      + 'Real-time routing, automated dispatch, and unified billing.',
};

/** What the Continue button promises, keyed by where it goes. */
const NEXT_LABEL = {
  email: 'Continue to Email',
  phone: 'Continue to Phone',
  documents: 'Continue to Documents',
  fleet: 'Next: Fleet Setup',
  review: 'Review and Send',
};

// ------------------------------------------------------------------ arriving

// The landing page links here with the choice already made, so somebody who clicked "Apply as a
// carrier" does not land on a form defaulted to a shop and have to notice.
const requestedKind = new URLSearchParams(location.search).get('kind');
if (requestedKind === 'CARRIER' || requestedKind === 'MERCHANT') {
  state.kind = requestedKind;
  document.querySelector(`input[name="kind"][value="${requestedKind}"]`).checked = true;
}

document.querySelectorAll('input[name="kind"]').forEach((radio) => {
  radio.addEventListener('change', () => {
    if (!radio.checked) return;
    state.kind = radio.value;
    applyWording();
    go('business');
  });
});

// The brand panel's footer is the applicant's own company, as they type it.
$('businessName').addEventListener('input', applyCompanyName);

function applyWording() {
  const words = WORDING[state.kind];
  $('business-label').textContent = words.business;
  $('contact-label').textContent = words.contact;
  $('notes-label').textContent = words.notes;
  $('brand-eyebrow').textContent = words.hub;
  $('receipt-eyebrow').textContent = words.hub;
  $('brand-lede').textContent = BRAND_LEDE[state.kind];
  // Fields only one kind of applicant is asked for.
  document.querySelectorAll('[data-kind]').forEach((node) => {
    node.hidden = node.dataset.kind !== state.kind;
  });
  applyCompanyName();
  document.title = state.kind === 'CARRIER'
      ? 'Apply as a delivery company — YouDrop'
      : 'Apply as a shop — YouDrop';
}

function applyCompanyName() {
  const typed = $('businessName').value.trim();
  $('brand-company').textContent = typed || WORDING[state.kind].fallbackCompany;
}

// ------------------------------------------------------------------ steps

document.querySelectorAll('[data-nav]').forEach((button) => {
  button.addEventListener('click', () => {
    const flow = FLOW[state.kind];
    const here = flow.indexOf(state.step);
    if (here < 0) return;

    if (button.dataset.nav === 'back') {
      go(flow[Math.max(0, here - 1)]);
      return;
    }
    if (!canLeave(state.step)) return;
    go(flow[Math.min(flow.length - 1, here + 1)]);
  });
});

/** The gate on Continue. Steps with nothing to check simply pass. */
function canLeave(step) {
  if (step === 'business') return validateBusiness();
  if (step === 'fleet') return validateFleet();
  return true;
}

function go(step) {
  const flow = FLOW[state.kind];
  // Switching kind can strip the step somebody is standing on (a shop has no fleet step). Falling
  // back to the first step is the only honest answer; it cannot happen from the buttons, only from
  // changing the choice on step one, which is where it lands anyway.
  state.step = flow.includes(step) ? step : flow[0];

  document.querySelectorAll('.wstep').forEach((section) => {
    section.hidden = section.dataset.step !== state.step;
  });

  const position = flow.indexOf(state.step) + 1;
  const percent = Math.round((position / flow.length) * 100);
  $('step-of').textContent = `Step ${position} of ${flow.length}`;
  $('step-percent').textContent = `${percent}% Complete`;
  $('bar-fill').style.width = `${percent}%`;

  const copy = COPY[state.step][state.kind] || COPY[state.step];
  $('step-title').textContent = copy.title;
  $('step-lede').textContent = copy.lede;
  $('brand-headline').textContent = copy.headline;

  // Every Continue says where it goes, and where it goes depends on the kind, so it is written at
  // the moment the step opens rather than baked into the markup.
  const next = flow[position];
  const label = document.querySelector(`.wstep[data-step="${state.step}"] .w-next-label`);
  if (label && next) label.textContent = NEXT_LABEL[next] || 'Continue';

  if (state.step === 'phone') seedPhone();
  if (state.step === 'review') fillSummary();

  // To the top of the step that just opened, not to the top of the document. On a narrow screen the
  // brand band is above the form and scrolling to the document top would put the progress bar and
  // the first field below the fold — so pressing Continue would look like it moved you backwards.
  document.querySelector('.w-head').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/*
  The number typed on step one, carried to the step that verifies it.

  The design puts a contact phone on the company panel; this page proves a phone with a code. Both
  are true at once by making the first one a starting value: it fills the verification field while
  that field is still empty and unproven, and never touches it afterwards, so a number that has
  been verified cannot be quietly replaced by an older draft.
*/
function seedPhone() {
  const seed = $('phoneSeed').value.trim();
  const field = $('contactPhone');
  if (seed && !field.value.trim() && !state.phoneToken) field.value = seed;
}

function validateBusiness() {
  const error = $('page-error');
  const fail = (message) => {
    error.textContent = message;
    error.hidden = false;
    return false;
  };

  if (!$('businessName').value.trim() || !$('contactName').value.trim()) {
    return fail('Please give the business name and your own name.');
  }
  if (state.kind === 'CARRIER' && !$('registrationNumber').value.trim()) {
    return fail('Please give your commercial registration number.');
  }
  error.hidden = true;
  return true;
}

function validateFleet() {
  const error = $('fleet-error');
  const fail = (message) => {
    error.textContent = message;
    error.hidden = false;
    return false;
  };

  const size = Number($('fleetSize').value.trim());
  if (!Number.isFinite(size) || size < 1) {
    return fail('Please give roughly how many riders or drivers you have active.');
  }
  if (!$('operatingRegions').value.trim()) {
    return fail('Please name at least one area you would like to work.');
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
  const flow = FLOW[state.kind];
  state.phone = null;
  state.phoneToken = null;
  state.skippedPhone = true;
  $('contactPhone').value = '';
  go(flow[flow.indexOf('phone') + 1]);
});

// ------------------------------------------------------------------ the details document

/*
  Everything the application carries beyond the five fields the endpoint has always had.

  It goes in a free-form `details` object the reviewer reads back key for key. Only what was
  actually answered goes in: an empty string here becomes an empty row on somebody's review screen,
  which is worse than no row at all.
*/
function collectDetails() {
  if (state.kind !== 'CARRIER') return null;

  const details = {
    commercialRegistrationNumber: $('registrationNumber').value.trim(),
    companyType: $('companyType').value,
  };

  const size = Number($('fleetSize').value.trim());
  if (Number.isFinite(size) && size > 0) details.fleetSize = size;

  const vehicles = [...document.querySelectorAll('input[name="vehicleType"]:checked')]
      .map((box) => box.value);
  if (vehicles.length) details.vehicleTypes = vehicles;

  const regions = $('operatingRegions').value.trim();
  if (regions) details.operatingRegions = regions;
  details.operatingHours = $('operatingHours').value;

  return details;
}

/** Plain words for the review screen, matching the labels the fields carry. */
const COMPANY_TYPES = {
  LOGISTICS_COMPANY: 'Logistics Company',
  COURIER_SERVICE: 'Courier Service',
  FREIGHT_TRUCKING: 'Freight & Trucking',
  SOLE_PROPRIETOR: 'Individual / Sole Proprietor',
  OTHER: 'Other',
};

const VEHICLES = {
  MOTORCYCLE: 'Motorcycles',
  CAR: 'Cars',
  VAN: 'Vans',
  TRUCK: 'Trucks',
};

// ------------------------------------------------------------------ sending

function fillSummary() {
  const words = WORDING[state.kind];
  const rows = [
    ['Applying as', state.kind === 'CARRIER' ? 'A delivery company' : 'A shop'],
    [words.business, $('businessName').value.trim()],
    [words.contact, $('contactName').value.trim()],
    ['Email', `${state.email} ✓ verified`],
    ['Phone', state.phone ? `${state.phone} ✓ verified` : 'Not given'],
  ];

  if (state.kind === 'CARRIER') {
    rows.push(['Registration no.', $('registrationNumber').value.trim()]);
    rows.push(['Company type', COMPANY_TYPES[$('companyType').value] || $('companyType').value]);
    rows.push(['Documents', 'To follow — uploads are not open yet']);

    const size = $('fleetSize').value.trim();
    if (size) rows.push(['Riders / drivers', size]);

    const vehicles = [...document.querySelectorAll('input[name="vehicleType"]:checked')]
        .map((box) => VEHICLES[box.value] || box.value);
    if (vehicles.length) rows.push(['Vehicles', vehicles.join(', ')]);

    const regions = $('operatingRegions').value.trim();
    if (regions) rows.push(['Regions', regions]);
    rows.push(['Hours', $('operatingHours').selectedOptions[0].textContent]);
  }

  const notes = $('notes').value.trim();
  if (notes) rows.push(['Notes', notes]);

  $('summary').innerHTML = rows.map(() => '<dt></dt><dd></dd>').join('');
  // Set as text rather than interpolated into the HTML above: every value here was typed by
  // somebody, and building markup out of it is how a business name becomes a script tag.
  const terms = $('summary').querySelectorAll('dt');
  const values = $('summary').querySelectorAll('dd');
  rows.forEach(([term, value], i) => {
    terms[i].textContent = term;
    values[i].textContent = value;
  });
}

/** One POST of the application. Returns the response and its parsed body together. */
async function postApplication(body) {
  const response = await fetch(`${API}/api/onboarding/applications`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { response, body: await response.json().catch(() => ({})) };
}

$('submit').addEventListener('click', async () => {
  const button = $('submit');
  const errorBox = $('submit-error');
  errorBox.hidden = true;
  button.disabled = true;
  button.textContent = 'Sending…';

  try {
    const application = {
      kind: state.kind,
      businessName: $('businessName').value.trim(),
      contactName: $('contactName').value.trim(),
      contactEmail: state.email,
      emailVerificationToken: state.emailToken,
      contactPhone: state.phone,
      phoneVerificationToken: state.phoneToken,
      notes: $('notes').value.trim() || null,
    };

    const details = collectDetails();
    let attempt = await postApplication(details ? { ...application, details } : application);

    /*
      One retry without the details document.

      The fleet and registration answers ride in `details`, which the endpoint learned to accept in
      the same wave as these screens. A deployment where this page is newer than the service behind
      it would reject the whole application on a field it has never heard of — and the applicant,
      who has just spent five minutes and two verification codes, would be looking at a wizard that
      cannot be finished by any means available to them. So a 400 with details attached is tried
      once more without them: the application lands, and what is lost is the part the old service
      could not have stored anyway.

      It is safe to repeat. The refusal happens while the request is still being read, before either
      verification token is spent, so the same proof works on the second attempt. And it cannot
      quietly swallow a real problem: if the second attempt fails too, its message is what is shown.

      The one thing this must not do is drop the details because they were too large — the endpoint
      caps that document at 16KB. Every field feeding it is length-capped in the markup and the
      whole thing runs to a few hundred bytes, so it cannot reach the cap; if that ever changes,
      this retry has to start reading the message instead of the status.
    */
    if (!attempt.response.ok && attempt.response.status === 400 && details) {
      attempt = await postApplication(application);
    }

    if (!attempt.response.ok) {
      throw new Error(attempt.body.message
          || 'Something went wrong sending that. Please try again.');
    }

    $('reference').textContent = attempt.body.reference;
    $('wizard').hidden = true;
    $('receipt').hidden = false;
    window.scrollTo({ top: 0 });
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

// ------------------------------------------------------------------ first paint

applyWording();
go('business');
