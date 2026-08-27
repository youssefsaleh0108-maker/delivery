-- Per-user, per-category notification preferences — the settings screen's notifications row.
--
-- WHY ONLY DEVIATIONS ARE STORED. There is no seed here and no row is written when a user signs up.
-- The default for a category lives in code (NotificationCategory), and the absence of a row means
-- "this user has not expressed a preference", which is a different and more useful fact than a row
-- that happens to hold today's default. Seeding instead would mean a backfill across every existing
-- user, four rows per channel per user forever, and — the real cost — a revised default silently
-- failing to apply to anyone who already had a row saying the old one.
--
-- WHY THE KEY INCLUDES THE CHANNEL. "Stop pushing promotions to my lock screen" and "stop emailing
-- me promotions" are separate asks. Keying by category alone forces a user who wants one to accept
-- the other, and that is the shape of settings screen people abandon by turning everything off.
create table notification.notification_preference (
    recipient_id  varchar(64)  not null,
    category      varchar(32)  not null,
    channel       varchar(16)  not null,
    enabled       boolean      not null,
    -- For PROMOTIONS this is the evidence of when consent was given, which is the question asked
    -- when somebody disputes having opted in. Hence updated in place on change rather than the row
    -- being deleted and rewritten.
    updated_at    timestamptz  not null default now(),
    primary key (recipient_id, category, channel),
    constraint chk_preference_category
        check (category in ('ORDER_UPDATES', 'CHAT', 'PROMOTIONS', 'ACCOUNT')),
    constraint chk_preference_channel
        check (channel in ('SMS', 'EMAIL', 'PUSH', 'IN_APP'))
);

comment on table notification.notification_preference is
    'Deviations from the coded per-category defaults. No row means the default applies. '
    'ACCOUNT rows are never consulted by the dispatch path: security and account-critical '
    'messages cannot be suppressed by a preference, so no row here can silence one.';

-- ACCOUNT is accepted by the CHECK above rather than forbidden, and that is on purpose. The
-- dispatch path short-circuits the category before it ever reads this table, so a row could not
-- suppress anything even if one existed — and refusing the value at the database level would mean
-- an operator inserting one by hand gets an error suggesting the setting WOULD have worked. The API
-- refuses the change explicitly instead, with a reason.

-- The only query the dispatch path makes is the primary key, which is already served. This one is
-- for the settings screen and for support: everything one user has changed, in a single round trip
-- rather than sixteen point lookups to paint one screen.
create index idx_notification_preference_recipient
    on notification.notification_preference (recipient_id);
