-- Auto-approval stops being an environment variable and becomes a decision somebody makes, signs
-- for, and can be asked about later.
--
-- Until now the only way to let riders onto the platform without a reviewer was AUTO_APPROVE_RIDER
-- on a container, which means the answer to "who decided nobody would read these applications, and
-- when" is a deploy pipeline and a person's memory. That is the wrong record for a switch whose ON
-- position puts strangers on the platform as live merchants. These two tables move the decision
-- into the schema beside the applications it governs: the current position per kind, and every
-- change ever made to it.
--
-- The environment variables do not go away. They become the SEED — the value in force for a kind
-- nobody has decided in the portal yet — which is what makes this migration safe to apply to a
-- running deployment. See the deliberately empty table below.

-- The current position, one row per kind, written only by the backoffice.
--
-- NO SEED ROWS, and that is the whole point. A kind with no row here falls back to the deployed
-- delivery.onboarding.auto-approve.* value, so every existing environment behaves after this
-- migration exactly as it did before it: nothing has been decided, so nothing has changed. Seeding
-- the three kinds from the defaults would look equivalent and is not — it would freeze today's
-- environment variable into the database and silently stop the ops-managed value from ever
-- mattering again, including a later change made to turn auto-approval OFF in a hurry.
--
-- A row's mere existence is therefore meaningful: it is the difference the API reports as
-- source=PORTAL rather than source=CONFIG.
CREATE TABLE auto_approval_settings (
    -- OnboardingApplication.Kind. The CHECK is here rather than a Postgres enum type so that
    -- adding a kind is a migration in this file and not an ALTER TYPE somebody has to remember.
    kind        varchar(16)  PRIMARY KEY,

    -- true = applications of this kind are approved on submission with no human review.
    automatic   boolean      NOT NULL,

    -- The Keycloak sub of the BACKOFFICE user who last set it. Same actor column as every other
    -- table in this schema, and never client-supplied — the service reads it from the token.
    changed_by  varchar(64)  NOT NULL,

    -- Written by the service rather than defaulted here, because the value is returned in the same
    -- response that sets it; a DEFAULT would leave the API returning null until the row was read
    -- back. The default is kept anyway so a hand-written INSERT cannot leave the column empty.
    changed_at  timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_auto_approval_kind CHECK (kind IN ('MERCHANT', 'CARRIER', 'RIDER'))
);

-- Append-only history of every change, in the shape connector_settings_audit uses: the subject,
-- both values, who, when. Rows are never updated or deleted.
--
-- One deliberate difference from that table, which stores NULL as the old value of a first change.
-- Here the old value is always recorded, together with where it came from, because "NULL" would
-- lose the fact this record exists to keep: whether merchant auto-approval was already ON via the
-- environment when somebody first pinned it in the portal. old_source = 'CONFIG' says the value
-- beside it was the deployment default in force at that moment; 'PORTAL' says it was an earlier
-- decision on this table. The new value is always a portal decision, so it needs no such column.
CREATE TABLE auto_approval_audit (
    id             uuid         PRIMARY KEY,
    kind           varchar(16)  NOT NULL,

    old_automatic  boolean      NOT NULL,
    old_source     varchar(8)   NOT NULL,
    new_automatic  boolean      NOT NULL,

    changed_by     varchar(64)  NOT NULL,
    changed_at     timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_auto_approval_audit_kind
        CHECK (kind IN ('MERCHANT', 'CARRIER', 'RIDER')),
    CONSTRAINT chk_auto_approval_audit_source
        CHECK (old_source IN ('CONFIG', 'PORTAL'))
);

-- The question this table answers is "when did rider auto-approval change, and to what", asked
-- newest-first about one kind at a time.
CREATE INDEX idx_auto_approval_audit_kind
    ON auto_approval_audit (kind, changed_at DESC);
