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

// ------------------------------------------------------------------ language

/*
  Arabic, done the way index.html does it — see the long note at the head of site.js.

  The same storage key, `youdrop-lang`, so the choice somebody made on the landing page is the
  language this page opens in. The same `data-t` convention: the English is written into
  register.html and read out of the DOM on load, never restated in a second dictionary, so a copy
  edit to the markup cannot leave a stale English string behind here. The same fail-open handling of
  localStorage, and the same `lang` / `dir` flip on the root element. Two pages of one site
  disagreeing about how language works would be worse than one page not having it at all.

  Two things go further, and both follow from this being a form rather than a document.

  1. THE MARKUP MECHANISM EXTENDS TO ATTRIBUTES. A placeholder and an aria-label are not
     textContent. `data-t-placeholder` and `data-t-aria` are shaped exactly like `data-t`: the
     English is read off the attribute at load, the Arabic comes from AR under the same key, and a
     key with no Arabic falls back to the English rather than blanking the attribute.

  2. MOST OF THIS PAGE'S WORDS ARE NOT IN THE MARKUP AT ALL. Every heading, every step label, every
     validation line and every upload state is chosen at run time out of the tables below, because
     it depends on the kind of applicant, the step, or what a server just said. Those tables hold
     both languages side by side rather than in a dictionary at the other end of the file — for the
     same reason site.js reads its English out of index.html: the two halves of one string should
     not be able to drift apart unnoticed. What each write puts on screen is remembered in
     `rewrites`, so switching mid-form rewrites what is already showing. A wizard that is Arabic
     until something goes wrong and then English is not a translated wizard.

  What is never translated is what somebody else wrote: a reviewer's reason for refusing a
  document, a validation message from the onboarding service, a business name as it was typed.
  Those are passed through exactly as they arrived.
*/

const STORAGE_KEY = 'youdrop-lang';

/** True while the page is in Arabic. The root element is the one source of truth, as on the site. */
const arabic = () => document.documentElement.lang === 'ar';

/** One pair in the current language. A pair with no Arabic reads as untranslated, never as empty. */
const say = (pair) => (arabic() && pair.ar) || pair.en;

/*
  `{name}` blanks filled in.

  Numbers are left in Western digits on both sides. The fields that produce them are numeric inputs
  and the codes are typed on a number pad, so a receipt that said ٤ while the box beside it said 4
  would be one number written two ways on one screen.
*/
function fill(text, fills) {
  if (!fills) return text;
  return Object.keys(fills).reduce((out, name) => {
    // A blank may be a function when what goes in it is itself translated — the paper's name inside
    // "Choose a file for …". Resolved here, at the moment of writing, so the remembered write picks
    // up the new language on both halves rather than only the sentence around the hole.
    const value = typeof fills[name] === 'function' ? fills[name]() : fills[name];
    return out.split(`{${name}}`).join(value);
  }, text);
}

