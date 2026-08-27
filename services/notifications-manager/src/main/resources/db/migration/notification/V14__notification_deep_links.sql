-- Where a notification points, so a tapped push opens the right screen instead of the app's home.
--
-- WHY NO URL IS STORED HERE. The canonical form the app routes on is `delivery://orders/<id>` — a
-- private scheme whose authority segment names the KIND of thing to open, never a server. A stored
-- `https://app.<something>/...` would be wrong the moment the environment moves, and this project
-- has already lived that: notifications sitting in a device tray, in a queue backlog and in
-- notification_log all kept pointing at a host that no longer served them. Storing the target and
-- the id separately means the string is composed at send time and every stored row survives a move.
-- Anything that genuinely needs a web URL — an email button — builds one from the environment's own
-- base URL at render time, where a redeploy fixes it.

-- The template says what KIND of screen its message is about; the id comes from the event.
--
-- Nullable, and NULL is the common case rather than a gap. A null target means "derive it from the
-- notification itself", which for every order.* row in V10 and V11 resolves to that order.
--
-- WHY DERIVE RATHER THAN BACKFILL 'ORDER' INTO THOSE 18 ROWS: the order id is already on the
-- notification_log row, put there by the event. Writing ORDER into each template as well records a
-- fact the platform already holds, in a second place, where a future template insert can forget it
-- or contradict it — a template row claiming ORDER for an event carrying no order would produce a
-- link to nothing. Deriving cannot drift. The column exists for the cases the derivation genuinely
-- cannot know: a chat message points at a conversation and an earnings notice at a statement,
-- neither of which is the order that triggered it.
alter table notification.notification_templates
    add column link_target varchar(32);

-- Constrained rather than free text. An unrecognised target is not a routing failure the app can
-- report — the tap simply does nothing, at the exact moment the customer is trying to act on the
-- notification. Adding a target is therefore deliberately two steps: the enum, and widening this.
alter table notification.notification_templates
    add constraint chk_template_link_target
    check (link_target is null
           or link_target in ('ORDER', 'CONVERSATION', 'APPLICATION', 'EARNINGS', 'ACCOUNT'));

comment on column notification.notification_templates.link_target is
    'What kind of screen this template''s message is about. NULL means derive it from the '
    'notification (an order notification points at its order). Set it only where the message '
    'concerns something other than the order that triggered it.';

-- What was actually sent, as opposed to what a template asked for.
--
-- The log is the record of what the platform did (Section 10), and the link is part of what the
-- customer received: "the notification opened the wrong screen" is unanswerable if the link is
-- recomputed from today's rules rather than read back from the row. Two columns rather than the
-- composed string, so the stored value stays independent of the scheme it is rendered under.
alter table notification.notification_log
    add column link_target varchar(32),
    add column link_id     varchar(128);

alter table notification.notification_log
    add constraint chk_log_link_target
    check (link_target is null
           or link_target in ('ORDER', 'CONVERSATION', 'APPLICATION', 'EARNINGS', 'ACCOUNT'));

-- Only ACCOUNT takes no id; every other target without one would render a link to a listing screen
-- rather than the thing the message was about. Enforced here because a row is worth rejecting at
-- write time — silently sending a half-formed link is the failure that reaches a customer.
alter table notification.notification_log
    add constraint chk_log_link_id
    check (link_target is null
           or (link_target = 'ACCOUNT' and link_id is null)
           or (link_target <> 'ACCOUNT' and link_id is not null));

-- Deliberately no index. Nothing looks a notification up BY its link; the columns are read back
-- with the row that was already found by id, order or recipient. An index here would be write cost
-- on every send in exchange for a query nobody makes.
