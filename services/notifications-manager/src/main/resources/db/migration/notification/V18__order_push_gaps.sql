-- The three moments an order changes hands and somebody's phone stayed silent.
--
-- V17 gave the customer a push for every status change, which is most of "tell people when their
-- order moves". Reading the template table against the log afterwards showed three holes left,
-- and all three have the same shape: one party to the order is told and the other is not.
--
-- 1. A CANCELLED ORDER PUSHES THE MERCHANT AND NOT THE CUSTOMER. V11 gave
--    order.cancelled.merchant a PUSH ("Stop preparing order #X") and order.cancelled — the
--    customer's copy — was left with EMAIL and IN_APP only. So the shop's phone buzzes and the
--    person whose dinner was just called off finds out when they next open the app, or when it
--    does not arrive. Of every notification on this platform this is the one most worth
--    interrupting somebody for, and it was the one that did not.
--
-- 2 & 3. THE MERCHANT IS NEVER TOLD THE ORDER LEFT, OR ARRIVED. order.status_changed and
--    order.delivered both notify customerId and nobody else, so from the shop's point of view an
--    order goes quiet the moment they mark it ready. Whether the rider ever came, and whether the
--    food got there, is not something the counter is told.
--
--    Only the transitions the merchant did NOT cause are added — the listener gates this to
--    PICKED_UP. Pushing ACCEPTED, PREPARING and READY back at the merchant would be notifying
--    them about their own three taps, which is how people learn to turn notifications off.
INSERT INTO notification_templates (id, event_type, channel, locale, subject_template, body_template) VALUES
    ('a0000000-0000-4000-8000-00000000001a', 'order.cancelled', 'PUSH', 'en',
     'Order #{{shortId}} cancelled', 'Your order was cancelled. {{reason}}'),

    ('a0000000-0000-4000-8000-00000000001b', 'order.status_changed.merchant', 'PUSH', 'en',
     'Order #{{shortId}} collected', 'A rider has picked up order #{{shortId}}.'),
    ('a0000000-0000-4000-8000-00000000001c', 'order.status_changed.merchant', 'IN_APP', 'en',
     'Order collected', 'A rider has picked up order #{{shortId}}.'),

    ('a0000000-0000-4000-8000-00000000001d', 'order.delivered.merchant', 'PUSH', 'en',
     'Order #{{shortId}} delivered', 'Order #{{shortId}} reached the customer.'),
    ('a0000000-0000-4000-8000-00000000001e', 'order.delivered.merchant', 'IN_APP', 'en',
     'Order delivered', 'Order #{{shortId}} reached the customer.');