/*
  The strings this script writes that do not belong to a table of their own.

  Sorted the way the page runs: the frame, then each step, then the receipt.
*/
const SAY = {
  /* the frame */
  'step-of': { en: 'Step {n} of {total}', ar: 'الخطوة {n} من {total}' },
  'percent': { en: '{percent}% Complete', ar: 'اكتمل {percent}%' },
  'continue': { en: 'Continue', ar: 'متابعة' },

  /* what a busy button says while it waits */
  'sending': { en: 'Sending…', ar: 'جارٍ الإرسال…' },
  'checking': { en: 'Checking…', ar: 'جارٍ التحقّق…' },
  'setting': { en: 'Setting…', ar: 'جارٍ الحفظ…' },
  'verify': { en: 'Verify', ar: 'تحقّق' },
  'send-application': { en: 'Send application', ar: 'أرسل الطلب' },

  /* what the form asks for before it will let go of a step */
  'need-name': {
    en: 'Please give the business name and your own name.',
    ar: 'الرجاء إدخال اسم النشاط التجاري واسمك.',
  },
  'need-cr': {
    en: 'Please give your commercial registration number.',
    ar: 'الرجاء إدخال رقم السجل التجاري.',
  },
  'need-fleet-size': {
    en: 'Please give roughly how many riders or drivers you have active.',
    ar: 'الرجاء إدخال عدد تقريبي للمندوبين أو السائقين العاملين لديك.',
  },
  'need-region': {
    en: 'Please name at least one area you would like to work.',
    ar: 'الرجاء ذكر منطقة واحدة على الأقل ترغب بالعمل فيها.',
  },

  /* the two codes */
  'need-email': { en: 'Enter your email address.', ar: 'أدخل بريدك الإلكتروني.' },
  'need-phone': { en: 'Enter a phone number.', ar: 'أدخل رقم هاتف.' },
  'need-code': { en: 'Enter the code we sent you.', ar: 'أدخل الرمز الذي أرسلناه إليك.' },
  'code-send-failed': {
    en: 'We could not send a code just now.',
    ar: 'تعذّر إرسال الرمز في الوقت الحالي.',
  },
  'code-refused': { en: 'That code was not accepted.', ar: 'لم يُقبل هذا الرمز.' },
  /* Both keep their trailing space: the resend button sits on the same line. */
  'code-expired': { en: 'That code has expired. ', ar: 'انتهت صلاحية الرمز. ' },
  'code-expires': { en: 'Expires in {clock}. ', ar: 'تنتهي صلاحيته خلال {clock}. ' },

  /* the review step */
  'sum-applying-as': { en: 'Applying as', ar: 'التقديم بصفة' },
  'sum-shop': { en: 'A shop', ar: 'متجر' },
  'sum-carrier': { en: 'A delivery company', ar: 'شركة توصيل' },
  'sum-email': { en: 'Email', ar: 'البريد الإلكتروني' },
  'sum-phone': { en: 'Phone', ar: 'رقم الهاتف' },
  'sum-verified': { en: '{value} ✓ verified', ar: '{value} ✓ تمّ التحقّق' },
  'sum-not-given': { en: 'Not given', ar: 'لم يُذكر' },
  'sum-registration': { en: 'Registration no.', ar: 'رقم السجل التجاري' },
  'sum-company-type': { en: 'Company type', ar: 'نوع الشركة' },
  'sum-documents': { en: 'Documents', ar: 'المستندات' },
  'sum-documents-later': { en: 'Attached on the next screen', ar: 'تُرفق في الشاشة التالية' },
  'sum-riders': { en: 'Riders / drivers', ar: 'المندوبون / السائقون' },
  'sum-vehicles': { en: 'Vehicles', ar: 'المركبات' },
  'sum-regions': { en: 'Regions', ar: 'المناطق' },
  'sum-hours': { en: 'Hours', ar: 'أوقات العمل' },
  'sum-notes': { en: 'Notes', ar: 'ملاحظات' },
  'submit-failed': {
    en: 'Something went wrong sending that. Please try again.',
    ar: 'حدث خلل أثناء إرسال الطلب. الرجاء المحاولة مرة أخرى.',
  },

  /* the passcode, and the session it buys */
  'passcode-six': { en: 'Please choose six digits.', ar: 'الرجاء اختيار ستة أرقام.' },
  'passcode-refused': { en: 'That passcode was not accepted.', ar: 'لم يُقبل رمز الدخول.' },
  'passcode-failed': {
    en: 'We could not set that passcode just now.',
    ar: 'تعذّر حفظ رمز الدخول في الوقت الحالي.',
  },
  'passcode-first': { en: 'Set your passcode first.', ar: 'اختر رمز الدخول أولاً.' },
  'signin-failed': {
    en: 'We could not sign you in just now.',
    ar: 'تعذّر تسجيل دخولك في الوقت الحالي.',
  },
  'signin-not-allowed': {
    en: 'This page is not allowed to sign you in yet. Your application is still in — '
        + 'we will ask for your documents by email.',
    ar: 'هذه الصفحة غير مخوّلة بتسجيل دخولك بعد. طلبك مُسجّل لدينا، وسنطلب مستنداتك عبر البريد '
        + 'الإلكتروني.',
  },
  'session-lost': { en: 'Your sign-in has run out.', ar: 'انتهت صلاحية جلستك.' },
  'session-lost-note': {
    en: 'Your sign-in has run out. Type your passcode again to carry on.',
    ar: 'انتهت صلاحية جلستك. أدخل رمز الدخول مرة أخرى للمتابعة.',
  },
  'lost-track': {
    en: 'We have lost track of your application on this page. It is still in: keep the reference '
        + 'above, and the decision will reach the address you verified.',
    ar: 'فقدنا أثر طلبك على هذه الصفحة. الطلب مُسجّل لدينا: احتفظ بالرقم المرجعي أعلاه، وسيصلك '
        + 'القرار على العنوان الذي تحقّقت منه.',
  },

  /* the document rows, on the preview step and on the receipt */
  'doc-photo-or-pdf': { en: 'A photo or a PDF', ar: 'صورة أو ملف PDF' },
  'doc-after-submit': { en: 'After you submit', ar: 'بعد إرسال الطلب' },
  'doc-choose': { en: 'Choose File', ar: 'اختر ملفاً' },
  /* "لـ" glued straight onto a definite noun reads badly — لـالسجل. The Arabic takes the noun as an
     apposition instead, which stays correct whichever paper's name lands in the blank. */
  'doc-choose-for': { en: 'Choose a file for {title}', ar: 'اختر ملفاً لمستند {title}' },
  'doc-replace': { en: 'Replace', ar: 'استبدل' },
  'doc-uploading': { en: 'Uploading…', ar: 'جارٍ الرفع…' },
  'doc-accepted': { en: 'Accepted', ar: 'مقبول' },
  'doc-accepted-note': {
    en: 'A reviewer has accepted this one.',
    ar: 'قبِل المراجع هذا المستند.',
  },
  'doc-refused': { en: 'Needs a new copy', ar: 'يحتاج نسخة جديدة' },
  'doc-refused-note': { en: 'Please upload another copy.', ar: 'الرجاء رفع نسخة أخرى.' },
  'doc-waiting': { en: 'Awaiting review', ar: 'بانتظار المراجعة' },
  'doc-waiting-note': {
    en: 'Uploaded. Replace it any time before a decision.',
    ar: 'تمّ الرفع. يمكنك استبداله في أي وقت قبل صدور القرار.',
  },
  'doc-types': {
    en: 'We take JPEG, PNG, WebP or PDF files.',
    ar: 'نقبل ملفات JPEG أو PNG أو WebP أو PDF.',
  },
  'doc-too-big': {
    en: 'That file is {size} and the limit is {limit}.',
    ar: 'حجم هذا الملف {size} والحد الأقصى {limit}.',
  },
  'doc-presign-failed': {
    en: 'We could not start that upload just now.',
    ar: 'تعذّر بدء الرفع في الوقت الحالي.',
  },
  'doc-put-failed': {
    en: 'That upload did not finish. Please try again.',
    ar: 'لم يكتمل الرفع. الرجاء المحاولة مرة أخرى.',
  },
  'doc-confirm-failed': {
    en: 'We could not file that document just now.',
    ar: 'تعذّر حفظ المستند في الوقت الحالي.',
  },
  'megabytes': { en: '{n} MB', ar: '{n} ميغابايت' },

  /* checking back */
  'status-unknown': { en: 'We could not find that reference.', ar: 'لم نعثر على هذا الرقم المرجعي.' },

  /* the request that never reached anybody */
  'network-failed': {
    en: 'We could not reach the server. Check your connection and try again.',
    ar: 'تعذّر الوصول إلى الخادم. تحقّق من اتصالك وحاول مرة أخرى.',
  },
};

/** One of the loose strings above, in the current language, with its blanks filled in. */
const t = (key, fills) => fill(say(SAY[key]), fills);

