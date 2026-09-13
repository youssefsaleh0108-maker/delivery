-- Keeping neighbourhood rooms safe: reports, blocks, moderator actions and their audit trail.
--
-- Required, not optional polish. A room is user-generated content between strangers, and the app
-- stores refuse such a feature without a way to report a message, block a person, and a moderator
-- who acts on reports. Everything here is enforced by the server: a blocked author is filtered out
-- of the blocker's history query and skipped at live delivery, and a muted member's post is refused
-- before it is written - none of it depends on a client choosing to behave.

-- Removal is a tombstone, never a DELETE. The row stays for the audit trail and for an appeal; what
-- changes is that every member is served "removed" in its place from then on.
ALTER TABLE chat_room_messages
    ADD COLUMN hidden_at timestamptz,
    ADD COLUMN hidden_by varchar(64);

-- A neighbour flagging a message for a moderator.
CREATE TABLE chat_room_reports (
    id          uuid        PRIMARY KEY,
    message_id  uuid        NOT NULL REFERENCES chat_room_messages (id),
    room_id     uuid        NOT NULL REFERENCES chat_rooms (id),
    reporter_id varchar(64) NOT NULL,
    reason      varchar(24) NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    -- Set when a moderator hides the message or dismisses its reports.
    resolved_at timestamptz,
    resolved_by varchar(64),
    resolution  varchar(16),
    -- One report per person per message: tapping Report twice is one report, and ten reports on a
    -- message means ten people, which is what the queue's ordering has to be able to trust.
    CONSTRAINT uq_chat_room_report UNIQUE (message_id, reporter_id),
    CONSTRAINT ck_chat_room_report_reason
        CHECK (reason IN ('SPAM', 'ABUSE', 'PERSONAL_INFO', 'OTHER')),
    CONSTRAINT ck_chat_room_report_resolution CHECK (
        (resolved_at IS NULL AND resolved_by IS NULL AND resolution IS NULL)
        OR (resolved_at IS NOT NULL AND resolved_by IS NOT NULL
            AND resolution IN ('HIDDEN', 'DISMISSED')))
);

-- The moderation queue reads open reports only; it should cost what is waiting, not what was ever said.
CREATE INDEX idx_chat_room_reports_open ON chat_room_reports (message_id) WHERE resolved_at IS NULL;

-- A person choosing not to see somebody. Person to person rather than per room, so moving
-- neighbourhood does not bring back the neighbour you blocked.
CREATE TABLE chat_blocks (
    id           uuid        PRIMARY KEY,
    blocker_id   varchar(64) NOT NULL,
    blocked_id   varchar(64) NOT NULL,
    -- The name the blocked person went by when blocked, so "people you blocked" has something to show
    -- without ever handing the blocker the blocked person's account id.
    blocked_name varchar(80),
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_chat_block UNIQUE (blocker_id, blocked_id),
    CONSTRAINT ck_chat_block_not_self CHECK (blocker_id <> blocked_id)
);

-- Live delivery asks "who among these listeners blocked the author".
CREATE INDEX idx_chat_blocks_blocked ON chat_blocks (blocked_id, blocker_id);

-- Every moderator action, written in the same transaction as the action itself: if the audit row
-- cannot be written, the hide or mute does not happen. Same principle as chat_transcript_access.
CREATE TABLE chat_moderation_actions (
    id             uuid         PRIMARY KEY,
    -- The staff member's Keycloak sub, from the token; nothing in a request can name another actor.
    actor_id       varchar(64)  NOT NULL,
    action         varchar(24)  NOT NULL,
    room_id        uuid         NOT NULL REFERENCES chat_rooms (id),
    message_id     uuid         REFERENCES chat_room_messages (id),
    -- Whose mute changed. Staff act through a message and never type an account id; it is recorded
    -- here so "every action ever taken against this person" is answerable.
    target_user_id varchar(64),
    muted_until    timestamptz,
    -- Required: the trail should say why, not only that.
    reason         varchar(200) NOT NULL,
    correlation_id varchar(64),
    created_at     timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_chat_moderation_action
        CHECK (action IN ('HIDE_MESSAGE', 'DISMISS_REPORTS', 'MUTE_MEMBER', 'UNMUTE_MEMBER'))
);

CREATE INDEX idx_chat_moderation_room   ON chat_moderation_actions (room_id, created_at DESC);
CREATE INDEX idx_chat_moderation_actor  ON chat_moderation_actions (actor_id, created_at DESC);
CREATE INDEX idx_chat_moderation_target ON chat_moderation_actions (target_user_id, created_at DESC);
