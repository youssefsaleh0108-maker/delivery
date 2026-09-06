-- SKU, barcode and the stock projection that the merchant suite's inventory screens need.
--
-- All three columns are additive and safe against the rows already live in dev and qa: existing
-- products get sku=NULL, barcode=NULL, in_stock=true, which leaves them untracked (no stock_levels
-- row in inventory-service) and therefore unchanged in every storefront query.

-- A merchant's own code for the item. Unique per store only where set: most catalogues are
-- migrated without one, and NULLs must not collide.
ALTER TABLE products ADD COLUMN sku varchar(64);
CREATE UNIQUE INDEX uq_products_store_sku ON products (store_id, sku) WHERE sku IS NOT NULL;

-- Scanned at the till. Deliberately NOT unique: the same EAN legitimately appears in two stores,
-- and a merchant may key one barcode to several pack sizes.
ALTER TABLE products ADD COLUMN barcode varchar(32);
CREATE INDEX idx_products_store_barcode ON products (store_id, barcode) WHERE barcode IS NOT NULL;

-- Projection of inventory-service's inventory.level_changed. TRUE for every existing row so that
-- nothing disappears from a storefront the moment this ships; inventory-service only ever flips it
-- for products a merchant has explicitly chosen to track.
ALTER TABLE products ADD COLUMN in_stock boolean NOT NULL DEFAULT true;

-- The storefront's hot path is "active products in this store, newest first, that can be bought".
CREATE INDEX idx_products_store_active_instock ON products (store_id, category_id, created_at DESC)
    WHERE status = 'ACTIVE' AND in_stock;