/*
  The Arabic for what is written into register.html.

  Keys match the `data-t`, `data-t-placeholder` and `data-t-aria` attributes in the markup. The
  English is not here on purpose — it is in the markup, and reading it back from there is what stops
  a copy edit to the HTML from leaving a stale English string in this file.
*/
const AR = {
  /* the frame */
  'brand-copyright': '© 2026 شركة YouDrop للتقنيات.',
  'signin-note': 'مسجّل لدينا من قبل؟',
  'signin-link': 'تسجيل الدخول',
  'lang-aria': 'اللغة',

  /* who is applying */
  'kinds-legend': 'بأي صفة تتقدّم بالطلب؟',
  'kind-shop': 'متجر',
  'kind-shop-note': 'اعرض قائمتك على المدينة كلّها ودعنا نجد لك المندوب',
  'kind-carrier': 'شركة توصيل',
  'kind-carrier-note': 'أدخل أسطولك إلى المنصّة وتصلك الطلبات تلقائياً',
  'business-hint': 'مثال: الوصول السريع للخدمات اللوجستية',
  'contact-hint': 'مثال: أحمد خليل',
  'cr-label': 'رقم السجل التجاري',
  'cr-hint': 'مثال: CR-894211A',
  'company-type': 'نوع الشركة',
  'ct-logistics': 'شركة خدمات لوجستية',
  'ct-courier': 'شركة بريد سريع',
  'ct-freight': 'شحن ونقل بري',
  'ct-sole': 'مؤسسة فردية',
  'ct-other': 'غير ذلك',
  'contact-phone': 'هاتف للتواصل',
  'optional': 'اختياري',

  /* the two codes */
  'email-note': 'نرسل رمزاً من ستة أرقام للتأكّد من أن العنوان يصل إليك. كل ما يلي ذلك — بما في '
      + 'ذلك القرار وطريقة تسجيل الدخول — يذهب إلى هذا العنوان، فليكن عنواناً تستطيع فتحه.',
  'email-label': 'البريد الإلكتروني',
  'phone-note': 'مفيد حين يحتاج أمر يخصّ طلباً إلى حلّ سريع. وإن لم ترغب، تجاوز هذه الخطوة — فهي '
      + 'لا تغيّر شيئاً في طلبك.',
  'phone-label': 'رقم الهاتف',
  'send-code': 'أرسل الرمز',
  'code-label': 'الرمز الذي أرسلناه',
  'verify': 'تحقّق',
  'send-another': 'أرسل رمزاً آخر',
  'verified': 'تمّ التحقّق',
  'skip-this': 'تجاوز هذه الخطوة',
  'back': 'رجوع',
  /* The Continue button's fallback word. Its usual one is written by paint(), out of NEXT_LABEL. */
  'continue': 'متابعة',

  /* the papers, and the fleet */
  'documents-note': 'سترفق هذه المستندات في الشاشة التالية، بعد وصول طلبك واختيارك رمز دخول. لا '
      + 'يُرفع شيء من هذه الخطوة.',
  'fleet-size': 'العدد التقديري للمندوبين أو السائقين العاملين',
  'vehicles-label': 'أنواع المركبات المتوفّرة',
  'veh-motorcycle': 'درّاجات نارية',
  'veh-car': 'سيارات',
  'veh-van': 'فانات',
  'veh-truck': 'شاحنات',
  'regions-label': 'المناطق المفضّلة للعمل',
  'regions-hint': 'مثال: بيروت، جبل لبنان',
  'hours-label': 'أوقات العمل المفضّلة',
  'hours-24': '24 ساعة (خدمة كاملة)',
  'hours-day': 'نهاراً (08:00 – 20:00)',
  'hours-evening': 'مساءً وليلاً (16:00 – 02:00)',
  'hours-weekend': 'عطلة نهاية الأسبوع فقط',
  'hours-other': 'غير ذلك — موضّح في الملاحظات',

  /* sending */
  'send-application': 'أرسل الطلب',
  'review-note': 'نقرأ كل طلب يصلنا، وسنردّ عليك في الحالتين.',

  /* the receipt */
  'receipt-title': 'تمّ إرسال طلبك بنجاح',
  'receipt-lede': 'شكراً لتقدّمك بالطلب. نتحقّق الآن من بيانات نشاطك التجاري، ومن مستندات أسطولك '
      + 'حيث ينطبق ذلك.',
  'your-reference': 'رقمك المرجعي',
  'set-passcode': 'اختر رمز الدخول',
  'account-note': 'ستة أرقام. يسجّل دخولك هنا مباشرةً لترفق مستنداتك، وهو نفسه رمز الدخول الذي '
      + 'تطلبه منك لوحة مفاتيح التطبيق.',
  'passcode-label': 'رمز الدخول',
  'set-it': 'اعتمده',
  'signed-in': 'تمّ تسجيل الدخول',
  'your-documents': 'مستنداتك',
  'documents-note-2': 'صورة أو ملف PDF لكل مستند. يمكنك رفع نسخة أوضح في أي وقت قبل صدور القرار — '
      + 'والنسخة الأحدث هي التي يقرأها المراجع.',
  'whats-next': 'ما الخطوة التالية؟',
  'next1-title': 'تدقيق المستندات',
  'next1-body': 'وحدة علاقات الشركاء لدينا تراجع بيانات تسجيل نشاطك التجاري.',
  'next2-title': 'مكالمة تحقّق',
  'next2-body': 'سنحدّد معك مكالمة قصيرة للتعريف بالخدمة والتأكّد من جاهزيتك.',
  'next3-title': 'تفعيل لوحة التحكّم',
  'next3-body': 'الموافقة تفتح لك لوحة التحكّم. ورمز الدخول الذي اخترته أعلاه هو الذي يُدخلك إليها.',
  'info-line': 'يستغرق التحقّق عادةً من يوم إلى خمسة أيام عمل. ستصلك إشعارات بالبريد الإلكتروني في '
      + 'كل مرحلة.',
  'check-status': 'تحقّق من حالة الطلب',
  'back-to-site': 'العودة إلى الموقع',
};

/* The three markup mechanisms, and the English each one reads back out of the document. */
const translatable = document.querySelectorAll('[data-t]');
const placeheld = document.querySelectorAll('[data-t-placeholder]');
const labelled = document.querySelectorAll('[data-t-aria]');
const toggles = document.querySelectorAll('[data-lang-toggle]');

/* One map per attribute, not one map for all three: an element is allowed to carry a word and a
   placeholder at once, and a single map keyed by node could only remember one of them. */
