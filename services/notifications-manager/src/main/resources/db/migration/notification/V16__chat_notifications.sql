-- The consumer half of `chat.message_missed`.
--
-- App Notification Service holds the customer↔rider chat socket and publishes this event when a
-- message had no live socket to land on. Nothing consumed it: this service bound `order.#` only, so
-- every one of those events was routed nowhere and the "your rider replied" push did not exist.
-- The shape now lives in platform-notifications (ChatEvents) beside DeliveryReceipt, so producer
-- and consumer are held to it by the compiler rather than by two copies of a comment.

-- WHY notification_log NEEDS A DEDUPE KEY.
--
-- Every event this service consumed until now was unique per order: there is one order.delivered
-- per order, so (order_id, event_type, channel, recipient_id) already answered "have we sent this",
-- and that is exactly the check the dispatch path makes. A conversation breaks the assumption — one
-- order carries many messages — so asking the order-shaped question about a chat notification would
-- send a push for the rider's FIRST missed message and then stay silent for the rest of the thread,
-- which is worse than sending nothing at all: the customer learns the feature is unreliable.
--
-- So the caller that knows what "the same notification" means supplies the key. For chat that is the
-- chat message id — not the conversation (a thread is many messages) and not the order.
--
-- Free-form text rather than a second uuid column on purpose. The next caller with this problem will
-- have some other kind of id, and a column typed to today's example would push it into inventing a
-- uuid to fit the column.
alter table notification.notification_log
    add column dedupe_key varchar(128);

comment on column notification.notification_log.dedupe_key is
    'What makes two deliveries the same notification, when the order id cannot say. NULL for order '
    'events, where (order_id, event_type, channel, recipient_id) is already unique. Set by callers '
    'whose events repeat within one order - a chat message id, for instance.';

-- PARTIAL, so the millions of order rows that will never carry a key are not in it, and so a NULL
-- key can never collide with another NULL.
--
-- UNIQUE rather than a plain index: the dispatch path checks before inserting, but that check and
-- the insert are two statements, and two redeliveries of one event landing on two instances at once
-- both pass the check. Uniqueness makes the second insert fail instead of sending a second push —
-- the same belt-and-braces reasoning as the CHECK behind the promo redemption counter. It also
-- serves the lookup, so this is one index doing both jobs rather than two.
create unique index uq_notification_log_dedupe
    on notification.notification_log (dedupe_key, channel, recipient_id)
    where dedupe_key is not null;

-- PUSH ONLY, and the absence of the other three channels is the decision.
--
-- IN_APP would be pointless bordering on absurd: the message is already in the app, in the thread,
-- and the reason this event exists at all is that the app was not there to receive it. SMS and EMAIL
-- would put a private message from one user to another into a channel neither of them chose for it,
-- charge the platform per send for a chat nudge, and arrive long after the conversation moved on.
-- A missed chat message is precisely the thing a lock screen is for.
--
-- The link target is CONVERSATION rather than NULL. NULL means "derive it", which resolves to the
-- order — and a tap that opens the order screen when the notification said someone wrote to you is
-- the wrong destination at the one moment the user is trying to reply. The id comes from the
-- conversationId placeholder the listener puts in the values map.
--
-- No name in the body. The event carries roles, not names, exactly so neither participant's identity
-- travels to the other's lock screen; {{sender}} renders as "your rider" or "your customer".
insert into notification.notification_templates
    (id, event_type, channel, locale, subject_template, body_template, link_target) values
    ('a0000000-0000-4000-8000-000000000030', 'chat.message_missed', 'PUSH', 'en',
     'New message about order #{{shortId}}',
     '{{sender}} sent you a message: {{preview}}',
     'CONVERSATION');
