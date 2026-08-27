-- What was actually bought together, projected from order.delivered.
--
-- The design has a "People Also Ordered" rail. There are two ways to fill it and only one of them
-- is honest.
--
-- The dishonest one is to show whatever else the shop sells and call it popular. This service
-- already knows a store's shelf, so that rail could have been built in an afternoon — and every
-- number on it would have been made up.
--
-- The honest one needs co-purchase history, and until now this service could not see any: it
-- projects order.delivered into reviewable_orders (V19), which records WHICH order, WHOSE it was
-- and WHICH shop, and deliberately nothing else. The event itself has always carried its line
-- items. This table keeps them, so "bought together" can be counted from real delivered baskets.
--
-- Deliberate limits, because they are the difference between a recommendation and a fabrication:
--
--   * Only DELIVERED orders count. A placed order can still be cancelled, and a cancelled basket is
--     not evidence of anything.
--   * There is no backfill and there cannot be one. This service physically cannot read the orders
--     schema — that is the whole point of schema-per-service — so the table starts empty and fills
--     from the moment it is deployed. Until it has data the cross-sell endpoint says so, in the
--     response, per item.
--   * No customer id. Counting baskets needs only the basket. Copying the buyer here would mean
--     holding a second, unowned record of who bought what for a rail that never looks at it.
CREATE TABLE delivered_order_lines (
    -- The basket. This is the grouping key the whole feature turns on: two products are "bought
    -- together" when they share one of these.
    order_id     uuid        NOT NULL,
    product_id   uuid        NOT NULL,

    -- Denormalised from the event so the co-occurrence query can be scoped to one shop without
    -- joining products. It also survives a product being archived and re-homed, which the join
    -- would not.
    store_id     uuid        NOT NULL,

    qty          integer     NOT NULL,
    delivered_at timestamptz NOT NULL,

    -- (order_id, product_id) rather than a surrogate id, for the same reason reviewable_orders is
    -- keyed on the order: the bus is at-least-once, and a redelivered order.delivered must rewrite
    -- the rows it already wrote instead of double-counting the basket it describes.
    PRIMARY KEY (order_id, product_id),

    CONSTRAINT chk_delivered_line_qty CHECK (qty > 0)
);

-- "Which baskets contained this product" — the outer side of the co-occurrence self-join, and the
-- one access path the primary key cannot serve, since product_id does not lead it.
--
-- The inner side ("what else was in those baskets") needs no index of its own: the primary key is a
-- btree on (order_id, product_id), and a lookup by order_id alone is a prefix scan of it.
CREATE INDEX idx_delivered_lines_product ON delivered_order_lines (product_id);
