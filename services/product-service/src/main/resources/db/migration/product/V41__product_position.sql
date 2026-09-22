-- The order the items of a section are printed in, so a menu reads the way a shopkeeper wrote it.
--
-- A shop's sections have had a display order since V26 (`categories.position`, dragged on the
-- merchant's sections screen). The items inside them have not: the public page asked for the shelf
-- sorted by name, so "Espresso, Latte, Turkish coffee" came out alphabetically whatever the shop
-- meant. On a menu that is wrong — the house special goes at the top, the drink nobody orders goes
-- at the bottom, and neither is where the alphabet puts it.
--
-- Same shape as `categories.position`, deliberately: a SMALLINT rewritten 0..n-1 in one transaction
-- from one authoritative list, so a sequence cannot drift into duplicates after a few reorders.
-- Scoped to (store_id, category_id) because that is exactly one block on the menu: the same section
-- id cannot belong to two shops, and a product with no section sits in its shop's own last block.
--
-- The backfill is the order the page already draws, so deploying this moves nothing: name, then id
-- for the ties, which is what `Sort.by("name")` gave for everything but the ties it left to the
-- planner. Clamped at SMALLINT's ceiling, which no real block comes near — the page draws 120 items.

ALTER TABLE products ADD COLUMN position SMALLINT NOT NULL DEFAULT 0;

UPDATE products p
   SET position = ranked.rn
  FROM (SELECT id,
               LEAST(ROW_NUMBER() OVER (PARTITION BY store_id, category_id
                                            ORDER BY name, id) - 1,
                     32767) AS rn
          FROM products) ranked
 WHERE p.id = ranked.id
   AND ranked.rn <> 0;

-- What the shop page's shelf query and the builder both read: one block, in its order. The shelf is
-- already narrowed by store_id, so this index earns its keep by handing the sort back sorted rather
-- than by narrowing anything further.
CREATE INDEX idx_products_store_section_position
    ON products (store_id, category_id, position, name);