const english = new Map();
const englishHints = new Map();
const englishLabels = new Map();
translatable.forEach((node) => english.set(node, node.textContent));
placeheld.forEach((node) => englishHints.set(node, node.placeholder));
labelled.forEach((node) => englishLabels.set(node, node.getAttribute('aria-label')));

/*
  Everything this script writes, remembered as the job of writing it again.

  site.js can keep a Map of node → its English, because over there the English is in the document.
  Here it is not: these strings are chosen at run time and the node is often built at run time too.
  So what is kept is the write itself — a closure that puts the same string in the same place in
  whatever language is current. Keyed by node, so the newest write for an element replaces the last
  one and `writeRaw` can drop it entirely when what lands there stops being ours to translate.
*/
const rewrites = new Map();

/** One of our own strings, into an element, remembered. */
function write(node, pair, fills) {
  const job = () => { node.textContent = fill(say(pair), fills); };
  rewrites.set(node, job);
  job();
}

/** Text somebody else wrote — a server message, a name as typed. Written once and left alone. */
function writeRaw(node, text) {
  rewrites.delete(node);
  node.textContent = text;
}

/*
  Whatever the language machinery says this element should say, put back.

  For the buttons that borrow their own label for a moment — "Send code" becomes "Sending…" and then
  becomes "Send code" again. Reading the word out of the DOM before overwriting it would restore the
  language the button was in when the request left, which is the wrong one if the reader switched
  while it was in flight. Both mechanisms are asked in turn: a script write first, then the markup.
*/
function restore(node) {
  const job = rewrites.get(node);
  if (job) {
    job();
    return;
  }
  node.textContent = (arabic() && AR[node.dataset.t]) || english.get(node);
}

/** As `write`, for an aria-label. Its own map: one element can carry both a label and a word. */
const rewriteLabels = new Map();
function relabel(node, pair, fills) {
  const job = () => node.setAttribute('aria-label', fill(say(pair), fills));
  rewriteLabels.set(node, job);
  job();
}

/*
  localStorage throws outright in a few places — a browser set to block site data, some embedded
  webviews — rather than merely returning null. A stored preference is not worth taking a form this
  long down for, so both directions are wrapped and a failure just means the default.
*/
function readStored() {
  try {
    return localStorage.getItem(STORAGE_KEY);
  } catch (error) {
    return null;
  }
}

function store(lang) {
  try {
    localStorage.setItem(STORAGE_KEY, lang);
  } catch (error) {
    /* Nothing to do and nothing worth saying: the page still works, it just forgets. */
  }
}

function apply(lang) {
  const ar = lang === 'ar';

  document.documentElement.lang = ar ? 'ar' : 'en';
  document.documentElement.dir = ar ? 'rtl' : 'ltr';

  /* A key with no Arabic falls back to the English rather than emptying the element — a missing
     translation should read as untranslated, never as missing content. */
  translatable.forEach((node) => {
    node.textContent = ar ? (AR[node.dataset.t] || english.get(node)) : english.get(node);
  });
  placeheld.forEach((node) => {
    const en = englishHints.get(node);
    node.placeholder = ar ? (AR[node.dataset.tPlaceholder] || en) : en;
  });
  labelled.forEach((node) => {
    const en = englishLabels.get(node);
    node.setAttribute('aria-label', ar ? (AR[node.dataset.tAria] || en) : en);
  });

  toggles.forEach((button) => button.setAttribute('aria-pressed', String(ar)));

  /* The wizard's own copy, rebuilt from the tables: the title, the step, the summary, the preview
     rows. Then everything else this script has written and is still on screen — the receipt's
     upload rows, the status line, a countdown — which no rebuild reaches. */
  applyWording();
  paint();
  rewrites.forEach((job, node) => (node.isConnected ? job() : rewrites.delete(node)));
  rewriteLabels.forEach((job, node) => (node.isConnected ? job() : rewriteLabels.delete(node)));
}

toggles.forEach((button) => {
  button.addEventListener('click', () => {
    const next = arabic() ? 'en' : 'ar';
    apply(next);
    store(next);
  });
});

/*
  An error whose message is one of ours, carrying the key it came from.

  Everything on this page that can fail says so in a box, and the box is filled from `e.message` —
  which may hold our sentence or the onboarding service's. Ours should be rewritten when the
  language changes and theirs should not, and the only place that difference is still visible is
  where the error was raised. So it is recorded there.
*/
class Said extends Error {
  constructor(key, fills) {
    super(t(key, fills));
    this.key = key;
    this.fills = fills;
  }
}

/**
 * Puts a failure in its box, in Arabic if it was ours to say and verbatim if it was not.
 *
 * The one failure that is neither: `fetch` rejects with a TypeError when the request never reached
 * anybody — no network, no service, a blocked origin. The browser's words for that are always
 * English and never say anything an applicant can act on, so they are replaced with ours. Every
 * other error keeps its own message, because the alternative is hiding what a server actually said.
 */
function showError(box, failure) {
  const error = failure instanceof TypeError ? new Said('network-failed') : failure;
  if (error.key) write(box, SAY[error.key], error.fills);
  else writeRaw(box, error.message);
  box.hidden = false;
}

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

/*
  The same form for both, with the nouns changed.

  Every value from here down is a `{ en, ar }` pair. These strings have no home in the markup — the
  right one is picked at run time — so both languages are written here, a line apart, where an edit
  to one is an edit in sight of the other.
*/
const WORDING = {
  MERCHANT: {
    hub: { en: 'Merchant Hub', ar: 'مركز التجّار' },
    business: { en: 'Shop name', ar: 'اسم المتجر' },
    contact: { en: 'Your name', ar: 'اسمك' },
    notes: {
      en: 'What do you sell, and where are you?',
      ar: 'ماذا تبيع، وأين يقع متجرك؟',
    },
    fallbackCompany: { en: 'Merchant Partner Application', ar: 'طلب شراكة تاجر' },
  },
  CARRIER: {
    hub: { en: 'Carrier Hub', ar: 'مركز شركات التوصيل' },
    business: { en: 'Company / Business Name', ar: 'اسم الشركة أو النشاط التجاري' },
    contact: { en: 'Owner Full Name', ar: 'الاسم الكامل لصاحب الشركة' },
    notes: {
      en: 'How many riders, and which areas do you cover?',
      ar: 'كم عدد المندوبين لديك، وأي المناطق تغطّونها؟',
    },
    fallbackCompany: { en: 'Carrier Partner Application', ar: 'طلب شراكة شركة توصيل' },
  },
};

