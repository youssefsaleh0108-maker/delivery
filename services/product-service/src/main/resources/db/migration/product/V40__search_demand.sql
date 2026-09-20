-- What the neighbourhood looked for, and what nobody nearby sells.
--
-- Customer item search shipped in V37, so the platform can now see something no single shop can: what
-- people around a street asked for, and whether anyone near them sells it. This migration adds the
-- three tables that turn that into a weekly signal for merchants — the log, the week's roll-up, and
-- the ledger of digests already sent.
--
-- ============================================================================================
-- PRIVACY: what search_demand_log deliberately does NOT hold
-- ============================================================================================
--
-- This table must be useless to anyone trying to follow one customer, including a future engineer
-- with full database access and good intentions. So it carries NO:
--
--   * account id, customer id, or any pseudonym of one. There is no column a person could be joined
--     on, so "everything this account searched for" is not a query anybody can write;
--   * session, request or device id, IP address or user agent — anything that would tie two rows to
--     one person or one shopping trip;
--   * exact pin. The customer's coordinates reach this service and are thrown away; only the id of
--     the delivery area nearest the pin is kept, which is a neighbourhood shared by thousands;
--   * sequential key. The primary key is random (uuid), NOT a bigserial: a monotonic id would order
--     the rows, and two rows adjacent in a coarse hour would read as one person's two searches.
--     A random key is not enough on its own, and it would be a dangerous thing to claim it is: this
--     table is insert-only and single-writer, so ORDER BY ctid reads the heap in the order the rows
--     were inserted in and hands the sequence straight back. That is why the recorder buffers rows
--     and writes each flush in a shuffled order (SearchDemandRecorder) — the heap says which flush a
--     row was in, never where in it;
--   * minute or second. searched_at is truncated to the hour by the writer, so the fine timing that
--     would otherwise re-link rows within an hour is not recorded either.
--
-- What is left describes a street, not a person: "in the hour after noon, somebody in Hamra looked
-- for nappies and the nearest shop selling them was over two kilometres away".
--
-- Repeats are collapsed BEFORE the row is written (SearchDemandRecorder), in memory, using the
-- account id the request already carries — so one person retyping a word makes one row without the
-- account id ever reaching the disk. That is the only place a person and a search are ever both in
-- scope, and it is a bounded in-process cache that a restart empties.
--
-- Retention is 90 days (SearchDemandMaintenance), on the pattern TrackingPartitionMaintenance uses.
CREATE TABLE search_demand_log (
    -- Random, never sequential. See the note above.
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Truncated to the hour by the writer. The week it falls in is what the roll-up reads; the age is
    -- what retention reads.
    searched_at timestamptz NOT NULL,

    -- The coarse location, and the only location: the delivery area whose centre is nearest the
    -- customer's pin, within a cap. NULL when the search carried no pin, or when the pin was too far
    -- from every placed area to belong to one — recorded as "somewhere unknown" rather than snapped
    -- to a distant neighbourhood. A NULL area is never reported to anybody.
    area_id uuid REFERENCES delivery_zones (id) ON DELETE SET NULL,

    -- What was looked for, already folded by search_fold (V37): lower case, no accents, Arabic
    -- letter families normalised. A multi-term search (a photo's name, Arabic name and brand) joins
    -- its folded terms with a single space, in slot order, so one search is one term string.
    term text NOT NULL,

    -- How many shops the search answered with, across every page. Zero is the signal that matters.
    result_count integer NOT NULL,

    -- Whether any answering shop is in the searcher's own area. False when nothing matched.
    in_own_area boolean NOT NULL,

    -- Metres to the nearest answering shop, rounded UP to a 250 m band by the writer. NULL when
    -- nothing matched or the search carried no pin.
    --
    -- Banded rather than exact because a metre-accurate distance to a shop whose pin is public would
    -- place the customer on a circle around it. A 250 m band leaves an annulus, which together with
    -- an area-level location says nothing about a household. The band is well under the 2 km the
    -- weekly job asks about, so nothing is lost.
    nearest_metres integer,

    -- The shop vertical the search was scoped to, when a search can be scoped. Customer item search
    -- is goods-only and takes no scope today, so this is NULL on every row it writes; the column is
    -- here because the roll-up reads it and a scoped search must not need a migration to be counted.
    vertical varchar(32),

    CONSTRAINT chk_search_demand_log_results CHECK (result_count >= 0),
    CONSTRAINT chk_search_demand_log_nearest CHECK (nearest_metres IS NULL OR nearest_metres >= 0),
    -- Nothing matched, so nothing can have been in the area or at a distance.
    CONSTRAINT chk_search_demand_log_empty CHECK (
        result_count > 0 OR (in_own_area = false AND nearest_metres IS NULL))
);

COMMENT ON TABLE search_demand_log IS
    'One row per distinct customer item search. Holds no account, session, device or exact location '
    'and no sequential key, by design: see V40__search_demand.sql.';

-- The roll-up reads one week of one area; retention reads the oldest rows. Both are served by this.
CREATE INDEX idx_search_demand_log_area_time ON search_demand_log (area_id, searched_at);
CREATE INDEX idx_search_demand_log_time ON search_demand_log (searched_at);

-- ============================================================================================
-- Who has already asked, without knowing who they are
-- ============================================================================================
--
-- The floor that decides whether a term may be spoken of has to count PEOPLE. Counting rows does
-- not: one household searching for the same thing on five evenings is five rows, and a merchant who
-- wanted to read a neighbour's search could clear a floor of five by contributing four of their own.
-- A floor that one person can clear alone is not a floor.
--
-- So each (account, area, term, week) leaves at most one row here, and the roll-up counts these
-- rows instead of log rows. What is stored is not the account and cannot be turned back into it:
--
--   seen_key = HMAC-SHA256(secret, "v1" | account | area | term | week)
--
-- The secret is read from the environment (DEMAND_SEEN_SECRET) and is never in this repository, in
-- this database, or in any event. Three properties follow, and they are the reason for this shape
-- rather than a hash of the account:
--
--   * not reversible, and not guessable. Without the secret, an account id cannot be turned into a
--     key or a key into an account id, so holding this whole table — a dump, a backup, a restored
--     snapshot — yields nothing about anybody;
--   * not joinable across terms. The term is inside the HMAC, so the same person searching for two
--     things leaves two unrelated values. "Everything this person looked for" cannot be assembled
--     here any more than it can in search_demand_log;
--   * countable, which is all the roll-up needs: rows with the same (week, area, term) are distinct
--     people, and how many there are is the only question asked of them.
--
-- WITH NO SECRET, NOTHING IS PUBLISHED. No key can be computed, so no row is written, so no term
-- reaches the floor and the roll-up refuses to run at all (UnmetDemand). Failing closed is the only
-- safe direction: the alternative — falling back to counting rows — is the weak floor this table
-- exists to replace, and it would fail silently.
--
-- ON ROTATION, THE COUNT RESTARTS. key_id is a fingerprint of the secret that computed the row (not
-- the secret), and the roll-up counts only rows under the current one. A new secret therefore reads
-- as "nobody has asked yet" rather than counting the same person twice under two keys, so a rotation
-- can only under-publish, never over-publish. Rotate just after a Monday digest: the week in
-- progress starts counting again, and the finished week is already sent.
--
-- These rows are kept only as long as the week they bound — the current week and the one before it,
-- which is as far back as the roll-up ever recomputes — and are deleted by the same retention job as
-- the log (UnmetDemand.forgetOldSearches).
CREATE TABLE search_demand_seen (
    -- Hex of the HMAC above, 64 characters of SHA-256. Never an account, and never a pseudonym that
    -- survives the term or the week.
    seen_key varchar(64) PRIMARY KEY,

    -- Which secret computed this row. A fingerprint derived from the secret, not the secret itself.
    key_id varchar(32) NOT NULL,

    -- The week the search fell in, Monday 00:00 in the platform's zone.
    week_start timestamptz NOT NULL,

    -- The neighbourhood, as search_demand_log holds it. A search with no area is never reported to
    -- anybody, so it needs no row here.
    area_id uuid NOT NULL REFERENCES delivery_zones (id) ON DELETE CASCADE,

    -- The folded term, as search_demand_log holds it.
    term text NOT NULL,

    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE search_demand_seen IS
    'One row per person per area per term per week, as an HMAC under a server-side secret. Counted '
    'by the roll-up so the floor counts people; holds no account and cannot be joined across terms.';

-- The one question asked of this table: how many people asked for this term, in this area, that week.
CREATE INDEX idx_search_demand_seen_count
    ON search_demand_seen (week_start, area_id, term, key_id);

-- Retention deletes by week.
CREATE INDEX idx_search_demand_seen_week ON search_demand_seen (week_start);

-- ============================================================================================
-- The week, as a merchant is shown it
-- ============================================================================================
--
-- Computed once by the roll-up rather than on every read: the Demand Radar polls, and a merchant
-- refreshing must not run an aggregate over a quarter's worth of searches. It also means the
-- five-search floor is applied once, in one place, and the log is never read by a request thread.
--
-- A term reaches this table only when at least the floor's worth of DISTINCT PEOPLE asked for it in
-- that week and that area, counted through search_demand_seen above. Under the floor it is one
-- household's shopping list, not a market signal, and it is simply not written.
CREATE TABLE search_demand_week (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Monday 00:00 in the platform's zone (delivery.platform.zone), stored as the instant it was.
    week_start timestamptz NOT NULL,

    area_id uuid NOT NULL REFERENCES delivery_zones (id) ON DELETE CASCADE,

    -- The folded term, as search_demand_log holds it.
    term text NOT NULL,

    -- NONE: every search for this term in this area answered with no shop at all.
    -- FAR: searches answered, but the nearest shop was further than the far-threshold (2 km).
    kind varchar(16) NOT NULL,

    -- How many searches asked for it — rows in the log, once the people floor has been cleared. Kept
    -- exact here because this table is never served to a merchant as-is: the API rounds it to a band
    -- ("about 10"). An exact count per area per week over a floor of five people is a market size,
    -- not a person, but it is still not a number a shop needs.
    searches integer NOT NULL,

    -- 1 is the term the most searches asked for in this area, this week, of this kind.
    rank integer NOT NULL,

    computed_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_search_demand_week_kind CHECK (kind IN ('NONE', 'FAR')),
    CONSTRAINT chk_search_demand_week_searches CHECK (searches > 0),
    CONSTRAINT chk_search_demand_week_rank CHECK (rank > 0),
    -- One row per term per kind per area per week, so a re-run replaces rather than doubles.
    CONSTRAINT uq_search_demand_week UNIQUE (week_start, area_id, kind, term)
);

CREATE INDEX idx_search_demand_week_lookup
    ON search_demand_week (area_id, week_start DESC, kind, rank);

-- ============================================================================================
-- The digests already sent
-- ============================================================================================
--
-- One row per merchant per week, taken BEFORE the message is raised. The unique constraint is what
-- makes the weekly send idempotent: a second run of the job, a restarted pod or a second replica
-- loses the insert and sends nothing. Notifications Manager deduplicates again on its own side from
-- the same key, so a message that was raised twice still reaches the merchant once.
--
-- The merchant id here is a merchant's, not a customer's, and it is the account the message was
-- addressed to — the ordinary record every other notification keeps. Nothing about searches or
-- searchers is in this table beyond how many terms the message named.
CREATE TABLE search_demand_digest (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    week_start timestamptz NOT NULL,
    -- Keycloak sub of the merchant.
    merchant_id varchar(64) NOT NULL,
    -- How many unmet terms the message named. Zero is never sent.
    terms integer NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_search_demand_digest_terms CHECK (terms >= 0),
    CONSTRAINT uq_search_demand_digest UNIQUE (week_start, merchant_id)
);
