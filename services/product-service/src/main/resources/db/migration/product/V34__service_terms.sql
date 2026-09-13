-- The services marketplace, slice 2: what a service offer promises, beside the product it describes.
--
-- A service offer is a product row. The USD price, the presigned photos with thumbnails, the publish
-- rule and the option groups ("Paper type") all come from there, and the catalogue prices an order line
-- for a service exactly as it prices a basket line. What a product cannot say is how the work is sold
-- and handed over. That is this table: one row per offer, keyed by the product.
--
--   pricing_type        FIXED     one price for one pack of unit_size units ("500 cards, $15.00")
--                       PER_UNIT  one price for one unit ("$8.00 per sqm"), so a pack is one unit
--                       FROM      a starting price that required options add to ("From $15.00")
--                       Quote-on-request is deliberately absent: an order is priced by the catalogue
--                       when it is placed, and a price nobody has set cannot be.
--   unit_label, unit_size
--                       one step of the quantity stepper: 500 "cards". An order line counts packs,
--                       1 to 99 of them, and products.price is the price of one pack. A per-card
--                       price such as $0.025 would not fit numeric(12,2), which is why it is per pack.
--   turnaround_*_hours  how long the provider needs once they accept. The customer's estimated
--                       completion is the accept time plus the maximum (owner default 7).
--   fulfilment_modes    PICKUP, DELIVERY or BOTH. A delivery offer is published only by a shop with
--                       delivery areas or a pin (CatalogService), which a CHECK here cannot see.
--   attachment_policy   whether the customer sends a file, such as a design to print.
--   instructions_prompt the question put to the customer beside the order's instructions.
--
-- No service category. An offer is filed under its shop's (stores.service_category, V33), so closing a
-- category hides its shops and their offers together, and no offer is listed under a category its shop
-- is not in. No price in any currency either: products.price is the price, in USD, and the LBP figure
-- the apps show is a conversion at the platform rate, never a second price somebody set.
--
-- The CHECKs hold what no offer can ever be. Policy that may move (the longest turnaround worth
-- promising, what a label must say) is in ServiceTerms, where changing it needs no migration.
--
-- Existing rows need nothing: every product so far is a goods product, and goods have no terms. The
-- cascade only keeps the pair together should a product ever be deleted; products are archived.

CREATE TABLE service_terms (
    product_id           uuid        PRIMARY KEY REFERENCES products (id) ON DELETE CASCADE,
    pricing_type         varchar(16) NOT NULL,
    unit_label           varchar(40),
    unit_size            integer     NOT NULL DEFAULT 1,
    turnaround_min_hours integer     NOT NULL,
    turnaround_max_hours integer     NOT NULL,
    fulfilment_modes     varchar(16) NOT NULL,
    attachment_policy    varchar(16) NOT NULL DEFAULT 'NONE',
    instructions_prompt  varchar(160),

    CONSTRAINT chk_service_terms_pricing_type
        CHECK (pricing_type IN ('FIXED', 'PER_UNIT', 'FROM')),
    CONSTRAINT chk_service_terms_unit_size
        CHECK (unit_size BETWEEN 1 AND 100000),
    -- Order lines are priced at products.price per pack, so a price per unit must be a pack of one.
    CONSTRAINT chk_service_terms_per_unit_is_one_unit
        CHECK (pricing_type <> 'PER_UNIT' OR unit_size = 1),
    -- Work that is ready before it is started is not a turnaround.
    CONSTRAINT chk_service_terms_turnaround
        CHECK (turnaround_min_hours >= 0
            AND turnaround_max_hours >= turnaround_min_hours
            AND turnaround_max_hours >= 1),
    CONSTRAINT chk_service_terms_fulfilment
        CHECK (fulfilment_modes IN ('PICKUP', 'DELIVERY', 'BOTH')),
    CONSTRAINT chk_service_terms_attachment
        CHECK (attachment_policy IN ('NONE', 'OPTIONAL', 'REQUIRED'))
);