/** The tab's own name, which changes with the kind for the same reason the eyebrow does. */
const TITLE = {
  MERCHANT: { en: 'Apply as a shop — YouDrop', ar: 'التقديم كمتجر — YouDrop' },
  CARRIER: {
    en: 'Apply as a delivery company — YouDrop',
    ar: 'التقديم كشركة توصيل — YouDrop',
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
      title: { en: 'Your business', ar: 'نشاطك التجاري' },
      lede: {
        en: 'Tell us who is applying. Nothing here is published anywhere.',
        ar: 'عرّفنا بمن يتقدّم بالطلب. لا يُنشر أي مما هنا في أي مكان.',
      },
      headline: {
        en: 'Put your menu in front of the whole city.',
        ar: 'اعرض قائمتك على المدينة كلّها.',
      },
    },
    CARRIER: {
      title: { en: 'Company Profile', ar: 'بيانات الشركة' },
      lede: {
        en: 'Provide official registration details of your business.',
        ar: 'زوّدنا ببيانات التسجيل الرسمية لنشاطك التجاري.',
      },
      headline: {
        en: 'Start your last-mile delivery partnership.',
        ar: 'ابدأ شراكتك في التوصيل إلى باب العميل.',
      },
    },
  },
  email: {
    title: { en: 'Your email address', ar: 'بريدك الإلكتروني' },
    lede: {
      en: 'We check it reaches you before anything else.',
      ar: 'نتأكّد من وصوله إليك قبل أي شيء آخر.',
    },
    headline: {
      en: 'One address, for everything that follows.',
      ar: 'عنوان واحد لكل ما يأتي بعده.',
    },
  },
  phone: {
    title: { en: 'A phone number', ar: 'رقم هاتف' },
    lede: {
      en: 'Optional, and useful when an order needs sorting out quickly.',
      ar: 'اختياري، ومفيد حين يحتاج طلب إلى حلّ سريع.',
    },
    headline: {
      en: 'A number for when something needs sorting fast.',
      ar: 'رقم نتّصل به حين يحتاج أمر إلى حلّ سريع.',
    },
  },
  documents: {
    title: { en: 'Regulatory Documents', ar: 'المستندات الرسمية' },
    // Was "Upload high-quality scans...". This step cannot upload anything — there is no account to
    // upload as until the application exists — so the line says what the step is instead of asking
    // for something it has no way to take.
    lede: {
      en: 'What we will ask for. You attach them on the next screen.',
      ar: 'ما سنطلبه منك. ترفقه في الشاشة التالية.',
    },
    headline: {
      en: 'Upload credentials to verify your fleet.',
      ar: 'ارفع المستندات التي تُثبت أهلية أسطولك.',
    },
  },
  fleet: {
    title: { en: 'Fleet & Service Scope', ar: 'الأسطول ونطاق الخدمة' },
    lede: {
      en: 'Define your capacity limits and operating capabilities.',
      ar: 'حدّد طاقتك الاستيعابية وقدراتك التشغيلية.',
    },
    headline: {
      en: 'Configure your active service metrics.',
      ar: 'اضبط مؤشّرات خدمتك الفعلية.',
    },
  },
  review: {
    title: { en: 'Check and send', ar: 'راجع وأرسل' },
    lede: {
      en: 'This is what we will read. Go back and change anything that is not right.',
      ar: 'هذا ما سنقرأه. ارجع وعدّل أي معلومة غير صحيحة.',
    },
    headline: {
      en: 'One last look before it reaches us.',
      ar: 'نظرة أخيرة قبل أن يصلنا الطلب.',
    },
  },
};

/*
  The brand panel's paragraph. One per kind rather than one per step: the headline carries the step,
  and a paragraph that changed under it every time would be movement for its own sake.
*/
const BRAND_LEDE = {
  MERCHANT: {
    en: 'Reach the whole city from one menu. Orders, riders and receipts arrive in one place, '
        + 'and we find the rider for you.',
    ar: 'اعرض قائمة واحدة تصل إلى المدينة كلّها. الطلبات والمندوبون والفواتير في مكان واحد، ونحن '
        + 'نجد لك المندوب.',
  },
  CARRIER: {
    en: 'Connect your fleet to the most advanced last-mile delivery network in the region. '
        + 'Real-time routing, automated dispatch, and unified billing.',
    ar: 'اربط أسطولك بأحدث شبكة توصيل إلى باب العميل في المنطقة. توجيه لحظي، وإرسال آلي، وفوترة '
        + 'موحّدة.',
  },
};

/** What the Continue button promises, keyed by where it goes. */
const NEXT_LABEL = {
  email: { en: 'Continue to Email', ar: 'متابعة إلى البريد الإلكتروني' },
  phone: { en: 'Continue to Phone', ar: 'متابعة إلى رقم الهاتف' },
  documents: { en: 'Continue to Documents', ar: 'متابعة إلى المستندات' },
  fleet: { en: 'Next: Fleet Setup', ar: 'التالي: بيانات الأسطول' },
  review: { en: 'Review and Send', ar: 'المراجعة والإرسال' },
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
  write($('business-label'), words.business);
  write($('contact-label'), words.contact);
  write($('notes-label'), words.notes);
  write($('brand-eyebrow'), words.hub);
  write($('receipt-eyebrow'), words.hub);
  write($('brand-lede'), BRAND_LEDE[state.kind]);
  // Fields only one kind of applicant is asked for.
  document.querySelectorAll('[data-kind]').forEach((node) => {
    node.hidden = node.dataset.kind !== state.kind;
  });
  applyCompanyName();
  document.title = say(TITLE[state.kind]);
}

