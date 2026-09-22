-- How often a shop's menu was opened, and roughly when in the day.
--
-- The merchant screen (Figma 139:255) asks what the menu is doing. Most of that question the
-- platform could already answer from records it keeps for other reasons — what the shop sold
-- (delivered_order_lines, V22), what the neighbourhood searched for and could not find
-- (search_demand_week, V40). One part it could not: nobody has ever counted a reader of
-- /s/{slug}. The page is stateless by design and writes nothing.
--
-- This table is the smallest thing that answers it.
--
-- ============================================================================================
-- PRIVACY: there is no such thing as a row per visit here
-- ============================================================================================
--
-- search_demand_log (V40) had a hard problem: it must keep one row per search, because the thing
-- it measures is which words were typed, and so it has to spend the whole of that migration
-- explaining how a row cannot be tied back to a person — a random key, a shuffled flush, a
-- truncated hour, a coarse area, a banded distance.
--
-- This table has no such problem, because it never holds a visit at all. A row is a COUNTER:
-- one shop, one day, one part of that day, one way in, and a number. Views are added into it.
-- There is nothing to re-link, because there is nothing to link: no key orders the readers, no
-- ctid hands back an arrival sequence, no column narrows to a person, and no shuffle is needed
-- because nothing was ever a sequence. Two people and one person who looked twice are the same
-- two in this table, permanently and by construction.
--
-- What it therefore does NOT hold, and could not be made to hold without a new migration:
--
--   * account, session, device or request id, IP address, user agent. The public page is
--     anonymous and reads nothing about its caller (PublicShopPageController), and counting must
--     not be the reason that changes;
--   * a timestamp. Not truncated to the hour, as V40 does — absent. The finest time here is a
--     part of the day, four to a day, and it is computed at flush time and then thrown away;
--   * a referrer, a country, a language, or anything else that would let two counters be read as
--     one person moving between them;
--   * the customer's side of anything at all. A row is a fact about a document being served.
--
-- ============================================================================================
-- What a number here can and cannot be made to mean
-- ============================================================================================
--
-- It counts REQUESTS THIS SERVICE ANSWERED. That is not the same as people, and the API never
-- calls it people:
--
--   * one reader who opens the menu three times is three, and the platform cannot tell otherwise
--     without keeping something about them, which is exactly what it refuses to keep;
--   * a reader served by their own browser's cache or by a CDN is ZERO. The page says
--     `Cache-Control: max-age=300, public`, so a link opened by everybody in a group chat inside
--     five minutes may reach the service once;
--   * a link preview and a crawler are one each, the same as a person.
--
-- So this is a trend, not a headcount, and the merchant-facing read says so in the response
-- rather than leaving the screen to guess. MenuInsights rounds every figure DOWN to a band and
-- publishes nothing under a floor, for the reason V40 gives about its own: a number small enough
-- to be one person is a number about that person.
--
-- Retention is 90 days, the same as the search log, and for a simpler reason: the screen asks for
-- at most thirty, so the rest is a year of counters nobody reads.
CREATE TABLE menu_view_day (
    -- Whose menu. The shop, never the reader.
    store_id uuid NOT NULL REFERENCES stores (id) ON DELETE CASCADE,

    -- The calendar day IN THE SHOP'S OWN ZONE (Store.zone()), not UTC. "Tuesday" has to mean the
    -- shop's Tuesday or the merchant reading it is being told about somebody else's day. A date,
    -- not a timestamp: there is no time of day on this row beyond the column below.
    viewed_on date NOT NULL,

    -- Which part of the shop's day, four to a day, computed at flush time from the shop's zone:
    --   MORNING 05:00-10:59   MIDDAY 11:00-16:59
    --   EVENING 17:00-22:59   NIGHT  23:00-04:59
    --
    -- Named rather than numbered, like search_demand_week.kind: a person reading this table in
    -- psql should not have to find a migration to learn what a 2 was, and a stored ordinal is a
    -- thing a reordered enum silently rewrites the meaning of.
    --
    -- Four, and not twenty-four. The screen's question is "when should I be ready", which a part
    -- of the day answers and an hour only appears to: a shop reading "one open at 19:00 on
    -- Tuesday" has been told about a person, and the fact that it took a quiet shop to make that
    -- sentence true is not a defence. V40 keeps an hour because its floor of five distinct PEOPLE
    -- is computed from something this table has not got — there is no account behind an anonymous
    -- page open, so there is nothing here to count people with, and the granularity has to carry
    -- the weight the people-floor carries there.
    day_part varchar(8) NOT NULL,

    -- How the reader arrived, as far as the URL itself says:
    --   TABLE  the address carried the table parameter a table card prints (?t=N)
    --   LINK   it did not
    --
    -- Note what is NOT here: "QR". A shop's counter QR (/s/{slug}/qr.png) encodes the plain page
    -- address with nothing added, so a scan of it and a tapped link are the same request and no
    -- honest column could separate them. Only the table cards carry a marker, because they had to
    -- carry the table number anyway. Calling this "scans" would be inventing a number.
    source varchar(8) NOT NULL,

    -- Added into, never inserted per view.
    views integer NOT NULL,

    -- The counter's identity IS the bucket. No surrogate key, because a surrogate key would be a
    -- sequence, and this table is the one shape that genuinely has no sequence in it.
    PRIMARY KEY (store_id, viewed_on, day_part, source),

    CONSTRAINT chk_menu_view_day_part
        CHECK (day_part IN ('MORNING', 'MIDDAY', 'EVENING', 'NIGHT')),
    CONSTRAINT chk_menu_view_day_source CHECK (source IN ('LINK', 'TABLE')),
    CONSTRAINT chk_menu_view_day_views CHECK (views > 0)
);

COMMENT ON TABLE menu_view_day IS
    'Counters of menu opens per shop per day per part of day per way in. Holds no visit, no '
    'timestamp and nothing about a reader, by design: see V44__menu_views.sql.';

-- The one question asked of it: this shop, this window, oldest-first for the series. Retention
-- deletes by date and rides the same index.
CREATE INDEX idx_menu_view_day_store_date ON menu_view_day (store_id, viewed_on);
CREATE INDEX idx_menu_view_day_date ON menu_view_day (viewed_on);
