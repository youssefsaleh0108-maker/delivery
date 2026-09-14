-- Service orders, told in their own words.
--
-- A service order (kind SERVICE: a print job, an alteration, a repair) moves on the same order.*
-- events and the same statuses as a basket, so until now its customer was told "The restaurant has
-- accepted your order.", and a pickup waiting at the counter was announced as "ready and waiting for
-- a rider" nobody was ever going to send. OrderEventListener now reads kind and fulfilment off the
-- snapshot and, for a service order, sends the moments below instead. Basket wording, every basket
-- template row and every dedupe key are untouched.
--
-- WHY THE NAMES START WITH THE DOMAIN EVENT. order.<event>.service.<moment>, rather than a family of
-- their own, because two things already key off that prefix. NotificationCategory files anything
-- starting "order." under ORDER_UPDATES, so the customer's own order-updates switch governs these
-- exactly as it governs a basket's; a name like service.declined would land in ACCOUNT, which nobody
-- may turn off. And the app's inbox picks its icon from order.cancelled / order.delivered /
-- order.placed, so a decline still draws a cancel mark rather than a bell.
--
-- WHICH CHANNELS. Each moment has the channels of the basket event it stands in for, and no others:
-- IN_APP, SMS and PUSH for a status change or a delivery; IN_APP, EMAIL and PUSH for a cancellation
-- or a merchant's new order. Whether a service order deserves fewer texts than a basket is a product
-- decision, and a migration is the wrong place to make it by accident.
--
-- WHAT HAS NO ROW, ON PURPOSE.
--   * PREPARING. A service order's shop accepts straight into production, so PREPARING follows
--     ACCEPTED in the same second, and the listener sends nothing for it: ACCEPTED has just told
--     the customer when to expect the work.
--   * The shop's copy of a pickup's collection, of its own decline, and of its own "not collected"
--     cancellation. All three are the shop's own taps, and V18's rule stands: telling the merchant
--     about its own actions is how people learn to turn notifications off.
--   * Everything else a service order does (a rider claiming it, the rider collecting it, a
--     delivery arriving, a cancellation in somebody's own words) reads correctly in the basket's
--     wording and uses the basket's rows.
--
-- PLACEHOLDERS the listener fills for service orders only: {{store}} the shop's name; {{offer}} the
-- job as the provider's card reads it ("500 Business Cards"); {{readyBy}} the estimate in Beirut
-- time, with its date ("Fri 18 Sep, 4:30 PM"), because this copy is kept in the inbox, where
-- "tomorrow" is wrong the next day; {{reasonWords}} a decline's picklist code in plain words, or the
-- shop's own words after NOT_COLLECTED. The stored "PROVIDER_DECLINED: TOO_BUSY" never reaches a
-- customer.
--
-- ARABIC. These are the first Arabic rows in this table, and nothing reads them yet: dispatch looks
-- every template up in delivery.notifications.default-locale (en), whoever the recipient is. They
-- are written now so the copy exists once a recipient's locale is resolved. The listener fills
-- {{readyByAr}} (Lebanese month names) and {{reasonWordsAr}} beside the English values, so an
-- Arabic message does not end in an English date or reason.

INSERT INTO notification_templates (id, event_type, channel, locale, subject_template, body_template) VALUES
    -- Merchant: a new service order to accept or decline, naming the job rather than counting items.
    ('a0000000-0000-4000-8000-000000000101', 'order.placed.service.merchant', 'IN_APP', 'en',
     'New service order', 'New service order: {{offer}}'),
    ('a0000000-0000-4000-8000-000000000102', 'order.placed.service.merchant', 'EMAIL', 'en',
     'New service order #{{shortId}}',
     'New service order: {{offer}}'
     || E'\n\nTotal: {{total}}'
     || E'\n\nAccept or decline it in the merchant portal.'),
    ('a0000000-0000-4000-8000-000000000103', 'order.placed.service.merchant', 'PUSH', 'en',
     'Order #{{shortId}}', 'New service order: {{offer}}'),

    -- Customer: accepted, and when the work will be ready.
    ('a0000000-0000-4000-8000-000000000104', 'order.status_changed.service.accepted', 'IN_APP', 'en',
     'Order accepted', '{{store}} accepted your order — ready by {{readyBy}}'),
    ('a0000000-0000-4000-8000-000000000105', 'order.status_changed.service.accepted', 'SMS', 'en',
     null, 'Delivery: {{store}} accepted order #{{shortId}} — ready by {{readyBy}}.'),
    ('a0000000-0000-4000-8000-000000000106', 'order.status_changed.service.accepted', 'PUSH', 'en',
     'Order #{{shortId}}', '{{store}} accepted your order — ready by {{readyBy}}'),

    -- Customer: ready, said differently for the two ways the work reaches them.
    ('a0000000-0000-4000-8000-000000000107', 'order.status_changed.service.ready_to_collect', 'IN_APP', 'en',
     'Ready to collect', 'Ready to collect at {{store}}'),
    ('a0000000-0000-4000-8000-000000000108', 'order.status_changed.service.ready_to_collect', 'SMS', 'en',
     null, 'Delivery: order #{{shortId}} is ready to collect at {{store}}.'),
    ('a0000000-0000-4000-8000-000000000109', 'order.status_changed.service.ready_to_collect', 'PUSH', 'en',
     'Order #{{shortId}}', 'Ready to collect at {{store}}'),
    ('a0000000-0000-4000-8000-00000000010a', 'order.status_changed.service.ready_for_rider', 'IN_APP', 'en',
     'Order ready', 'Ready — a rider is being assigned'),
    ('a0000000-0000-4000-8000-00000000010b', 'order.status_changed.service.ready_for_rider', 'SMS', 'en',
     null, 'Delivery: order #{{shortId}} is ready — a rider is being assigned.'),
    ('a0000000-0000-4000-8000-00000000010c', 'order.status_changed.service.ready_for_rider', 'PUSH', 'en',
     'Order #{{shortId}}', 'Ready — a rider is being assigned'),

    -- Customer: a pickup collected at the counter, which is the moment to ask for a rating.
    ('a0000000-0000-4000-8000-00000000010d', 'order.delivered.service.collected', 'IN_APP', 'en',
     'Collected', 'Collected — rate {{store}}'),
    ('a0000000-0000-4000-8000-00000000010e', 'order.delivered.service.collected', 'SMS', 'en',
     null, 'Delivery: order #{{shortId}} collected — rate {{store}} in the app.'),
    ('a0000000-0000-4000-8000-00000000010f', 'order.delivered.service.collected', 'PUSH', 'en',
     'Order #{{shortId}}', 'Collected — rate {{store}}'),

    -- Customer: the provider declined, with its reason in words.
    ('a0000000-0000-4000-8000-000000000110', 'order.cancelled.service.declined', 'IN_APP', 'en',
     'Order declined', 'Declined by {{store}}: {{reasonWords}}'),
    ('a0000000-0000-4000-8000-000000000111', 'order.cancelled.service.declined', 'EMAIL', 'en',
     'Order #{{shortId}} declined', 'Your order #{{shortId}} was declined by {{store}}: {{reasonWords}}.'),
    ('a0000000-0000-4000-8000-000000000112', 'order.cancelled.service.declined', 'PUSH', 'en',
     'Order #{{shortId}} declined', 'Declined by {{store}}: {{reasonWords}}'),

    -- Customer: a pickup nobody came for, cancelled by the shop once the wait was over. Said plainly,
    -- with the shop's own words after it when it gave any.
    ('a0000000-0000-4000-8000-000000000113', 'order.cancelled.service.not_collected', 'IN_APP', 'en',
     'Order cancelled', '{{store}} cancelled your order because it wasn''t collected in time. {{reasonWords}}'),
    ('a0000000-0000-4000-8000-000000000114', 'order.cancelled.service.not_collected', 'EMAIL', 'en',
     'Order #{{shortId}} cancelled',
     'Your order #{{shortId}} was cancelled by {{store}} because it wasn''t collected in time. {{reasonWords}}'),
    ('a0000000-0000-4000-8000-000000000115', 'order.cancelled.service.not_collected', 'PUSH', 'en',
     'Order #{{shortId}} cancelled', '{{store}} cancelled your order because it wasn''t collected in time. {{reasonWords}}');

-- The same moments in Arabic, on the same channels.
INSERT INTO notification_templates (id, event_type, channel, locale, subject_template, body_template) VALUES
    ('a0000000-0000-4000-8000-000000000121', 'order.placed.service.merchant', 'IN_APP', 'ar',
     'طلب خدمة جديد', 'طلب خدمة جديد: {{offer}}'),
    ('a0000000-0000-4000-8000-000000000122', 'order.placed.service.merchant', 'EMAIL', 'ar',
     'طلب خدمة جديد #{{shortId}}',
     'طلب خدمة جديد: {{offer}}'
     || E'\n\nالمجموع: {{total}}'
     || E'\n\nاقبله أو ارفضه من بوابة التاجر.'),
    ('a0000000-0000-4000-8000-000000000123', 'order.placed.service.merchant', 'PUSH', 'ar',
     'الطلب #{{shortId}}', 'طلب خدمة جديد: {{offer}}'),

    ('a0000000-0000-4000-8000-000000000124', 'order.status_changed.service.accepted', 'IN_APP', 'ar',
     'تم قبول الطلب', 'قبِل {{store}} طلبك — سيكون جاهزًا بحلول {{readyByAr}}'),
    ('a0000000-0000-4000-8000-000000000125', 'order.status_changed.service.accepted', 'SMS', 'ar',
     null, 'قبِل {{store}} الطلب #{{shortId}} — سيكون جاهزًا بحلول {{readyByAr}}.'),
    ('a0000000-0000-4000-8000-000000000126', 'order.status_changed.service.accepted', 'PUSH', 'ar',
     'الطلب #{{shortId}}', 'قبِل {{store}} طلبك — سيكون جاهزًا بحلول {{readyByAr}}'),

    ('a0000000-0000-4000-8000-000000000127', 'order.status_changed.service.ready_to_collect', 'IN_APP', 'ar',
     'جاهز للاستلام', 'طلبك جاهز للاستلام من {{store}}'),
    ('a0000000-0000-4000-8000-000000000128', 'order.status_changed.service.ready_to_collect', 'SMS', 'ar',
     null, 'الطلب #{{shortId}} جاهز للاستلام من {{store}}.'),
    ('a0000000-0000-4000-8000-000000000129', 'order.status_changed.service.ready_to_collect', 'PUSH', 'ar',
     'الطلب #{{shortId}}', 'طلبك جاهز للاستلام من {{store}}'),
    ('a0000000-0000-4000-8000-00000000012a', 'order.status_changed.service.ready_for_rider', 'IN_APP', 'ar',
     'الطلب جاهز', 'طلبك جاهز — جارٍ تعيين سائق لتوصيله'),
    ('a0000000-0000-4000-8000-00000000012b', 'order.status_changed.service.ready_for_rider', 'SMS', 'ar',
     null, 'الطلب #{{shortId}} جاهز — جارٍ تعيين سائق لتوصيله.'),
    ('a0000000-0000-4000-8000-00000000012c', 'order.status_changed.service.ready_for_rider', 'PUSH', 'ar',
     'الطلب #{{shortId}}', 'طلبك جاهز — جارٍ تعيين سائق لتوصيله'),

    ('a0000000-0000-4000-8000-00000000012d', 'order.delivered.service.collected', 'IN_APP', 'ar',
     'تم الاستلام', 'تم استلام طلبك — قيّم {{store}}'),
    ('a0000000-0000-4000-8000-00000000012e', 'order.delivered.service.collected', 'SMS', 'ar',
     null, 'تم استلام الطلب #{{shortId}} — قيّم {{store}} في التطبيق.'),
    ('a0000000-0000-4000-8000-00000000012f', 'order.delivered.service.collected', 'PUSH', 'ar',
     'الطلب #{{shortId}}', 'تم استلام طلبك — قيّم {{store}}'),

    ('a0000000-0000-4000-8000-000000000130', 'order.cancelled.service.declined', 'IN_APP', 'ar',
     'تم رفض الطلب', 'رفض {{store}} طلبك: {{reasonWordsAr}}'),
    ('a0000000-0000-4000-8000-000000000131', 'order.cancelled.service.declined', 'EMAIL', 'ar',
     'تم رفض الطلب #{{shortId}}', 'رفض {{store}} طلبك #{{shortId}}: {{reasonWordsAr}}.'),
    ('a0000000-0000-4000-8000-000000000132', 'order.cancelled.service.declined', 'PUSH', 'ar',
     'تم رفض الطلب #{{shortId}}', 'رفض {{store}} طلبك: {{reasonWordsAr}}'),

    ('a0000000-0000-4000-8000-000000000133', 'order.cancelled.service.not_collected', 'IN_APP', 'ar',
     'تم إلغاء الطلب', 'ألغى {{store}} طلبك لأنه لم يُستلم في الوقت المحدد. {{reasonWordsAr}}'),
    ('a0000000-0000-4000-8000-000000000134', 'order.cancelled.service.not_collected', 'EMAIL', 'ar',
     'تم إلغاء الطلب #{{shortId}}',
     'ألغى {{store}} طلبك #{{shortId}} لأنه لم يُستلم في الوقت المحدد. {{reasonWordsAr}}'),
    ('a0000000-0000-4000-8000-000000000135', 'order.cancelled.service.not_collected', 'PUSH', 'ar',
     'تم إلغاء الطلب #{{shortId}}', 'ألغى {{store}} طلبك لأنه لم يُستلم في الوقت المحدد. {{reasonWordsAr}}');