function applyCompanyName() {
  const typed = $('businessName').value.trim();
  // A name somebody typed is theirs and stays exactly as typed; only the stand-in is translated.
  if (typed) writeRaw($('brand-company'), typed);
  else write($('brand-company'), WORDING[state.kind].fallbackCompany);
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
  paint();

  // To the top of the step that just opened, not to the top of the document. On a narrow screen the
  // brand band is above the form and scrolling to the document top would put the progress bar and
  // the first field below the fold — so pressing Continue would look like it moved you backwards.
  document.querySelector('.w-head').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

/*
  Drawing the step the wizard is on, without moving.

  Split out of `go` for the language switch, which redraws every word on the page and must not also
  jump the reader back to the top of a step they were halfway down.
*/
function paint() {
  const flow = FLOW[state.kind];

  document.querySelectorAll('.wstep').forEach((section) => {
    section.hidden = section.dataset.step !== state.step;
  });

  const position = flow.indexOf(state.step) + 1;
  const percent = Math.round((position / flow.length) * 100);
  write($('step-of'), SAY['step-of'], { n: position, total: flow.length });
  write($('step-percent'), SAY.percent, { percent });
  $('bar-fill').style.width = `${percent}%`;

  const copy = COPY[state.step][state.kind] || COPY[state.step];
  write($('step-title'), copy.title);
  write($('step-lede'), copy.lede);
  write($('brand-headline'), copy.headline);

  // Every Continue says where it goes, and where it goes depends on the kind, so it is written at
  // the moment the step opens rather than baked into the markup.
  const next = flow[position];
  const label = document.querySelector(`.wstep[data-step="${state.step}"] .w-next-label`);
  if (label && next) write(label, NEXT_LABEL[next] || SAY.continue);

  if (state.step === 'phone') seedPhone();
  if (state.step === 'documents') fillDocumentPreview();
  if (state.step === 'review') fillSummary();
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
  const fail = (key) => {
    write(error, SAY[key]);
    error.hidden = false;
    return false;
  };

  if (!$('businessName').value.trim() || !$('contactName').value.trim()) {
    return fail('need-name');
  }
  if (state.kind === 'CARRIER' && !$('registrationNumber').value.trim()) {
    return fail('need-cr');
  }
  error.hidden = true;
  return true;
}

function validateFleet() {
  const error = $('fleet-error');
  const fail = (key) => {
    write(error, SAY[key]);
    error.hidden = false;
    return false;
  };

  const size = Number($('fleetSize').value.trim());
  if (!Number.isFinite(size) || size < 1) {
    return fail('need-fleet-size');
  }
  if (!$('operatingRegions').value.trim()) {
    return fail('need-region');
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

  const fail = (error) => showError(errorBox, error);

  const send = async (button) => {
    errorBox.hidden = true;
    const destination = destinationInput.value.trim();
    if (!destination) {
      fail(new Said(channel === 'EMAIL' ? 'need-email' : 'need-phone'));
      return;
    }

    button.disabled = true;
    button.textContent = t('sending');
    try {
      const response = await fetch(`${API}/api/onboarding/verifications`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ channel, destination }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw body.message ? new Error(body.message) : new Said('code-send-failed');
      }

      codeBox.hidden = false;
      codeInput.focus();
      startCooldown(new Date(body.expiresAt));
    } catch (e) {
      fail(e);
    } finally {
      button.disabled = false;
      restore(button);
    }
  };

  sendButton.addEventListener('click', () => send(sendButton));
  resendButton.addEventListener('click', () => send(resendButton));

  confirmButton.addEventListener('click', async () => {
    errorBox.hidden = true;
    const destination = destinationInput.value.trim();
    const code = codeInput.value.trim();
    if (!code) {
      fail(new Said('need-code'));
      return;
    }

    confirmButton.disabled = true;
    confirmButton.textContent = t('checking');
    try {
      const response = await fetch(`${API}/api/onboarding/verifications/confirm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ channel, destination, code }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw body.message ? new Error(body.message) : new Said('code-refused');
      }

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
      fail(e);
    } finally {
      confirmButton.disabled = false;
      restore(confirmButton);
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
        write(expiryLabel, SAY['code-expired']);
        resendButton.disabled = false;
        clearInterval(cooldown);
        return;
      }
      const minutes = Math.floor(secondsLeft / 60);
      const seconds = String(secondsLeft % 60).padStart(2, '0');
      write(expiryLabel, SAY['code-expires'], { clock: `${minutes}:${seconds}` });
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
  LOGISTICS_COMPANY: { en: 'Logistics Company', ar: 'شركة خدمات لوجستية' },
  COURIER_SERVICE: { en: 'Courier Service', ar: 'شركة بريد سريع' },
  FREIGHT_TRUCKING: { en: 'Freight & Trucking', ar: 'شحن ونقل بري' },
  SOLE_PROPRIETOR: { en: 'Individual / Sole Proprietor', ar: 'مؤسسة فردية' },
  OTHER: { en: 'Other', ar: 'غير ذلك' },
};

const VEHICLES = {
  MOTORCYCLE: { en: 'Motorcycles', ar: 'درّاجات نارية' },
  CAR: { en: 'Cars', ar: 'سيارات' },
  VAN: { en: 'Vans', ar: 'فانات' },
  TRUCK: { en: 'Trucks', ar: 'شاحنات' },
};

// ------------------------------------------------------------------ sending

/*
  A cell of the summary, as the job of filling it in.

  Half of what is on this screen is ours and half of it was typed by the applicant. A term and a
  chosen option are translated; a business name, a registration number and a note are not — those
  are somebody's own words and rewriting them in another language would be inventing facts. The two
  are told apart here, once, rather than at each of the sixteen rows below.
*/
const ours = (pair, fills) => (node) => write(node, pair, fills);
const theirs = (text) => (node) => writeRaw(node, text);

/** Several of our pairs read as a list, in the current language's own comma. */
const list = (pairs) => ({
  en: pairs.map((pair) => pair.en).join(', '),
  ar: pairs.map((pair) => pair.ar || pair.en).join('، '),
});

function fillSummary() {
  const words = WORDING[state.kind];
  const rows = [
    [ours(SAY['sum-applying-as']),
      ours(state.kind === 'CARRIER' ? SAY['sum-carrier'] : SAY['sum-shop'])],
    [ours(words.business), theirs($('businessName').value.trim())],
    [ours(words.contact), theirs($('contactName').value.trim())],
    [ours(SAY['sum-email']), ours(SAY['sum-verified'], { value: state.email })],
    [ours(SAY['sum-phone']), state.phone
      ? ours(SAY['sum-verified'], { value: state.phone })
      : ours(SAY['sum-not-given'])],
  ];

  if (state.kind === 'CARRIER') {
    const companyType = $('companyType').value;
    rows.push([ours(SAY['sum-registration']), theirs($('registrationNumber').value.trim())]);
    rows.push([ours(SAY['sum-company-type']),
      COMPANY_TYPES[companyType] ? ours(COMPANY_TYPES[companyType]) : theirs(companyType)]);
    rows.push([ours(SAY['sum-documents']), ours(SAY['sum-documents-later'])]);

    const size = $('fleetSize').value.trim();
    if (size) rows.push([ours(SAY['sum-riders']), theirs(size)]);

    const vehicles = [...document.querySelectorAll('input[name="vehicleType"]:checked')]
        .map((box) => VEHICLES[box.value] || { en: box.value });
    if (vehicles.length) rows.push([ours(SAY['sum-vehicles']), ours(list(vehicles))]);

    const regions = $('operatingRegions').value.trim();
    if (regions) rows.push([ours(SAY['sum-regions']), theirs(regions)]);
    // The chosen option's own text, which the markup mechanism has already translated by the time
    // this runs — so these five phrases are written down once, in register.html, and not again.
    rows.push([ours(SAY['sum-hours']), theirs($('operatingHours').selectedOptions[0].textContent)]);
  }

  const notes = $('notes').value.trim();
  if (notes) rows.push([ours(SAY['sum-notes']), theirs(notes)]);

  $('summary').innerHTML = rows.map(() => '<dt></dt><dd></dd>').join('');
  // Set as text rather than interpolated into the HTML above: every value here was typed by
  // somebody, and building markup out of it is how a business name becomes a script tag.
  const terms = $('summary').querySelectorAll('dt');
  const values = $('summary').querySelectorAll('dd');
  rows.forEach(([term, value], i) => {
    term(terms[i]);
    value(values[i]);
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
  button.textContent = t('sending');

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
      throw attempt.body.message
          ? new Error(attempt.body.message)
          : new Said('submit-failed');
    }

    // The reference is a key, not a sentence: it is written as it arrived in either language.
    writeRaw($('reference'), attempt.body.reference);
    $('wizard').hidden = true;
    $('receipt').hidden = false;
    window.scrollTo({ top: 0 });
  } catch (e) {
    showError(errorBox, e);
  } finally {
    button.disabled = false;
    restore(button);
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
const PAPERS = {
  COMMERCIAL_REGISTRATION: { en: 'Commercial Registration (CR)', ar: 'السجل التجاري' },
  NATIONAL_ID: { en: 'Authorized Signatory Owner ID', ar: 'هوية المفوّض بالتوقيع' },
};

const DOCUMENTS = {
  MERCHANT: [
    { kind: 'COMMERCIAL_REGISTRATION', title: PAPERS.COMMERCIAL_REGISTRATION },
    { kind: 'NATIONAL_ID', title: PAPERS.NATIONAL_ID },
  ],
  CARRIER: [
    { kind: 'COMMERCIAL_REGISTRATION', title: PAPERS.COMMERCIAL_REGISTRATION },
    { kind: 'NATIONAL_ID', title: PAPERS.NATIONAL_ID },
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
  write(row.querySelector('b'), paper.title);
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
    write(row.querySelector('.w-upload-text span'), SAY['doc-photo-or-pdf']);
    const later = document.createElement('span');
    later.className = 'w-later';
    write(later, SAY['doc-after-submit']);
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
function readTokenError(body, fallbackKey) {
  if (body.error === 'invalid_grant') return new Said('passcode-refused');
  if (body.error === 'invalid_client' || body.error === 'unauthorized_client') {
    // The one failure an applicant can do nothing about, said plainly rather than as "invalid".
    return new Said('signin-not-allowed');
  }
  // Keycloak's own sentence, in whatever language the realm was configured in. Not ours to rewrite.
  return body.error_description ? new Error(body.error_description) : new Said(fallbackKey);
}

async function askForToken(form, fallbackKey) {
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(form),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw readTokenError(body, fallbackKey);
  keep(body);
}

function signIn(username, password) {
  return askForToken({
    client_id: IAM_CLIENT,
    grant_type: 'password',
    scope: 'openid',
    username,
    password,
  }, 'signin-failed');
}

/** Quietly true or quietly false: a failed refresh is not something to put on screen on its own. */
async function refreshSession() {
  if (!session.refresh) return false;
  try {
    await askForToken({
      client_id: IAM_CLIENT,
      grant_type: 'refresh_token',
      refresh_token: session.refresh,
    }, 'session-lost');
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
  write(errorBox, SAY['session-lost-note']);
  errorBox.hidden = false;
  return new Said('session-lost');
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
  if (!session.access) throw new Said('passcode-first');
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

/*
  The body of an onboarding error, which is always `{"message": …}` when the service wrote it.

  Returns the failure rather than its words: the service's sentence if it sent one, and otherwise
  ours under the key given, so the box it lands in can tell which of the two it is holding.
*/
async function failureFrom(response, fallbackKey) {
  const body = await response.json().catch(() => ({}));
  return body.message ? new Error(body.message) : new Said(fallbackKey);
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
    showError(errorBox, new Said('passcode-six'));
    return;
  }
  if (!reference || !state.email) {
    // Not reachable from the buttons — this screen only exists once both are set — but a passcode
    // is being sent somewhere, and "somewhere" has to be checked before it is.
    showError(errorBox, new Said('lost-track'));
    return;
  }

  button.disabled = true;
  button.textContent = t('setting');
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
        : await failureFrom(created, 'passcode-failed');

    try {
      await signIn(state.email, passcode);
    } catch (e) {
      throw creationError || e;
    }

    $('passcode').value = '';
    $('account-note').hidden = true;
    $('account-block').querySelector('.w-verify').hidden = true;
    $('account-done').hidden = false;
    await openDocuments();
  } catch (e) {
    showError(errorBox, e);
  } finally {
    button.disabled = false;
    restore(button);
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
  write(button, SAY['doc-choose']);
  // Named for the paper it belongs to, in both halves: the verb from the table and the noun from
  // the same pair the row's own heading uses.
  relabel(button, SAY['doc-choose-for'], { title: () => say(paper.title) });
  button.addEventListener('click', () => picker.click());

  node.append(pill, picker, button);
  write(detail, SAY['doc-photo-or-pdf']);

  let busy = false;

  function setPill(key, tone) {
    write(pill, SAY[key]);
    pill.className = `w-pill${tone ? ` is-${tone}` : ''}`;
    pill.hidden = false;
  }

  let current = null;

  function show(doc) {
    current = doc;
    node.classList.remove('is-done', 'is-bad');
    write(button, SAY['doc-replace']);
    relabel(button, SAY['doc-choose-for'], { title: () => say(paper.title) });
    if (doc.status === 'APPROVED') {
      node.classList.add('is-done');
      setPill('doc-accepted', 'ok');
      write(detail, SAY['doc-accepted-note']);
    } else if (doc.status === 'REJECTED') {
      node.classList.add('is-bad');
      setPill('doc-refused', 'bad');
      // The reviewer's reason, as they wrote it. Somebody who is not told why uploads the same
      // photograph again, unchanged — and it is theirs, so it is never rewritten in Arabic.
      if (doc.rejectionReason) writeRaw(detail, doc.rejectionReason);
      else write(detail, SAY['doc-refused-note']);
    } else {
      setPill('doc-waiting', 'wait');
      write(detail, SAY['doc-waiting-note']);
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
    setPill('doc-uploading', 'wait');

    try {
      show(await uploadDocument(paper.kind, file));
    } catch (e) {
      showError(errorBox, e);
      // Back to whatever the row honestly is. A failed replacement changed nothing on the server,
      // so a row that already held an accepted document goes back to saying so rather than to
      // looking empty — the old document is still the one on file.
      if (current) {
        show(current);
      } else {
        pill.hidden = true;
        node.classList.remove('is-done', 'is-bad');
        write(detail, SAY['doc-photo-or-pdf']);
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
  return t('megabytes', { n: (bytes / (1024 * 1024)).toFixed(1) });
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
  if (!contentType) throw new Said('doc-types');

  const presigned = await authFetch('/api/onboarding/applications/mine/documents/presign', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ kind, contentType }),
  });
  if (!presigned.ok) throw await failureFrom(presigned, 'doc-presign-failed');
  const ticket = await presigned.json();

  // Checked here rather than after the bytes have gone: the server would refuse the confirm
  // anyway, and by then somebody on a phone connection has uploaded the whole thing for nothing.
  if (ticket.maxSizeBytes && file.size > ticket.maxSizeBytes) {
    // Both sizes are read at the moment of writing, so the unit switches with the sentence.
    throw new Said('doc-too-big', {
      size: () => megabytes(file.size),
      limit: () => megabytes(ticket.maxSizeBytes),
    });
  }

  // No Authorization header on this one, deliberately: the URL carries its own signature, and
  // S3-compatible storage refuses a request that arrives with two ways of proving who sent it.
  const stored = await fetch(ticket.uploadUrl, {
    method: 'PUT',
    headers: { 'Content-Type': ticket.contentType },
    body: file,
  });
  if (!stored.ok) throw new Said('doc-put-failed');

  const confirmed = await authFetch(
    `/api/onboarding/applications/mine/documents/${ticket.fileId}/confirm`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ kind }),
    });
  if (!confirmed.ok) throw await failureFrom(confirmed, 'doc-confirm-failed');
  return confirmed.json();
}

// ------------------------------------------------------------------ checking back

$('check').addEventListener('click', async () => {
  const line = $('status');
  const reference = $('reference').textContent.trim();
  if (!reference) return;

  line.hidden = false;
  write(line, SAY.checking);
  try {
    const response = await fetch(
      `${API}/api/onboarding/applications/by-reference/${encodeURIComponent(reference)}`);
    if (!response.ok) throw new Said('status-unknown');
    const [pair, fills] = describe(await response.json());
    write(line, pair, fills);
  } catch (e) {
    showError(line, e);
  }
});

/*
  Plain words. An applicant should not have to know what PROVISIONED means.

  Returns the pair and its blanks rather than a finished sentence, so the line it lands on can be
  rewritten if the language changes while somebody is still reading it.
*/
const STATUS = {
  SUBMITTED: {
    en: 'Received — waiting for someone to read it.',
    ar: 'وصلنا طلبك — بانتظار من يقرأه.',
  },
  IN_REVIEW: { en: 'Someone is reading it now.', ar: 'أحد المراجعين يقرأه الآن.' },
  APPROVED: {
    en: 'Approved. We are setting your account up.',
    ar: 'تمّت الموافقة. نُجهّز حسابك الآن.',
  },
  PROVISIONED: {
    en: 'Approved and ready — check your email to set a password.',
    ar: 'تمّت الموافقة والحساب جاهز — راجع بريدك الإلكتروني لتعيين كلمة المرور.',
  },
  REJECTED: { en: 'Not this time: {reason}', ar: 'ليس هذه المرة: {reason}' },
  // Honest rather than reassuring: somebody has to look at it, and saying "approved" would leave
  // them waiting for an email that is not coming.
  FAILED: {
    en: 'Approved, but setting your account up did not finish. We are on it.',
    ar: 'تمّت الموافقة، لكن تجهيز حسابك لم يكتمل. نحن نعمل على ذلك.',
  },
  UNKNOWN: { en: 'Status: {status}', ar: 'الحالة: {status}' },
};

function describe(application) {
  const known = STATUS[application.status];
  if (!known) return [STATUS.UNKNOWN, { status: application.status }];
  // The reviewer's own reason rides in the blank and is not translated.
  if (application.status === 'REJECTED') return [known, { reason: application.rejectionReason }];
  return [known];
}

// ------------------------------------------------------------------ first paint

applyWording();
go('business');

/*
  Only Arabic needs applying on load, exactly as on the marketing site: the document already holds
  its English, and the two calls above have just written the rest of it in English too.
*/
if (readStored() === 'ar') apply('ar');
