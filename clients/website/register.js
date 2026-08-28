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

/*
  Keycloak, for the one authenticated thing on this site.

  The realm's own token endpoint, with the mobile app's public client id and a direct password
  grant. Not an authorization-code redirect, deliberately: a redirect would take somebody who has
  just finished a six-minute form away from the receipt they are reading, and bring them back to a
  page with no application state — the reference, the kind, the address they proved. The password
  they type here is the one they have chosen two seconds earlier on this same screen, so there is no
  credential being borrowed from elsewhere and nothing for a redirect to protect.
*/
const IAM = window.DELIVERY_IAM_BASE || 'http://127.0.0.1:8180';
const REALM = window.DELIVERY_IAM_REALM || 'delivery-platform';
const IAM_CLIENT = 'mobile-app';
const TOKEN_URL = `${IAM}/realms/${REALM}/protocol/openid-connect/token`;

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
    // Was "Upload high-quality scans...". This step cannot upload anything — there is no account to
    // upload as until the application exists — so the line says what the step is instead of asking
    // for something it has no way to take.
    lede: 'What we will ask for. You attach them on the next screen.',
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
  if (state.step === 'documents') fillDocumentPreview();
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
    rows.push(['Documents', 'Attached on the next screen']);

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

// ------------------------------------------------------------------ documents

/*
  What each kind of applicant is asked for, and the only place that list is written down.

  The platform has four document kinds and gives each applicant kind a subset of them: a shop and a
  delivery company are both asked for a commercial registration and the signatory's own identity
  paper; a rider is asked for a driving licence and vehicle papers instead, and riders do not apply
  from this page. The server checks the kind against that subset BEFORE it mints an upload URL, so a
  row drawn here for a kind it does not expect is a row that cannot ever work.

  Which is why the design's other two rows — Tax & VAT Certificate, Active Fleet Insurance — are not
  here. There is no document kind for either, so there is no upload that could carry them and no
  reviewer screen that could show them. A reviewer who needs one asks by email, as they did before.
*/
const DOCUMENTS = {
  MERCHANT: [
    { kind: 'COMMERCIAL_REGISTRATION', title: 'Commercial Registration (CR)' },
    { kind: 'NATIONAL_ID', title: 'Authorized Signatory Owner ID' },
  ],
  CARRIER: [
    { kind: 'COMMERCIAL_REGISTRATION', title: 'Commercial Registration (CR)' },
    { kind: 'NATIONAL_ID', title: 'Authorized Signatory Owner ID' },
  ],
};

/* The service's own list. Offered in the file picker so the wrong file is refused before it is
   read, rather than after it has been sent across somebody's phone connection. */
const ACCEPTED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
const ACCEPT_ATTRIBUTE = `${ACCEPTED_TYPES.join(',')},.jpg,.jpeg,.png,.webp,.pdf`;
const EXTENSION_TYPES = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png',
  webp: 'image/webp', pdf: 'application/pdf',
};

const DOC_GLYPH = '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" aria-hidden="true">'
    + '<path d="M11.6665 1.666H5.0005C4.55852 1.666 4.13464 1.84161 3.82211 2.1542C3.50958 2.46678'
    + ' 3.334 2.89074 3.334 3.3328V16.6672C3.334 17.1093 3.50958 17.5332 3.82211 17.8458C4.13464'
    + ' 18.1584 4.55852 18.334 5.0005 18.334H14.9995C15.4415 18.334 15.8654 18.1584 16.1779'
    + ' 17.8458C16.4904 17.5332 16.666 17.1093 16.666 16.6672V6.6664M11.6665 1.666C11.9303 1.66558'
    + ' 12.1915 1.71734 12.4352 1.81832C12.6789 1.9193 12.9002 2.0675 13.0864 2.25438L16.0761'
    + ' 5.24462C16.2634 5.43089 16.412 5.65244 16.5133 5.89647C16.6145 6.14051 16.6664 6.40219'
    + ' 16.666 6.6664M11.6665 1.666V5.833C11.6665 6.05403 11.7543 6.26601 11.9106 6.4223C12.0668'
    + ' 6.57859 12.2788 6.6664 12.4997 6.6664L16.666 6.6664M8.3335 7.4998H6.667M13.333'
    + ' 10.8334H6.667M13.333 14.167H6.667" stroke="currentColor" stroke-width="2"'
    + ' stroke-linecap="round"/></svg>';

/** The papers this applicant will be asked for. Empty for a kind with no list, never undefined. */
function papersForKind() {
  return DOCUMENTS[state.kind] || [];
}

