-- Templates for the non-customer audiences.
--
-- One domain event usually has more than one interested party, and they do not want the same
-- message: order.placed is a receipt for the customer and a work item for the merchant. Rather than
-- branch on role inside the manager, each audience gets its own event_type suffix and its own
-- template rows, so "what does the merchant see" is answerable by reading this table.

INSERT INTO notification_templates (id, event_type, channel, locale, subject_template, body_template) VALUES
    -- Merchant: a new order is waiting to be accepted.
    ('a0000000-0000-4000-8000-000000000010', 'order.placed.merchant', 'IN_APP', 'en',
     'New order', 'Order #{{shortId}} ({{itemCount}} items, {{total}}) is waiting to be accepted.'),
    ('a0000000-0000-4000-8000-000000000011', 'order.placed.merchant', 'EMAIL', 'en',
     'New order #{{shortId}}',
     'Order #{{shortId}} has been placed.'
     || E'\n\nItems: {{itemCount}}\nTotal: {{total}}\nDeliver to: {{address}}'
     || E'\n\nAccept it in the merchant portal to start preparing.'),
    ('a0000000-0000-4000-8000-000000000012', 'order.placed.merchant', 'PUSH', 'en',
     'New order', 'Order #{{shortId}} is waiting to be accepted.'),

    -- Rider: the job they just claimed, with the address they need.
    ('a0000000-0000-4000-8000-000000000013', 'order.rider_assigned.rider', 'IN_APP', 'en',
     'Job assigned', 'Order #{{shortId}} is yours. Deliver to {{address}}.'),
    ('a0000000-0000-4000-8000-000000000014', 'order.rider_assigned.rider', 'PUSH', 'en',
     'Job assigned', 'Order #{{shortId}} — deliver to {{address}}.'),

    -- Merchant: stop preparing.
    ('a0000000-0000-4000-8000-000000000015', 'order.cancelled.merchant', 'IN_APP', 'en',
     'Order cancelled', 'Order #{{shortId}} was cancelled. {{reason}}'),
    ('a0000000-0000-4000-8000-000000000016', 'order.cancelled.merchant', 'PUSH', 'en',
     'Order cancelled', 'Stop preparing order #{{shortId}}. {{reason}}'),

    -- Customer push for the two moments worth interrupting someone for. Deliberately not every
    -- status change: a notification for PREPARING as well as READY as well as PICKED_UP is how a
    -- platform teaches its users to turn notifications off.
    ('a0000000-0000-4000-8000-000000000017', 'order.rider_assigned', 'PUSH', 'en',
     'On the way', 'A rider has picked up order #{{shortId}}.'),
    ('a0000000-0000-4000-8000-000000000018', 'order.delivered', 'PUSH', 'en',
     'Delivered', 'Order #{{shortId}} has arrived.');
