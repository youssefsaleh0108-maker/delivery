-- Which orders may be reviewed, projected from order.delivered.
--
-- Reviews were previously accepted on the caller's word alone. This service cannot see the orders
-- schema, so `rate` checked that the store existed and nothing else — not that the order existed,
-- not that it belonged to the customer rating it, and not that it was ever delivered. Anyone holding
-- a token could invent a UUID and post a five-star review of their own shop, or a one-star review of
-- a competitor's, as often as they liked. Ratings drive the storefront ranking, so that is not
-- cosmetic.
--
-- A projection rather than a synchronous call to order-manager: the check runs on the review write
-- path, and making that path depend on another service being up would take reviews down whenever
-- order-manager restarted, to verify a fact that does not change after delivery.

CREATE TABLE IF NOT EXISTS reviewable_orders (
    order_id     uuid        PRIMARY KEY,
    store_id     uuid        NOT NULL,
    customer_id  varchar(64) NOT NULL,
    delivered_at timestamptz NOT NULL,
    recorded_at  timestamptz NOT NULL DEFAULT now()
);

-- "What has this customer bought that they have not yet rated" — the app's prompt-to-review query.
CREATE INDEX IF NOT EXISTS idx_reviewable_orders_customer
    ON reviewable_orders (customer_id, delivered_at DESC);