/** One row, drawn the way the design draws it: tile, title, a line of detail, an action. */
function documentRow(paper) {
  const row = document.createElement('div');
  row.className = 'w-upload';
  row.innerHTML = `<span class="w-upload-tile">${DOC_GLYPH}</span>`
      + '<span class="w-upload-text"><b></b><span></span></span>';
  row.querySelector('b').textContent = paper.title;
  return row;
}

/*
  The step before review: a preview, with nothing to press.

  A disabled Choose File is a control that never works, which is the thing being removed everywhere
  on this site. What sits in its slot is a plain label saying when the row goes live — no affordance
  at all, rather than a broken one.
*/
function fillDocumentPreview() {
  const list = $('documents-preview');
  if (!list) return;
  list.textContent = '';
  papersForKind().forEach((paper) => {
    const row = documentRow(paper);
    row.querySelector('.w-upload-text span').textContent = 'A photo or a PDF';
    const later = document.createElement('span');
    later.className = 'w-later';
    later.textContent = 'After you submit';
    row.appendChild(later);
    list.appendChild(row);
  });
}

// ------------------------------------------------------------------ the applicant's session

/*
  THE TOKENS LIVE HERE AND NOWHERE ELSE — not in localStorage, not in sessionStorage, not in a
  cookie.

  This page is written for the computer in the back of a shop: one machine, several people, a
  browser nobody signs out of. Anything put in web storage from this origin survives the tab being
  closed and is readable by the next person to open the same page — and what would be sitting there
  is a bearer token for an account whose documents are somebody's passport and commercial register.
  A variable dies with the tab, which is exactly the lifetime this session should have.

  The cost is that a refresh means typing the passcode again. That is the correct trade for a
  five-minute task on a machine that is not yours, and it is the only cost: the application itself
  is already in, and the reference on screen has also gone to the address that was verified.
*/
const session = { access: null, refresh: null, expiresAt: 0 };

function keep(token) {
  session.access = token.access_token || null;
  session.refresh = token.refresh_token || null;
  // A minute of slack, and never a window so short that the first request refreshes the token it
  // has just been given: better to renew one that had seconds left than to send one that expired
  // between the check here and the request arriving.
  session.expiresAt = Date.now() + Math.max(30, (token.expires_in || 300) - 60) * 1000;
}

/** Keycloak's errors are a code and a sentence; the code is the part worth reacting to. */
function readTokenError(body, fallback) {
  if (body.error === 'invalid_grant') return 'That passcode was not accepted.';
  if (body.error === 'invalid_client' || body.error === 'unauthorized_client') {
    // The one failure an applicant can do nothing about, said plainly rather than as "invalid".
    return 'This page is not allowed to sign you in yet. Your application is still in — '
        + 'we will ask for your documents by email.';
  }
  return body.error_description || fallback;
}

async function askForToken(form, fallback) {
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(readTokenError(body, fallback));
  keep(body);
}

function signIn(username, password) {
  return askForToken({
    client_id: IAM_CLIENT,
    grant_type: 'password',
    scope: 'openid',
    username,
    password,
  }, 'We could not sign you in just now.');
}

/** Quietly true or quietly false: a failed refresh is not something to put on screen on its own. */
async function refreshSession() {
  if (!session.refresh) return false;
  try {
    await askForToken({
      client_id: IAM_CLIENT,
      grant_type: 'refresh_token',
      refresh_token: session.refresh,
    }, 'expired');
    return true;
  } catch (e) {
    session.access = null;
    session.refresh = null;
    return false;
  }
}

/*
  The session ran out and could not be renewed. The passcode box comes back rather than the page
  pretending nothing happened: this is a slow screen — somebody photographs a licence, finds the
  other one, comes back — and it is entirely normal for a token to age out in the middle of it.
  Typing six digits again is a small thing; a Choose File button that silently fails is not.
*/
function sessionLost() {
  session.access = null;
  session.refresh = null;
  $('account-done').hidden = true;
  $('account-note').hidden = false;
  $('account-block').querySelector('.w-verify').hidden = false;
  const errorBox = $('account-error');
  errorBox.textContent = 'Your sign-in has run out. Type your passcode again to carry on.';
  errorBox.hidden = false;
  return new Error('Your sign-in has run out.');
}

/**
 * A call to the platform with the applicant's token on it.
 *
 * Refreshes ahead of the expiry, and once more on a 401 — a token can be refused for reasons a
 * clock check cannot see, and sending somebody back to the passcode box because a server clock
 * drifted is a poor way to end a form.
 */
