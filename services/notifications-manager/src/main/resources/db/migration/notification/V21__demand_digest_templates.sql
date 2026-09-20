-- The weekly demand digest: what a shop's neighbours looked for and could not find nearby.
--
-- Product Service raises demand.digest.weekly once a week per merchant with a live shop, and this
-- service turns it into a message. An event and a template rather than POST /api/notifications/direct,
-- which deliberately bypasses notification preferences: a weekly nudge that could not be turned off
-- would be the kind of message that teaches people to turn everything off.
--
-- WHY THE NAME STARTS WITH demand. NotificationCategory derives the preference bucket from the event
-- type's namespace, and anything it does not recognise falls to ACCOUNT, which nobody may mute. So
-- "demand." is added to that mapping in the same change as these rows, pointing at a new
-- MERCHANT_INSIGHTS category: on by default, because a shop that just opened wants to hear this, and
-- droppable, because it is advice rather than a security notice.
--
-- WHICH CHANNELS. IN_APP and PUSH. This is a Monday-morning nudge with a link into the app, not news
-- somebody needs at the door — so no SMS, which is paid for per segment and reserved for the moments
-- that send somebody out of the house. No EMAIL either: the merchant's inbox already gets their
-- statement, and the digest is only useful beside the screen it links to.
--
-- PLACEHOLDERS, filled by DemandEventListener from the event:
--   {{terms}} the words themselves, joined for reading ("nappies, basmati rice and nescafe");
--   {{first}} the most-searched of them, which is also what the subject names;
--   {{about}}  roughly how many searches asked for {{first}} — a band, never the exact count;
--   {{area}}  the neighbourhood that asked, or the region, or "your area" when the register has
--             neither. Never a coordinate and never a customer.
--
-- The link target is DEMAND, whose id is the shop's, so a tap opens that shop's Demand Radar rather
-- than a listing. Adding a target is deliberately two steps — the enum and the CHECK constraints
-- below — so the app and the platform have to agree the route exists before a message can point at it.

alter table notification.notification_templates
    drop constraint chk_template_link_target;

alter table notification.notification_templates
    add constraint chk_template_link_target
    check (link_target is null
           or link_target in ('ORDER', 'CONVERSATION', 'APPLICATION', 'EARNINGS', 'ACCOUNT', 'DEMAND'));

alter table notification.notification_log
    drop constraint chk_log_link_target;

alter table notification.notification_log
    add constraint chk_log_link_target
    check (link_target is null
           or link_target in ('ORDER', 'CONVERSATION', 'APPLICATION', 'EARNINGS', 'ACCOUNT', 'DEMAND'));

insert into notification.notification_templates
    (id, event_type, channel, locale, subject_template, body_template, link_target) values
    ('a0000000-0000-4000-8000-000000000140', 'demand.digest.weekly', 'IN_APP', 'en',
     'Your neighbours looked for {{first}}',
     'Near {{area}} last week: {{terms}}. About {{about}} searches for {{first}} found nothing '
     'nearby. Open your Demand Radar to see the week.',
     'DEMAND'),
    ('a0000000-0000-4000-8000-000000000141', 'demand.digest.weekly', 'PUSH', 'en',
     'Your neighbours looked for {{first}}',
     'Near {{area}}: {{terms}}. Nobody nearby sells them. Tap to see the week.',
     'DEMAND'),
    ('a0000000-0000-4000-8000-000000000142', 'demand.digest.weekly', 'IN_APP', 'ar',
     'جيرانك بحثوا عن {{first}}',
     'قرب {{area}} الأسبوع الماضي: {{terms}}. حوالي {{about}} عملية بحث عن {{first}} لم تجد شيئاً '
     'قريباً. افتح رادار الطلب لرؤية الأسبوع.',
     'DEMAND'),
    ('a0000000-0000-4000-8000-000000000143', 'demand.digest.weekly', 'PUSH', 'ar',
     'جيرانك بحثوا عن {{first}}',
     'قرب {{area}}: {{terms}}. لا أحد قريب يبيعها. اضغط لرؤية الأسبوع.',
     'DEMAND');
