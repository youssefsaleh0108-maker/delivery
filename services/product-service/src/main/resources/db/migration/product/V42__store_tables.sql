-- How many tables a shop has, so it can print a QR code for each of them.
--
-- A code taped to table 7 points at the shop's page carrying `?t=7`, and an order started from it
-- knows which table it came from. The page and the code are already pure functions of the slug; the
-- only thing that is not derivable is how many tables the room holds, and that has to be a property
-- of the shop rather than of the device that printed the sheet: a merchant who reprints one card
-- next month, or does it from the portal instead of the phone, has to get the same twelve codes.
--
-- Zero means "no tables", which is every shop until one says otherwise, and is why the sheet is a
-- thing a shop asks for rather than a thing every shop has. The ceiling is small on purpose — a
-- room with more than a few hundred tables is a typo, and the ceiling is what stops one turning
-- into a print job of thirty thousand cards.

ALTER TABLE stores ADD COLUMN table_count SMALLINT NOT NULL DEFAULT 0;

ALTER TABLE stores ADD CONSTRAINT chk_store_table_count
    CHECK (table_count BETWEEN 0 AND 400);
