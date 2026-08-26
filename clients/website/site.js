/*
  The public site's only moving part: the language switch.

  Applying used to live here too, as a dialog. It is now its own page at /register — see
  register.js — because a flow that asks somebody to leave and fetch a code from their inbox needs
  to survive a reload, and a sheet that closes on a stray click does not. The sign-in chooser that
  stood here went the same way for a simpler reason: it offered two doors that now resolve to the
  same portal, so it was a question with one answer. The footer links straight to it.

  No framework and no build step. The whole page is a few files a browser reads directly, which
  matters more here than anywhere else in the platform: this is the one thing a stranger loads
  before they have any reason to trust us, and it should be quick and it should not break.

  --------------------------------------------------------------------------------------------
  How the switch works, and why it works this way.

  The page ships in English, written into the HTML. That is the whole no-JavaScript story: with
  scripting off, or before this file has arrived, a reader gets a complete English page and a
  button that does nothing — not an empty page waiting for a dictionary to populate it.

  Arabic lives in the dictionary below and is applied in place. Nothing is fetched, so switching is
  instant and works offline. The English is not duplicated here: it is read out of the DOM on load
  and kept in a Map, which means the two languages can never drift apart in the one direction that
  matters — a copy edit to the English in index.html is picked up automatically.
  --------------------------------------------------------------------------------------------
*/

const STORAGE_KEY = 'youdrop-lang';

