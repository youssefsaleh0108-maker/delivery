-- Product options: the "Choose Size: Medium (30 Cm)" line on a receipt.
--
-- Until now a product was one name and one price, so a pizzeria selling three sizes had to create
-- three products. That pollutes search, splits Buy Again across near-duplicates, and gives the
-- customer no way to say "extra cheese". This is the model that lets one product be configured at
-- the moment it is added to a basket.
--
-- Two tables rather than a jsonb blob on the product: options are selected, priced and reported on
-- individually, and a price delta buried in a document cannot be summed, indexed or audited.

CREATE TABLE product_option_groups (
    id          uuid         PRIMARY KEY,
    product_id  uuid         NOT NULL REFERENCES products (id) ON DELETE CASCADE,
    name        varchar(120) NOT NULL,

    -- How many of this group's options may be taken. min_select = 0 makes the group optional;
    -- min_select >= 1 makes it required, which is what forces "Choose Size" before add-to-cart.
    -- Expressing it as a range rather than a required/multi pair of booleans covers "pick exactly
    -- one", "pick up to three toppings" and "pick at least two sides" with the same two columns.
    min_select  smallint     NOT NULL DEFAULT 0,
    max_select  smallint     NOT NULL DEFAULT 1,

    -- Display order within the product. Not alphabetical: "Size" belongs above "Extras".
    position    smallint     NOT NULL DEFAULT 0,
    created_at  timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_option_group_select CHECK (min_select >= 0 AND max_select >= 1
                                              AND max_select >= min_select)
);

CREATE INDEX idx_option_groups_product ON product_option_groups (product_id, position);

CREATE TABLE product_options (
    id             uuid           PRIMARY KEY,
    group_id       uuid           NOT NULL REFERENCES product_option_groups (id) ON DELETE CASCADE,
    name           varchar(120)   NOT NULL,

    -- Added to the product's base price when chosen. Signed on purpose: "Small" can be -1.00 as
    -- readily as "Large" is +3.00, and modelling only surcharges would force every menu to price
    -- from its cheapest variant.
    price_delta    numeric(12, 2) NOT NULL DEFAULT 0,

    -- Pre-ticked when the sheet opens. A default on a required single-select group is what makes
    -- "add to basket" possible in one tap for the common case.
    is_default     boolean        NOT NULL DEFAULT false,

    -- Sold out tonight, without deleting it and losing the price and the history.
    available      boolean        NOT NULL DEFAULT true,

    position       smallint       NOT NULL DEFAULT 0,

    CONSTRAINT chk_option_delta_scale CHECK (price_delta > -1000000 AND price_delta < 1000000)
);

CREATE INDEX idx_options_group ON product_options (group_id, position);
