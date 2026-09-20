-- The checkout map: which checkout an order belongs to, which shop it is from, and when it was
-- collected and finished.
--
-- A multi-shop basket becomes one ordinary order per shop at checkout, linked by a checkout id and
-- nothing else (Order Manager V33 — there is no checkouts table upstream either). The customer's
-- one-map view of such a checkout needs "every order of checkout X, for its customer" answered from
-- this projection, for the same reason V10 built it: a screen that polls must not make Order
-- Manager's availability a dependency of every refresh.
--
-- Everything is nullable, and nothing is backfilled. An order placed alone has no checkout, and an
-- order in flight when this lands fills in on its next event — every order publishes one per status
-- change. An order that finished before this migration never appears on a checkout map, which is
-- only ever opened for a checkout in progress.
--
-- picked_up_at and completed_at come from the event's occurredAt, and the earliest one wins. The
-- numbers on the map's pickup stops are the real order in which a rider collected, so a replayed or
-- late-arriving event must never move them.
ALTER TABLE order_participants
    ADD COLUMN checkout_id  uuid,
    ADD COLUMN store_name   varchar(160),
    ADD COLUMN picked_up_at timestamptz,
    ADD COLUMN completed_at timestamptz;

-- "Every order of this checkout." Partial, because most orders are placed alone and never need it.
CREATE INDEX idx_participants_checkout ON order_participants (checkout_id)
    WHERE checkout_id IS NOT NULL;
