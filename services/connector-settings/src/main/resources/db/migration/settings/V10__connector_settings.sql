-- Connector Settings (Section 8): business-user-managed runtime configuration.
--
-- Deliberately separate from the Config Server's Git-backed store. Config Server holds ops-managed
-- values that change through a commit and a pipeline; this holds the handful a non-engineer needs
-- to change from a Backoffice screen - primarily which SMS provider is live. Keeping them apart
-- avoids handing non-engineers Git access, and avoids exposing connection pool sizes in a
-- business-facing settings page.

CREATE TABLE connector_settings (
    connector_type varchar(32)  PRIMARY KEY,
    -- The active provider, e.g. DEV_PASSTHROUGH / MONTYMOBILE / TWILIO for SMS.
    provider       varchar(64)  NOT NULL,
    -- Non-secret knobs only: sender ids, from-addresses, feature flags, the simulator toggle.
    --
    -- SECRETS MUST NOT BE STORED HERE. API keys and bank credentials live in Vault; this table
    -- holds only the Vault PATH they can be read from, so the Backoffice UI can show a masked
    -- value and a last-rotated date without the secret ever reaching a browser.
    config_json    jsonb        NOT NULL DEFAULT '{}'::jsonb,
    vault_path     varchar(255),
    secret_rotated_at timestamptz,
    is_active      boolean      NOT NULL DEFAULT true,
    updated_by     varchar(64)  NOT NULL,
    updated_at     timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT chk_connector_type CHECK (connector_type IN ('SMS', 'EMAIL', 'PUSH', 'CORE_BANKING'))
);

-- Every change is audited: this page can redirect real SMS traffic and real money, so "who
-- switched the provider, when, and from what" has to be answerable after the fact (Section 8).
CREATE TABLE connector_settings_audit (
    id             uuid         PRIMARY KEY,
    connector_type varchar(32)  NOT NULL,
    old_value      jsonb,
    new_value      jsonb        NOT NULL,
    changed_by     varchar(64)  NOT NULL,
    changed_at     timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX idx_settings_audit_connector ON connector_settings_audit (connector_type, changed_at DESC);

-- Seed the four connectors in their safe default state.
--
-- SMS starts in DEV_PASSTHROUGH, which redirects the message to an email inbox instead of sending
-- anything. Section 7 is explicit that launching before the MontyMobile/Twilio commercial decision
-- is safe precisely because this is the default - no code change is needed to go live later.
INSERT INTO connector_settings (connector_type, provider, config_json, vault_path, updated_by) VALUES
    ('SMS', 'DEV_PASSTHROUGH',
     '{"testInbox":"sms-test@dev.local","senderId":"Delivery"}'::jsonb,
     'secret/sms-connector', 'system'),
    ('EMAIL', 'SMTP',
     '{"fromAddress":"no-reply@delivery.local","fromName":"Delivery"}'::jsonb,
     'secret/email-connector', 'system'),
    -- DEV_LOG, not FIREBASE. There is no dev Firebase project yet, and seeding a provider whose
    -- credentials are empty would make every push permanently fail from the first boot. Flipping
    -- to FIREBASE is a Backoffice change once a project exists - the client is already deployed.
    ('PUSH', 'DEV_LOG',
     '{"projectId":""}'::jsonb,
     'secret/push-connector', 'system'),
    -- Dev points at the simulator; staging/prod flip this to REAL (Section 7).
    ('CORE_BANKING', 'SIMULATOR',
     '{"baseUrl":"http://corebanking-simulator:8114"}'::jsonb,
     'secret/corebanking-connector', 'system');