const AR = {
  /* navigation and calls to action */
  'nav-merchants': 'للتجّار',
  'nav-carriers': 'لشركات الشحن',
  'nav-riders': 'للمندوبين',
  'nav-customers': 'للعملاء',
  'cta-get-started': 'ابدأ الآن',
  'cta-merchant': 'ابدأ كتاجر',
  'cta-rider': 'انضم كمندوب',
  'cta-shop': 'افتح متجرك الآن',
  'cta-partner': 'كن شريكاً لنا',
  'cta-download': 'حمّل تطبيق العملاء',
  'soon': 'قريباً',

  /* hero */
  'hero-eyebrow': '⚡ منظومة موحّدة للخدمات اللوجستية والتوصيل',
  'hero-title': 'منصّة التوصيل التي تربط الجميع',
  'hero-lede': 'تنسّق YouDrop العمل بين العملاء والمتاجر المحلية والمندوبين المستقلّين وشركات الشحن في تناغم تام. منظومة واحدة، وكفاءة بلا حدود.',
  'tower-label': 'برج التحكّم',
  'tower-delta': '+8.4% مقارنةً بالأسبوع الماضي',

  /* the cycle */
  'cycle-eyebrow': 'الدورة اللوجستية',
  'cycle-title': 'ثلاثة أطراف، دورة واحدة متكاملة',
  'cycle-lede': 'تعمل YouDrop لحظةً بلحظة لتمنح شفافية كاملة في كل مرحلة من مراحل الطلب.',
  'step1-title': 'المتاجر تعرض',
  'step1-body': 'ترفع المتاجر قوائمها وتحدّد أوقات التوصيل من خلال تطبيق التاجر.',
  'step2-title': 'العملاء يطلبون',
  'step2-body': 'يبحث المستخدمون في محيطهم فيطلبون الطعام أو السلع أو يرسلون الطرود عبر خدمة بتلر.',
  'step3-title': 'المندوبون يوصّلون',
  'step3-body': 'يحسّن المندوبون وأساطيل الشحن مساراتهم ويسلّمون في أوقات قياسية.',

  /* merchants */
  'merchants-eyebrow': 'للتجّار',
  'merchants-title': 'ضاعف إيراداتك واترك اللوجستيات علينا',
  'merchants-lede': 'ركّز على صناعة منتجات رائعة. من أطباق المطاعم إلى مخزون المتاجر، تتولّى YouDrop خط التوصيل بالكامل.',
  'merchants-f1': 'إدارة سهلة للقوائم والمنتجات',
  'merchants-f2': 'توجيه فوري للطلبات ومطابقة المندوبين',
  'merchants-f3': 'تحليلات متقدّمة متكاملة مع بوابة الإدارة',
  'merchants-f4': 'باقات أسعار مرنة مصمّمة للتجارة المحلية',

  /* carriers */
  'carriers-eyebrow': 'لشركات الشحن',
  'carriers-title': 'مكّن أسطولك وتصدّر السوق في منطقتك',
  'carriers-lede': 'تتعاون كبرى شركات التوصيل والشركات اللوجستية مع YouDrop لإدارة المندوبين وتأهيل الكوادر وتتبّع الشحنات الكثيفة لحظةً بلحظة.',
  'carriers-f1': 'مركز تحكّم متطوّر لشركات الشحن',
  'carriers-f2': 'تكامل مباشر عبر الواجهات البرمجية مع الأنظمة اللوجستية القائمة',
  'carriers-f3': 'تخطيط مرن للورديات ولوحات تحكّم للمرسِلين',
  'carriers-f4': 'تسويات فورية مجمّعة وتتبّع للمستحقات',
  'fleet-title': 'مركز إرسال الأسطول',
  'fleet-live': 'بث مباشر',

  /* riders */
  'riders-eyebrow': 'للمندوبين',
  'riders-title': 'وصّل متى شئت، واكسب دخلاً ممتازاً.',
  'riders-lede': 'تمنحك YouDrop مرونة كاملة. سواء كنت تستخدم دراجة هوائية أو سكوتر أو دراجة نارية أو سيارة — اتصل بالتطبيق واقبل الطلبات واكسب فوراً.',
  'riders-f1': 'أرباح تنافسية عالية وإكراميات',
  'riders-f2': 'ساعات مرنة — اعمل وقتما تشاء',
  'riders-f3': 'نظام توجيه ذكي لتسليم أسرع وانتظار أقل',
  'riders-f4': 'تحويلات فورية مباشرةً إلى محفظتك الرقمية',

  /* customers and Butler */
  'customers-eyebrow': 'للعملاء',
  'customers-title': 'بتلر من YouDrop: اشترِ أو أرسل أي شيء',
  'customers-lede': 'خدمة بتلر المميّزة لا تقتصر على القوائم المعتادة. إن وُجد المتجر في مدينتك اشترينا منه. وتحتاج إلى توصيل مفاتيح؟ نحن جاهزون.',
  'butler-buy-title': 'اشترِ أي شيء',
  'butler-buy-body': 'أخبرنا بما تريد شراءه وسنوصله إليك.',
  'butler-send-title': 'أرسل أي شيء',
  'butler-send-body': 'استلام وتسليم وتوصيل فوري لأي غرض داخل المدينة.',

  /* the counters */
  'stat1': 'متجر نشط',
  'stat2': 'عملية توصيل يومياً',
  'stat3': 'مندوب موثّق',
  'stat4': 'نسبة الرضا',

  /* testimonials, still waiting for their subjects */
  'stories-eyebrow': 'قصص نجاح',
  'stories-title': 'يحبّها التجّار والمندوبون والعملاء',
  'stories-lede': 'لا تأخذ كلامنا وحده. استمع إلى أصوات من قلب منظومتنا.',
  'tag-merchant': 'تاجر شريك',
  'tag-rider': 'مندوب نشط',
  'tag-customer': 'عميل',
  'quote-pending-name': 'بانتظار تاجر',
  'quote-pending-role': 'الاسم والمتجر الحقيقيان',
  'quote-pending-body': 'كلمات تاجر بصيغته هو، تُوضع هنا بعد أن نطلبها منه.',
  'quote-pending-name-r': 'بانتظار مندوب',
  'quote-pending-role-r': 'الاسم والمدينة الحقيقيان',
  'quote-pending-body-r': 'كلمات مندوب بصيغته هو، تُوضع هنا بعد أن نطلبها منه.',
  'quote-pending-name-c': 'بانتظار عميل',
  'quote-pending-role-c': 'الاسم والمدينة الحقيقيان',
  'quote-pending-body-c': 'كلمات عميل بصيغته هو، تُوضع هنا بعد أن نطلبها منه.',

  /* the app */
  'mobile-eyebrow': 'التطبيق على هاتفك',
  'mobile-title': 'حمّل YouDrop على هاتفك اليوم',
  'mobile-lede': 'متاح لأجهزة iOS وAndroid. امسح رمز الاستجابة السريعة للتثبيت، أو حمّله مباشرةً من متجر التطبيقات المفضّل لديك.',
  'qr-slot': 'رمز الاستجابة السريعة قريباً',

  /* questions */
  'faq-eyebrow': 'مركز المساعدة',
  'faq-title': 'الأسئلة الشائعة',
  'faq-lede': 'لديك سؤال عن YouDrop؟ جمعنا لك إجابات أكثر الأسئلة تكراراً.',
  'faq1-q': 'كيف أسجّل كتاجر؟',
  'faq1-a': 'اضغط على زر «ابدأ كتاجر»، وارفع مستندات نشاطك التجاري وقائمتك أو كتالوج متجرك، وسيراجع فريقنا الطلب ويفعّل حسابك خلال ٢٤ ساعة.',
  'faq2-q': 'ما هي خدمة بتلر من YouDrop؟',
  'faq2-a': 'تتيح لك خدمة بتلر طلب أي شيء من أي متجر في مدينتك. اختر «اشترِ أي شيء» أو «أرسل أي شيء» داخل التطبيق ليصلك مندوب خاص فوراً.',
  'faq3-q': 'هل تُدار أساطيل التوصيل مباشرةً؟',
  'faq3-a': 'نعم. تحصل شركات الشحن على لوحة تحكّم موحّدة للمرسِلين لتأهيل أساطيلها وتخطيط الورديات ومتابعة العمليات مباشرةً عبر برج التحكّم.',
  'faq4-q': 'متى تُصرف أرباح المندوبين؟',
  'faq4-a': 'تُصرف فوراً. بمجرّد تأكيد إتمام عملية التوصيل تُحوَّل أرباحك وإكرامياتك مباشرةً إلى محفظتك داخل التطبيق للسحب في الحال.',
  'faq5-q': 'في أي المناطق تعمل YouDrop؟',
  'faq5-a': 'نعمل في المراكز الحضرية الكبرى. راجع خريطة التغطية أو ابحث عن مدينتك داخل التطبيق لمعرفة النطاق المتاح والمتاجر القريبة.',
  'faq6-q': 'ما هي رسوم الانضمام إلى المنصّة؟',
  'faq6-a': 'نلتزم بالشفافية الكاملة. لا توجد أي رسوم انضمام مقدّمة. تعمل YouDrop بعمولة بسيطة على المعاملات تُحدَّد وفق حجم أعمالك.',

  /* footer */
  'footer-blurb': 'نطوّر تقنيات لوجستية من الجيل القادم تربط التجارة بالمندوبين والأساطيل في كل مكان.',
  'footer-platform': 'المنصّة',
  'footer-company': 'الشركة',
  'footer-support': 'الدعم',
  'footer-partner': 'كن شريكاً لنا',
  'footer-signin': 'تسجيل الدخول',
  'footer-legal': '© 2026 شركة YouDrop لتقنيات الخدمات اللوجستية. جميع الحقوق محفوظة.'
};

