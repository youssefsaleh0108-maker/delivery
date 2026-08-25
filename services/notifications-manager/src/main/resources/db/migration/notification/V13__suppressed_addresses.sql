-- Addresses the platform has been told are dead, and must stop using.
--
-- A device token stops working the moment its app is uninstalled, and FCM says so on the next send.
-- Nothing acted on that before: the contact details live in Keycloak, and Notifications Manager
-- reads them through a service account holding view-users and nothing else. Widening that to
-- manage-users so the notification path could edit user records would be a poor trade — a far larger
-- privilege than the problem needs.
--
-- So the suppression is kept here instead, and applied when contacts are resolved. Keycloak stays
-- the source of truth for what a user's address IS; this table records what the platform has learnt
-- about whether it still works.
--
-- Keyed by the address rather than by the user: a token re-registered after a reinstall is a
-- different string, so a returning user is reachable again with no un-suppression step. That is the
-- property that makes this safe to write from the delivery path without an operator ever having to
-- clear a row by hand.
create table notification.suppressed_address (
    channel        varchar(16)  not null,
    address        varchar(512) not null,
    recipient_id   varchar(64),
    reason         text,
    provider       varchar(64),
    suppressed_at  timestamptz  not null default now(),
    primary key (channel, address),
    constraint chk_suppressed_channel
        check (channel in ('SMS', 'EMAIL', 'PUSH', 'IN_APP'))
);

comment on table notification.suppressed_address is
    'Addresses a provider has reported as permanently undeliverable (dead device token, '
    'disconnected number, hard bounce). Consulted when resolving contacts.';

-- Every lookup is (channel, address), which the primary key already serves. This one supports the
-- operator question instead: which of a given user''s addresses have gone dead.
create index idx_suppressed_address_recipient
    on notification.suppressed_address (recipient_id)
    where recipient_id is not null;