async function authFetch(path, options) {
  const settings = options || {};
  if (!session.access) throw new Error('Set your passcode first.');
  if (Date.now() >= session.expiresAt && !(await refreshSession())) throw sessionLost();

  const send = () => fetch(`${API}${path}`, {
    method: settings.method || 'GET',
    headers: Object.assign({}, settings.headers, { Authorization: `Bearer ${session.access}` }),
    body: settings.body,
  });

  let response = await send();
  if (response.status === 401) {
    if (!await refreshSession()) throw sessionLost();
    response = await send();
  }
  return response;
}

/** The body of an onboarding error, which is always `{"message": …}` when the service wrote it. */
async function messageFrom(response, fallback) {
  const body = await response.json().catch(() => ({}));
  return body.message || fallback;
}

// ------------------------------------------------------------------ setting a passcode

$('account-save').addEventListener('click', async () => {
  const button = $('account-save');
  const errorBox = $('account-error');
  const passcode = $('passcode').value;
  const reference = $('reference').textContent.trim();

  errorBox.hidden = true;
  // Six digits, not "at least six characters" — see the note on the field. The service would take
  // a longer one; the phone in this person's pocket would not.
  if (!/^\d{6}$/.test(passcode)) {
    errorBox.textContent = 'Please choose six digits.';
    errorBox.hidden = false;
    return;
  }
  if (!reference || !state.email) {
    // Not reachable from the buttons — this screen only exists once both are set — but a passcode
    // is being sent somewhere, and "somewhere" has to be checked before it is.
    errorBox.textContent = 'We have lost track of your application on this page. It is still in: '
        + 'keep the reference above, and the decision will reach the address you verified.';
    errorBox.hidden = false;
    return;
  }

  button.disabled = true;
  const label = button.textContent;
  button.textContent = 'Setting…';
  try {
    /*
      Two calls, and the first one is allowed to fail.

      Creating the account is refused if this application already has a sign-in — which is exactly
      what happens when somebody sets a passcode, reloads the receipt, and types it again. Signing
      in is the thing that actually matters, so it is attempted either way, and the creation error
      is only shown if signing in fails too. That way "you already did this" resolves itself and a
      real problem still says what it was.
    */
    const created = await fetch(
      `${API}/api/onboarding/applications/${encodeURIComponent(reference)}/account`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: passcode }),
      });
    const creationError = created.ok
        ? null
        : await messageFrom(created, 'We could not set that passcode just now.');

    try {
      await signIn(state.email, passcode);
    } catch (e) {
      throw new Error(creationError || e.message);
    }

    $('passcode').value = '';
    $('account-note').hidden = true;
    $('account-block').querySelector('.w-verify').hidden = true;
    $('account-done').hidden = false;
    await openDocuments();
  } catch (e) {
    errorBox.textContent = e.message;
    errorBox.hidden = false;
  } finally {
    button.disabled = false;
    button.textContent = label;
  }
});

// ------------------------------------------------------------------ uploading

/** The rows, once there is a token to use them with. */
async function openDocuments() {
  const list = $('documents-list');
  const papers = papersForKind();
  if (!papers.length) return;

  list.textContent = '';
  const rows = new Map();
  papers.forEach((paper) => {
    const row = buildUploadRow(paper);
    rows.set(paper.kind, row);
    list.appendChild(row.node);
  });

  $('documents-rule').hidden = false;
  $('documents-block').hidden = false;

  // What is already on file. A passcode typed a second time — after a session ran out mid-upload,
  // say — must show the papers that are already there rather than a pair of empty rows inviting
  // somebody to send them again.
  try {
    const response = await authFetch('/api/onboarding/applications/mine/documents');
    if (response.ok) {
      const existing = await response.json();
      existing.forEach((doc) => {
        const row = rows.get(doc.kind);
        if (row) row.show(doc);
      });
    }
  } catch (e) {
    /* Nothing to say: every row is already in its empty state, which is the truth for a first
       visit and a harmless understatement for a second one. Uploading still works. */
  }
}

