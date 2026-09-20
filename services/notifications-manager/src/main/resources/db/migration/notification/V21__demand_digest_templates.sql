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
-- THE COPY DOES NOT PROMISE A TAP. It said "Open your Demand Radar" and "Tap to see the week", and
-- no client routes a deep link anywhere today: the in-app row marks itself read, a push opens the
-- app wherever it was, and there is no route table to add DEMAND to. So the message says where to
-- look — Demand Radar on the shop's dashboard, where the merchant already has a door to it — which
-- is true whatever the tap does. Wiring a real route means push-tap handling the app does not have
-- at all, a deep-link parser, and a merchant shell that can pick the right shop; that is a change
-- of its own, not a line in a template, and half of it would be worse than none.
--
-- The link target stays DEMAND, whose id is the shop's: it is the record of where this message
-- points, and it travels as metadata for the client that will one day route it. The enum's own
-- comment now says plainly that nothing routes it yet, rather than implying the route exists.

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
     'nearby. The week is in Demand Radar, on your shop''s dashboard.',
     'DEMAND'),
    ('a0000000-0000-4000-8000-000000000141', 'demand.digest.weekly', 'PUSH', 'en',
     'Your neighbours looked for {{first}}',
     'Near {{area}}: {{terms}}. Nobody nearby sells them. Open Demand Radar on your dashboard '
     'for the week.',
     'DEMAND'),
    ('a0000000-0000-4000-8000-000000000142', 'demand.digest.weekly', 'IN_APP', 'ar',
     'جيرانك بحثوا عن {{first}}',
     'قرب {{area}} الأسبوع الماضي: {{terms}}. حوالي {{about}} عملية بحث عن {{first}} لم تجد شيئاً '
     'قريباً. الأسبوع كامل في رادار الطلب، في لوحة متابعة متجرك.',
     'DEMAND'),
    ('a0000000-0000-4000-8000-000000000143', 'demand.digest.weekly', 'PUSH', 'ar',
     'جيرانك بحثوا عن {{first}}',
     'قرب {{area}}: {{terms}}. لا أحد قريب يبيعها. افتح رادار الطلب في لوحة المتابعة لرؤية الأسبوع.',
     'DEMAND');