const TITLE_AR = 'YouDrop — منصّة التوصيل التي تربط الجميع';

/* The footer's label names the language the page is currently in, as the design draws it. The
   affordance is the "EN / AR" control in the navbar; this one reports and also flips. */
const SWITCH_LABEL = { en: 'English (US)', ar: 'العربية' };

const translatable = document.querySelectorAll('[data-t]');
const toggles = document.querySelectorAll('[data-lang-toggle]');
const switchLabels = document.querySelectorAll('[data-lang-label]');

/* The English, taken from the markup itself rather than restated in a second dictionary. */
const english = new Map();
translatable.forEach((node) => english.set(node, node.textContent));
const titleEn = document.title;

/*
  localStorage throws outright in a few places — a browser set to block site data, some embedded
  webviews — rather than merely returning null. Reading a stored preference is not worth taking the
  page down for, so both directions are wrapped and a failure just means the default.
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
  const arabic = lang === 'ar';

  document.documentElement.lang = arabic ? 'ar' : 'en';
  document.documentElement.dir = arabic ? 'rtl' : 'ltr';
  document.title = arabic ? TITLE_AR : titleEn;

  translatable.forEach((node) => {
    const key = node.dataset.t;
    /* A key with no Arabic falls back to the English rather than emptying the element — a missing
       translation should read as untranslated, never as missing content. */
    node.textContent = arabic ? (AR[key] || english.get(node)) : english.get(node);
  });

  switchLabels.forEach((node) => { node.textContent = SWITCH_LABEL[arabic ? 'ar' : 'en']; });
  toggles.forEach((button) => button.setAttribute('aria-pressed', String(arabic)));
}

toggles.forEach((button) => {
  button.addEventListener('click', () => {
    const next = document.documentElement.lang === 'ar' ? 'en' : 'ar';
    apply(next);
    store(next);
  });
});

/* Only Arabic needs applying on load. English is already in the document — including the footer's
   own label — and re-writing every node with the text it already holds would be work for nothing. */
if (readStored() === 'ar') apply('ar');
