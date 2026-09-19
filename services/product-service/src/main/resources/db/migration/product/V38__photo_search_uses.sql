-- Photo search: how often each account has had a photo read, and nothing else.
--
-- A customer's search by photo and a merchant's "find in my catalogue by photo" each send the photo to
-- a paid vision provider once real recognition is on, so every read is counted and capped per account
-- (PhotoQuota): per rolling day, per minute, and for customers across the whole platform per day.
--
-- Nothing about the photo is stored here or anywhere: no bytes, no object key, no description, no
-- search terms and no location. A row says only that this account had one photo read, of which kind,
-- and when. The photo itself goes straight from the request to the reader and is dropped when the read
-- returns; it never touches MinIO, whose product-images bucket is public-read, nor this database.
--
-- Rows older than 48 hours answer no limit (the longest window is a rolling 24 hours), and the
-- transaction that counts a new use deletes them, so the table holds at most two days of uses.
CREATE TABLE photo_search_uses (
    id uuid PRIMARY KEY,
    -- Keycloak sub of the account whose photo was read.
    account_id varchar(64) NOT NULL,
    -- CUSTOMER_SEARCH: a customer searching the shops by photo. MERCHANT_FIND: a merchant finding a
    -- product in their own catalogue by photo. Counted apart, with limits of their own.
    kind varchar(16) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_photo_search_use_kind CHECK (kind IN ('CUSTOMER_SEARCH', 'MERCHANT_FIND'))
);

-- Each limit counts exactly this: one account's uses of one kind over the last day or minute, and the
-- oldest of them, which says how long until the next one is allowed.
CREATE INDEX idx_photo_search_uses_account ON photo_search_uses (account_id, kind, created_at DESC);

-- The platform's customer searches over the last day, and the sweep of rows past 48 hours.
CREATE INDEX idx_photo_search_uses_created ON photo_search_uses (created_at);
