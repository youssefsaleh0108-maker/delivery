-- The simulator's own storage. NOT the accounting schema - this stands in for a system outside the
-- platform, and giving it a schema the platform's services can read would let a test accidentally
-- assert against the bank's internals instead of through its API.
--
-- Version range 30+ keeps it visually distinct from the other services sharing this database.

CREATE TABLE bank_accounts (
    account_ref   varchar(64)  PRIMARY KEY,
    holder_name   varchar(255) NOT NULL,
    -- A real core banking system stores minor units to avoid float entirely. Mirrored here so the
    -- connector's rounding is exercised against the same representation the bank uses.
    balance_minor bigint       NOT NULL DEFAULT 0,
    currency      varchar(3)   NOT NULL DEFAULT 'USD',
    status        varchar(16)  NOT NULL DEFAULT 'ACTIVE',
    opened_at     timestamptz  NOT NULL DEFAULT now(),
    -- Optimistic lock. A settlement credits the platform account for every order in flight, so
    -- concurrent postings against one account are the normal case, and a lost update here would
    -- silently lose money in the one component being used as a test oracle.
    version       bigint       NOT NULL DEFAULT 0,
    CONSTRAINT chk_account_status CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED'))
);

-- Every accepted posting.
--
-- client_reference is the caller's idempotency key and is UNIQUE. That constraint is the entire
-- point of this table: a retried debit must return the ORIGINAL posting rather than move money a
-- second time, and the only way to prove the connector gets that right is for the bank to enforce
-- it the way a real one does.
CREATE TABLE bank_postings (
    id                uuid         PRIMARY KEY,
    client_reference  varchar(64)  NOT NULL UNIQUE,
    account_ref       varchar(64)  NOT NULL REFERENCES bank_accounts (account_ref),
    direction         varchar(8)   NOT NULL,
    amount_minor      bigint       NOT NULL,
    currency          varchar(3)   NOT NULL DEFAULT 'USD',
    narrative         varchar(255),
    status            varchar(16)  NOT NULL,
    balance_after_minor bigint,
    rejection_reason  text,
    posted_at         timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT chk_posting_direction CHECK (direction IN ('DEBIT', 'CREDIT')),
    CONSTRAINT chk_posting_status CHECK (status IN ('POSTED', 'REJECTED')),
    CONSTRAINT chk_posting_amount CHECK (amount_minor > 0)
);

CREATE INDEX idx_postings_account ON bank_postings (account_ref, posted_at DESC);

-- Dev accounts matching the seeded Keycloak users. The platform account is where commission lands.
--
-- The customer starts funded; the others start empty, so a settlement visibly moves money between
-- them rather than every balance staying plausible whatever happens.
INSERT INTO bank_accounts (account_ref, holder_name, balance_minor, currency) VALUES
    ('ACC-CUSTOMER', 'Casey Customer',  500000, 'USD'),
    ('ACC-MERCHANT', 'Morgan Merchant',      0, 'USD'),
    ('ACC-RIDER',    'Riley Rider',          0, 'USD'),
    ('ACC-PLATFORM', 'Delivery Platform',    0, 'USD'),
    -- Exists so the "insufficient funds" path is testable without draining a working account.
    ('ACC-EMPTY',    'Empty Test Account',   0, 'USD'),
    -- Exists so the "account frozen" permanent-rejection path is testable.
    ('ACC-FROZEN',   'Frozen Test Account', 100000, 'USD');

UPDATE bank_accounts SET status = 'FROZEN' WHERE account_ref = 'ACC-FROZEN';
