-- A push for every order status change, reversing V11's "only two moments" stance on request.
--
-- V11 deliberately pushed only rider-assigned and delivered, reasoning that a notification per
-- status teaches people to turn notifications off. The platform's owner asked for the opposite —
-- the customer should hear about each step — and the ORDER_UPDATES category is user-mutable, so
-- anyone who agrees with V11 can still turn these off themselves.
--
-- {{statusMessage}} is a real sentence built in OrderEventListener ("The restaurant is preparing
-- your order."), not the raw state name. The listener also keys this event's dedupe on the status,
-- so each transition notifies once; before that, the order-based check meant only the FIRST
-- status change ever fired and the rest were dropped as duplicates — which also silently affected
-- the IN_APP and SMS rows V10 seeded for this event.
INSERT INTO notification_templates (id, event_type, channel, locale, subject_template, body_template) VALUES
    ('a0000000-0000-4000-8000-000000000019', 'order.status_changed', 'PUSH', 'en',
     'Order #{{shortId}}', '{{statusMessage}}');

-- The rider-assigned push fires at CLAIM time, but its copy said "picked up" — which now collides
-- with the real PICKED_UP push above and was never what the moment meant. Say what happened.
UPDATE notification_templates
   SET body_template = 'A rider has accepted order #{{shortId}}.'
 WHERE event_type = 'order.rider_assigned' AND channel = 'PUSH' AND locale = 'en';
