-- Notification schema (Section 4), owned by Notifications Manager.

-- Message bodies per channel and locale. Kept in the database rather than in code so a wording fix
-- is a data change, not a release - Section 6 puts template DEFAULTS in the config repo, but the
-- editable copy belongs here.
CREATE TABLE notification_templates (
    id            uuid         PRIMARY KEY,
    event_type    varchar(64)  NOT NULL,
    channel       varchar(16)  NOT NULL,
    locale        varchar(8)   NOT NULL DEFAULT 'en',
    subject_template text,
    body_template text         NOT NULL,
    created_at    timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT chk_template_channel CHECK (channel IN ('SMS', 'EMAIL', 'PUSH', 'IN_APP')),
    CONSTRAINT uq_template UNIQUE (event_type, channel, locale)
);

-- Every notification the platform decided to send, and what became of it.
--
-- This is the record that answers "why didn't this SMS arrive" (Section 10). The row is written
-- BEFORE dispatch, so a message that vanished in the connector still has a trace - a log written
-- only on success would be silent about exactly the failures worth investigating.
CREATE TABLE notification_log (
    id            uuid         PRIMARY KEY,
    order_id      uuid,
    recipient_id  varchar(64)  NOT NULL,
    channel       varchar(16)  NOT NULL,
    recipient     varchar(255) NOT NULL,
    event_type    varchar(64)  NOT NULL,
    subject       text,
    body          text         NOT NULL,
    status        varchar(16)  NOT NULL DEFAULT 'PENDING',
    provider      varchar(64),
    provider_message_id varchar(255),
    failure_reason text,
    attempts      integer      NOT NULL DEFAULT 0,
    correlation_id varchar(64),
    created_at    timestamptz  NOT NULL DEFAULT now(),
    sent_at       timestamptz,
    CONSTRAINT chk_log_channel CHECK (channel IN ('SMS', 'EMAIL', 'PUSH', 'IN_APP')),
    CONSTRAINT chk_log_status CHECK (status IN ('PENDING', 'SENT', 'FAILED', 'DEAD_LETTERED'))
);

CREATE INDEX idx_notification_log_order ON notification_log (order_id, created_at DESC);
CREATE INDEX idx_notification_log_recipient ON notification_log (recipient_id, created_at DESC);
-- The operator's view: what is stuck or lost.
CREATE INDEX idx_notification_log_unsent ON notification_log (created_at)
    WHERE status IN ('PENDING', 'FAILED', 'DEAD_LETTERED');

-- Seed templates for the order lifecycle. {{placeholders}} are substituted by the manager.
INSERT INTO notification_templates (id, event_type, channel, locale, subject_template, body_template) VALUES
    ('a0000000-0000-4000-8000-000000000001', 'order.placed', 'IN_APP', 'en',
     'Order placed', 'Your order #{{shortId}} is with the merchant. Total {{total}}.'),
    ('a0000000-0000-4000-8000-000000000002', 'order.placed', 'EMAIL', 'en',
     'We got your order #{{shortId}}',
     'Thanks! Your order #{{shortId}} totalling {{total}} has been sent to the merchant.'),
    ('a0000000-0000-4000-8000-000000000003', 'order.status_changed', 'IN_APP', 'en',
     'Order update', 'Order #{{shortId}} is now {{status}}.'),
    ('a0000000-0000-4000-8000-000000000004', 'order.status_changed', 'SMS', 'en',
     null, 'Delivery: order #{{shortId}} is now {{status}}.'),
    ('a0000000-0000-4000-8000-000000000005', 'order.rider_assigned', 'IN_APP', 'en',
     'Rider on the way', 'A rider has picked up order #{{shortId}}.'),
    ('a0000000-0000-4000-8000-000000000006', 'order.delivered', 'IN_APP', 'en',
     'Delivered', 'Order #{{shortId}} has been delivered. Enjoy!'),
    ('a0000000-0000-4000-8000-000000000007', 'order.delivered', 'SMS', 'en',
     null, 'Delivery: order #{{shortId}} has been delivered.'),
    ('a0000000-0000-4000-8000-000000000008', 'order.cancelled', 'IN_APP', 'en',
     'Order cancelled', 'Order #{{shortId}} was cancelled. {{reason}}'),
    ('a0000000-0000-4000-8000-000000000009', 'order.cancelled', 'EMAIL', 'en',
     'Order #{{shortId}} cancelled',
     'Your order #{{shortId}} was cancelled. {{reason}}');
