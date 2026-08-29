-- WHO a leg belongs to, as opposed to where the money would be posted.
--
-- THE PROBLEM THIS FIXES. `account_ref` is resolved from a Keycloak attribute and is an OMNIBUS
-- bucket: every merchant credit written so far landed on a single 'ACC-MERCHANT' regardless of which
-- shop sold the goods, and every genuinely onboarded merchant resolves to 'ACC-UNMAPPED' because
-- nobody has a `bankAccountRef` yet. Both are correct as BANK POSTINGS — that really is the account
-- the money would move through — and both are useless for answering "what do we owe Rose & Crust
-- this month". A bank account number is not an identity, and the ledger had no other.
--
-- So this is a SECOND pair of columns rather than a change to account_ref. The two answer different
-- questions and will legitimately disagree: two shops can share a payout account, one shop can
-- change theirs mid-month, and a statement must not be restated when either happens. Overloading
-- account_ref with identity is what made the omnibus bucket look correct in the first place.
--
-- The identity is already on the order event — merchantId, riderId, deliveryProviderId — and
-- OrderEventListener already parses merchantId. It was simply thrown away at settlement time.

ALTER TABLE transactions
    ADD COLUMN counterparty_kind varchar(16),
    ADD COLUMN counterparty_ref  varchar(64);

COMMENT ON COLUMN transactions.counterparty_kind IS
    'Which sort of party this leg belongs to: MERCHANT, RIDER, CARRIER or PLATFORM. NULL on legs '
    'written before attribution existed, and on CUSTOMER_DEBIT, which has no counterparty in this '
    'model.';

COMMENT ON COLUMN transactions.counterparty_ref IS
    'The party''s own identifier - a Keycloak subject for a person or shop, a provider id for a '
    'delivery company, a constant for the platform. NOT an account number; see account_ref.';

-- NULLABLE, AND DELIBERATELY NOT BACKFILLED.
--
-- The 45 rows already in this table were written before the identity was recorded, and the only
-- place it survives is the `orders` schema, which belongs to Order Manager. A migration that reached
-- across to read it would (a) very possibly fail outright, because this service's DB role is not
-- granted on that schema, and (b) hard-code a cross-service join into a file that runs at startup —
-- the exact coupling schema-per-service exists to prevent.
--
-- So those rows stay NULL and every statement surface accounts for them explicitly: the
-- counterparties listing carries an `unattributed` block naming the amount and the order count that
-- cannot be assigned to anybody. An honest hole with a number on it is worth more than a backfill
-- that guesses, and it shrinks to zero on its own as new orders settle.
ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_counterparty_kind CHECK (
        counterparty_kind IS NULL OR counterparty_kind IN
            ('MERCHANT', 'RIDER', 'CARRIER', 'PLATFORM'));

-- Both or neither. A kind with no ref names a category and not a party, and a ref with no kind
-- cannot be looked up in any directory — either one would be a row that a statement query silently
-- skips while a reconciliation total silently counts.
ALTER TABLE transactions
    ADD CONSTRAINT chk_txn_counterparty_paired CHECK (
        (counterparty_kind IS NULL) = (counterparty_ref IS NULL));

-- The statement query: one party's legs over a window. `created_at` is in the index because every
-- statement is bounded by a date range and none of them ever wants the whole history.
CREATE INDEX idx_txn_counterparty
    ON transactions (counterparty_kind, counterparty_ref, created_at);

-- The other half of the same screen: what could NOT be attributed. Partial, because this set only
-- ever shrinks - it is closed at the moment attribution shipped and no new row joins it.
CREATE INDEX idx_txn_unattributed
    ON transactions (created_at)
    WHERE counterparty_kind IS NULL;
