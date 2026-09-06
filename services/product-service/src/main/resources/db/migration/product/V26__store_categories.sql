-- Merchant-owned catalogue sections.
--
-- Until now every category was platform taxonomy, created only by BACKOFFICE. The merchant suite's
-- Categories screen lets a shop author its own sections ("Lebanese Specialties") and drag them into
-- the order the customer app shows. Those rows carry a store_id; the platform's own rows keep
-- store_id NULL and are untouched.
--
-- Load-bearing companion change in the same release: GET /api/categories must select only the
-- platform rows (store_id IS NULL), or the first merchant-authored section shows up in every
-- client's vertical picker.

ALTER TABLE categories
    ADD COLUMN store_id uuid NULL REFERENCES stores (id) ON DELETE CASCADE,
    ADD COLUMN position smallint NOT NULL DEFAULT 0,
    ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

-- Uniqueness becomes per owner. The old constraint was global on (name, parent_id), which would
-- stop two different shops each having a "Drinks" section.
ALTER TABLE categories DROP CONSTRAINT uq_category_name_parent;

-- COALESCE rather than NULLS NOT DISTINCT: with three nullable columns the NULL semantics stop
-- being obvious to read, and a sentinel makes "no parent" and "no store" compare as ordinary
-- values. The sentinel is the nil UUID, which is not a legal id for any row.
CREATE UNIQUE INDEX uq_category_name_owner ON categories (
    name,
    COALESCE(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    COALESCE(store_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

-- The merchant Categories screen reads exactly this: one store's sections in display order.
CREATE INDEX idx_categories_store_position ON categories (store_id, position) WHERE store_id IS NOT NULL;
-- The customer app's vertical picker reads exactly this: platform taxonomy only.
CREATE INDEX idx_categories_platform ON categories (parent_id) WHERE store_id IS NULL;

CREATE TRIGGER trg_categories_updated_at BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
