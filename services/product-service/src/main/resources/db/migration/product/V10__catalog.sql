-- Product Service catalog tables (Section 4).
--
-- VERSION NUMBERING: the shared migrations from the platform-* libraries occupy V1 (outbox_event)
-- and V2 (file_metadata), and Flyway merges all configured locations into one ordered timeline.
-- Service-owned migrations therefore start at V10, leaving room for shared migrations to be added
-- later without renumbering anything a service already applied.

CREATE TABLE categories (
    id         uuid         PRIMARY KEY,
    name       varchar(128) NOT NULL,
    -- Self-referencing tree. ON DELETE RESTRICT: removing a category with children would silently
    -- orphan an entire branch of the catalog.
    parent_id  uuid         REFERENCES categories (id) ON DELETE RESTRICT,
    created_at timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_category_name_parent UNIQUE NULLS NOT DISTINCT (name, parent_id)
);

CREATE INDEX idx_categories_parent ON categories (parent_id);

CREATE TABLE products (
    id          uuid           PRIMARY KEY,
    -- The merchant's Keycloak `sub`. Every write is checked against the caller's own sub, so this
    -- is the column that makes "a merchant may only edit their own products" enforceable.
    merchant_id varchar(64)    NOT NULL,
    name        varchar(200)   NOT NULL,
    description text,
    price       numeric(12, 2) NOT NULL,
    category_id uuid           REFERENCES categories (id) ON DELETE RESTRICT,
    -- Object keys in the product-images bucket, in display order. Section 4 specifies jsonb here
    -- rather than a child table; the list is short, always read whole, and never queried into.
    image_refs  jsonb          NOT NULL DEFAULT '[]'::jsonb,
    status      varchar(16)    NOT NULL DEFAULT 'DRAFT',
    created_at  timestamptz    NOT NULL DEFAULT now(),
    updated_at  timestamptz    NOT NULL DEFAULT now(),
    CONSTRAINT chk_product_price_positive CHECK (price > 0),
    CONSTRAINT chk_product_status CHECK (status IN ('DRAFT', 'ACTIVE', 'ARCHIVED'))
);

-- The Merchant Portal's main list: a merchant's own products, newest first.
CREATE INDEX idx_products_merchant ON products (merchant_id, created_at DESC);

-- The customer-facing catalog only ever shows ACTIVE products, so the index excludes the rest.
CREATE INDEX idx_products_active_category ON products (category_id, created_at DESC)
    WHERE status = 'ACTIVE';

-- Catalog search. pg_trgm was enabled in Phase 0 for exactly this.
-- The operator class MUST be schema-qualified: the extension lives in `public`, but Flyway runs
-- with the search path set to this service's own schema, so a bare `gin_trgm_ops` fails with
-- "operator class does not exist for access method gin".
CREATE INDEX idx_products_name_trgm ON products USING gin (name public.gin_trgm_ops);

-- Keeps updated_at honest without every writer having to remember to set it.
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- A small starter tree so the Merchant Portal has something to select on first run. Fixed UUIDs so
-- the migration is idempotent across environments and demo data can reference them.
INSERT INTO categories (id, name, parent_id) VALUES
    ('11111111-1111-4111-8111-111111111111', 'Food',        NULL),
    ('22222222-2222-4222-8222-222222222222', 'Groceries',   NULL),
    ('33333333-3333-4333-8333-333333333333', 'Pharmacy',    NULL),
    ('44444444-4444-4444-8444-444444444444', 'Restaurants', '11111111-1111-4111-8111-111111111111'),
    ('55555555-5555-4555-8555-555555555555', 'Bakery',      '11111111-1111-4111-8111-111111111111'),
    ('66666666-6666-4666-8666-666666666666', 'Fresh Produce', '22222222-2222-4222-8222-222222222222');
