-- Customer item search: "who near me sells Pepsi?" answered across every live goods shop.
--
-- Until now a customer could search shop names on Home and a product name inside one shop, but not
-- products across shops. The catalogue's only cross-shop search (GET /api/products?search=) knows
-- nothing about a shop's status, stock, distance or hours, and it matches LOWER(name) LIKE, which no
-- index here serves: V10's trigram index is on name itself, and a LIKE on LOWER(name) cannot use it.
--
-- A product has one name, in whatever script and spelling its merchant typed. Lebanese shops list
-- the same Pepsi as "Pepsi", "PEPSI 1L" and "بيبسي", and Arabic is written with or without hamza,
-- taa marbuta and short vowels: أحمد and احمد, مكتبة and مكتبه, مصطفى and مصطفي are each one word
-- to a reader and two strings to a database. So this adds a folded copy of the name that search
-- compares against, and a trigram index on that copy.
--
-- 1. search_fold(text): the one spelling rule. Lower-cased, then:
--      أ إ آ ٱ -> ا    ى ی -> ي    ة -> ه    ؤ -> و    ئ -> ي    ک -> ك
--      Arabic-Indic digits ٠-٩ and Eastern Arabic-Indic digits ۰-۹ -> 0-9
--      é è ê ë -> e   à â ä á -> a   î ï í -> i   ô ö ó -> o   û ü ù ú -> u   ç -> c   ñ -> n
--        (upper case too, so the fold does not depend on what lower() knows in this locale)
--    then tashkeel (U+064B-065F, U+0670), tatweel (U+0640) and apostrophes (' ’ ‘ ʼ `) are dropped,
--    so "Lay's" is "lays" and a vowelled name matches an unvowelled search; then every run of
--    anything that is not a-z, 0-9 or an Arabic letter (U+0621-064A) becomes one space, and the
--    ends are trimmed.
--
--    The ranges are written out rather than [:alnum:], so the answer does not depend on the
--    database's locale, and nothing the fold returns can be a LIKE wildcard (% _ \) or a
--    regular-expression metacharacter: search can put a folded term inside a pattern as it is.
--
--    IMMUTABLE because products.search_name below is generated from it and indexed. That is a
--    promise that the same input always folds the same way, so this function is NEVER changed in
--    place (no CREATE OR REPLACE in a later migration): rows folded by the old body would silently
--    disagree with searches folded by the new one. A change is a new migration that drops and
--    re-adds the column, which refolds every row.
--
--    The Arabic letters and digits are written as U& escapes, because right-to-left text inside a
--    left-to-right string shows in most editors in an order that is not the order of the bytes,
--    and translate() maps position by position. Each escape is named in the list above, in order.
--
-- 2. products.search_name: the folded name, generated and stored, so it can never disagree with
--    the name it came from and no Java code writes it. Unmapped, like stores.location (V20): only
--    the search queries read it. Adding it rewrites the table once.
--
-- 3. idx_products_search_name_trgm: what serves search. GIN with trigram operators answers both
--    "contains this" (LIKE '%...%') and "sounds like this" (word similarity, the <% operator) from
--    the index. Partial on what a customer can buy (ACTIVE and in stock), the rows the customer
--    search returns at all. pg_trgm's operator class lives in public, and Flyway pins the search
--    path to this service's schema, so it is qualified, as in V10 and V11.
--
--    fastupdate = off, because customers search far more often than merchants add products. With
--    GIN's default, a new row waits in a pending list until a vacuum merges it, every search scans
--    that list end to end, and the planner, pricing that scan, turns to reading every live product
--    instead. Off, each insert updates the index at once, for the cost of one name's trigrams.
--
-- 4. idx_products_barcode_live: a barcode lookup across every shop. V25's index leads with the
--    store, which a search across shops cannot use.

CREATE FUNCTION search_fold(value text) RETURNS text
    LANGUAGE sql
    IMMUTABLE
    STRICT
    PARALLEL SAFE
AS $$
SELECT btrim(
         regexp_replace(
           regexp_replace(
             translate(
               lower(value),
               -- أ إ آ ٱ ى ی ة ؤ ئ ک
               U&'\0623\0625\0622\0671\0649\06CC\0629\0624\0626\06A9'
                 -- ٠-٩, then ۰-۹
                 || U&'\0660\0661\0662\0663\0664\0665\0666\0667\0668\0669'
                 || U&'\06F0\06F1\06F2\06F3\06F4\06F5\06F6\06F7\06F8\06F9'
                 || 'éèêëàâäáîïíôöóûüùúçñ'
                 || 'ÉÈÊËÀÂÄÁÎÏÍÔÖÓÛÜÙÚÇÑ',
               -- ا ا ا ا ي ي ه و ي ك
               U&'\0627\0627\0627\0627\064A\064A\0647\0648\064A\0643'
                 || '0123456789'
                 || '0123456789'
                 || 'eeeeaaaaiiiooouuuucn'
                 || 'eeeeaaaaiiiooouuuucn'),
             -- Dropped outright: tashkeel, the superscript alef, tatweel and apostrophes.
             '[\u064B-\u065F\u0670\u0640''\u2019\u2018\u02BC`]', '', 'g'),
           -- Everything else that is not a-z, 0-9 or an Arabic letter separates words.
           '[^a-z0-9\u0621-\u064A]+', ' ', 'g'));
$$;

ALTER TABLE products
    ADD COLUMN search_name text GENERATED ALWAYS AS (search_fold(name)) STORED;

CREATE INDEX idx_products_search_name_trgm ON products
    USING gin (search_name public.gin_trgm_ops)
    WITH (fastupdate = off)
    WHERE status = 'ACTIVE' AND in_stock;

CREATE INDEX idx_products_barcode_live ON products (barcode)
    WHERE barcode IS NOT NULL AND status = 'ACTIVE';