function buildUploadRow(paper) {
  const node = documentRow(paper);
  const detail = node.querySelector('.w-upload-text span');

  const pill = document.createElement('span');
  pill.className = 'w-pill';
  pill.hidden = true;

  /*
    The file input is display:none rather than clipped to a pixel, and the button beside it is a
    real button rather than a styled <label>.

    A clipped input is still focusable, which would give every row two tab stops — one of them
    invisible — and a label is not focusable at all, which would give it none. One button that opens
    the picker is one tab stop, works from the keyboard, and is announced with the name of the paper
    it belongs to rather than as the fourth "Choose File" on the screen.
  */
  const picker = document.createElement('input');
  picker.type = 'file';
  picker.className = 'w-file';
  picker.accept = ACCEPT_ATTRIBUTE;

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'w-choose';
  button.textContent = 'Choose File';
  button.setAttribute('aria-label', `Choose a file for ${paper.title}`);
  button.addEventListener('click', () => picker.click());

  node.append(pill, picker, button);
  detail.textContent = 'A photo or a PDF';

  let busy = false;

  function setPill(text, tone) {
    pill.textContent = text;
    pill.className = `w-pill${tone ? ` is-${tone}` : ''}`;
    pill.hidden = false;
  }

  let current = null;

  function show(doc) {
    current = doc;
    node.classList.remove('is-done', 'is-bad');
    button.textContent = 'Replace';
    if (doc.status === 'APPROVED') {
      node.classList.add('is-done');
      setPill('Accepted', 'ok');
      detail.textContent = 'A reviewer has accepted this one.';
    } else if (doc.status === 'REJECTED') {
      node.classList.add('is-bad');
      setPill('Needs a new copy', 'bad');
      // The reviewer's reason, as they wrote it. Somebody who is not told why uploads the same
      // photograph again, unchanged.
      detail.textContent = doc.rejectionReason || 'Please upload another copy.';
    } else {
      setPill('Awaiting review', 'wait');
      detail.textContent = 'Uploaded. Replace it any time before a decision.';
    }
  }

  picker.addEventListener('change', async () => {
    const file = picker.files && picker.files[0];
    picker.value = '';                       // so choosing the same file twice fires again
    if (!file || busy) return;

    const errorBox = $('documents-error');
    errorBox.hidden = true;
    busy = true;
    button.disabled = true;
    setPill('Uploading…', 'wait');

    try {
      show(await uploadDocument(paper.kind, file));
    } catch (e) {
      errorBox.textContent = e.message;
      errorBox.hidden = false;
      // Back to whatever the row honestly is. A failed replacement changed nothing on the server,
      // so a row that already held an accepted document goes back to saying so rather than to
      // looking empty — the old document is still the one on file.
      if (current) {
        show(current);
      } else {
        pill.hidden = true;
        node.classList.remove('is-done', 'is-bad');
        detail.textContent = 'A photo or a PDF';
      }
    } finally {
      busy = false;
      button.disabled = false;
    }
  });

  return { node, show };
}

/** Bytes, in the units somebody would say out loud. */
function megabytes(bytes) {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function typeOf(file) {
  if (ACCEPTED_TYPES.indexOf(file.type) >= 0) return file.type;
  // Some browsers hand over an empty type for a file dragged from an unusual place. The extension
  // is a worse answer than the browser's own sniffing and a much better one than giving up.
  const extension = (file.name.split('.').pop() || '').toLowerCase();
  return EXTENSION_TYPES[extension] || null;
}

/**
 * The three-step upload, exactly as the mobile app does it.
 *
 * 1. Ask this service for a one-shot URL. It checks that the application is the caller's own, that
 *    the kind is one this applicant is asked for, and that the type is one it takes.
 * 2. PUT the bytes STRAIGHT AT STORAGE. They never pass through the onboarding service, which is
 *    why a queue of applicants photographing their papers does not consume its request threads.
 * 3. Confirm, which is what makes the document real and puts it in front of a reviewer.
 */
async function uploadDocument(kind, file) {
  const contentType = typeOf(file);
  if (!contentType) throw new Error('We take JPEG, PNG, WebP or PDF files.');

  const presigned = await authFetch('/api/onboarding/applications/mine/documents/presign', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ kind, contentType }),
  });
  if (!presigned.ok) {
    throw new Error(await messageFrom(presigned, 'We could not start that upload just now.'));
  }
  const ticket = await presigned.json();

  // Checked here rather than after the bytes have gone: the server would refuse the confirm
  // anyway, and by then somebody on a phone connection has uploaded the whole thing for nothing.
  if (ticket.maxSizeBytes && file.size > ticket.maxSizeBytes) {
    throw new Error(`That file is ${megabytes(file.size)} and the limit is `
        + `${megabytes(ticket.maxSizeBytes)}.`);
  }

  // No Authorization header on this one, deliberately: the URL carries its own signature, and
  // S3-compatible storage refuses a request that arrives with two ways of proving who sent it.
  const stored = await fetch(ticket.uploadUrl, {
    method: 'PUT',
    headers: { 'Content-Type': ticket.contentType },
    body: file,
  });
  if (!stored.ok) throw new Error('That upload did not finish. Please try again.');

  const confirmed = await authFetch(
    `/api/onboarding/applications/mine/documents/${ticket.fileId}/confirm`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ kind }),
    });
  if (!confirmed.ok) {
    throw new Error(await messageFrom(confirmed, 'We could not file that document just now.'));
  }
  return confirmed.json();
}

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
