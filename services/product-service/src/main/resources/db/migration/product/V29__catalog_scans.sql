-- ---------------------------------------------------------------------------------------------
-- Merchant Blitz: shelf photos in, a draft catalogue out.
--
-- A merchant photographs their shelves, a vision provider lists what it can see, and the merchant
-- accepts, edits or rejects each line. An accepted line becomes an ordinary DRAFT product in the
-- merchant's own store through the same CatalogService.create every other product goes through —
-- nothing here publishes anything, and nothing here writes to `products` directly.
--
-- Three tables rather than one JSON blob, because each level has its own lifecycle and its own
-- ownership question: a photo is a storage object that must be confirmed before it is trusted, and
-- an item is a decision the merchant makes one line at a time and may come back to.
--
-- Pre-assigned V29 (Merchant Blitz) so parallel product-service work does not collide.
-- ---------------------------------------------------------------------------------------------

CREATE TABLE catalog_scans (
    id uuid PRIMARY KEY,
    -- Keycloak sub of the merchant who owns the scan. Every read and write is keyed on it.
    merchant_id varchar(64) NOT NULL,
    store_id uuid NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    status varchar(16) NOT NULL DEFAULT 'UPLOADING',
    -- Which provider actually produced the items: FAKE results are sample data and the client says
    -- so on screen, so this is recorded per scan rather than inferred from today's configuration.
    provider varchar(16),
    -- A code, not prose: the client words it in the merchant's language.
    failure_code varchar(32),
    -- Every analysis is a paid call once a real provider is on, so retries are counted and capped.
    analysis_attempts smallint NOT NULL DEFAULT 0,
    analysis_started_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_scan_status CHECK (status IN ('UPLOADING','ANALYZING','COMPLETE','FAILED')),
    CONSTRAINT chk_scan_attempts CHECK (analysis_attempts >= 0)
);

-- The daily quota counts exactly this: one merchant's scans over the last day.
CREATE INDEX idx_catalog_scans_merchant_created ON catalog_scans (merchant_id, created_at DESC);

CREATE TABLE catalog_scan_photos (
    id uuid PRIMARY KEY,
    scan_id uuid NOT NULL REFERENCES catalog_scans (id) ON DELETE CASCADE,
    -- The platform-storage file id the presign issued. Unique: one upload belongs to one scan.
    file_id uuid NOT NULL,
    object_key varchar(512) NOT NULL,
    -- PENDING until the merchant confirms the bytes landed; only UPLOADED photos are analysed.
    status varchar(16) NOT NULL DEFAULT 'PENDING',
    position smallint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_scan_photo_file UNIQUE (file_id),
    CONSTRAINT chk_scan_photo_status CHECK (status IN ('PENDING','UPLOADED'))
);
CREATE INDEX idx_catalog_scan_photos_scan ON catalog_scan_photos (scan_id, position);

CREATE TABLE catalog_scan_items (
    id uuid PRIMARY KEY,
    scan_id uuid NOT NULL REFERENCES catalog_scans (id) ON DELETE CASCADE,
    photo_id uuid NOT NULL REFERENCES catalog_scan_photos (id) ON DELETE CASCADE,
    position smallint NOT NULL,
    -- What the provider read, then whatever the merchant corrected it to.
    name varchar(200) NOT NULL,
    brand varchar(120),
    size_label varchar(60),
    -- The section the provider suggested, resolved server-side to one of the store's own sections
    -- or the platform taxonomy. Never an id the provider made up: unmatched suggestions stay null.
    category_id uuid,
    confidence numeric(4,3) NOT NULL,
    -- A GUESS, and named as one everywhere it travels. Never copied into `price` by the server:
    -- the merchant states the price they sell at before a product is created.
    price_guess numeric(12,2),
    price numeric(12,2),
    -- Where on the photo the item sits, as fractions of the photo's width and height. Approximate
    -- by nature; used to place the tag over the photo, never to crop a product image.
    box_left numeric(5,4),
    box_top numeric(5,4),
    box_width numeric(5,4),
    box_height numeric(5,4),
    status varchar(16) NOT NULL DEFAULT 'PENDING',
    -- The DRAFT product an accepted line became.
    product_id uuid,
    decided_at timestamptz,
    CONSTRAINT chk_scan_item_status CHECK (status IN ('PENDING','ACCEPTED','REJECTED')),
    CONSTRAINT chk_scan_item_confidence CHECK (confidence >= 0 AND confidence <= 1),
    CONSTRAINT chk_scan_item_guess CHECK (price_guess IS NULL OR price_guess > 0),
    CONSTRAINT chk_scan_item_price CHECK (price IS NULL OR price > 0),
    -- Accepted is exactly "has a product"; a line cannot claim one without the other.
    CONSTRAINT chk_scan_item_accepted CHECK ((status = 'ACCEPTED') = (product_id IS NOT NULL)),
    CONSTRAINT chk_scan_item_box CHECK (
        (box_left IS NULL AND box_top IS NULL AND box_width IS NULL AND box_height IS NULL)
        OR (box_left >= 0 AND box_top >= 0 AND box_width > 0 AND box_height > 0
            AND box_left + box_width <= 1.0001 AND box_top + box_height <= 1.0001))
);
CREATE INDEX idx_catalog_scan_items_scan ON catalog_scan_items (scan_id, position);

CREATE TRIGGER trg_catalog_scans_updated_at BEFORE UPDATE ON catalog_scans
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
