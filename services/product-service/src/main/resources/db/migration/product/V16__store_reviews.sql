-- Reviews, and ratings that mean something.
--
-- `stores.rating` has been a seeded number since V12 — 4.8 from nobody. This is the model behind it.
--
-- Lives in the product schema rather than with orders because a rating is a property of a store,
-- and the storefront reads it on every card. `order_id` is an opaque reference across the service
-- boundary, deliberately without a foreign key: order-manager owns that table and this schema
-- physically cannot see it.

CREATE TABLE store_reviews (
    id          uuid         PRIMARY KEY,
    store_id    uuid         NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    -- The reviewer's Keycloak sub.
    customer_id varchar(64)  NOT NULL,
    -- The order being reviewed. One review per order is the anti-spam rule: you can only rate a
    -- shop as many times as you have actually bought from it.
    order_id    uuid         NOT NULL,

    rating      smallint     NOT NULL,
    comment     text,

    created_at  timestamptz  NOT NULL DEFAULT now(),
    updated_at  timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5),
    -- The constraint that makes the aggregate trustworthy. Enforced here rather than in service
    -- code because two taps racing would otherwise both pass a read-then-write check.
    CONSTRAINT uq_review_per_order UNIQUE (order_id)
);

-- "Reviews for this store, newest first" — the store page's review list.
CREATE INDEX idx_reviews_store ON store_reviews (store_id, created_at DESC);

-- "Have I already reviewed this?" — asked once per order row in the customer's order list.
CREATE INDEX idx_reviews_customer ON store_reviews (customer_id, created_at DESC);

CREATE TRIGGER trg_store_reviews_updated_at
    BEFORE UPDATE ON store_reviews
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- The seeded ratings were never real. Clearing them means every store starts at "New" and earns its
-- score from actual reviews — a 4.8 nobody gave is worse than no number at all, because a customer
-- cannot tell the difference between the two.
UPDATE stores SET rating = NULL, rating_count = 0;
