-- The services marketplace, slice 11: back office takes a service offer down with a reason, and restores it.
--
-- Any provider can publish anything, and the catalogue cannot judge whether an offer belongs on YouDrop.
-- Back office can, after a complaint or a review. Taking an offer down has to be:
--   immediate    gone for every customer at once;
--   sticky       its provider cannot simply publish or resume it again;
--   explained    its provider reads why;
--   accountable  who took it down, when and why, and who put it back, is on record.
--
-- Immediate: a taken-down offer is ARCHIVED. Every customer read already asks for status = 'ACTIVE' (the
-- services search, a shop's shelf, the catalogue, a product read by anyone but its owner, and through
-- that read its options and its price), and order-manager refuses a product that is not ACTIVE when an
-- order is placed. Nothing that reads products learns a new status, and neither does an installed app.
--
-- Sticky: the hold is on the product row. Product refuses publish, resume and pause while taken_down_at
-- is set, and only a restore clears it. chk_product_takedown keeps the three columns together and the
-- offer archived while they are set.
--
-- A save that read a product before another save changed it is refused (version). Back office's acts lock
-- the row, but a provider's saves and back office's gift-hub switch read without a lock, and every save
-- judges the product's rules on what it read. Writing every column, a provider's save that read an offer
-- just before it was taken down would put back the hold-less row it read. Writing only the columns it
-- changed, two saves from one read leave a row neither of them made: an archive that keeps ACTIVE as the
-- status to restore, a publish that goes live after the last photo was removed, a gift-hub pick left on an
-- archived product. So each save writes only where the row still has the version it read, and moves the
-- version on. The second of two saves from one read matches no row, Hibernate refuses it, and the API
-- answers 409 PRODUCT_CHANGED for its caller to reload.
--
-- Explained: takedown_reason is what the provider reads on their offer, in back office's words.
--
-- Accountable: offer_moderation_actions has one row per act, written in the same transaction as the act.
-- If the row cannot be written, the offer is not taken down or restored. Rows are never updated or
-- deleted.
--
-- Restoring lifts the hold and returns the offer to what it was, with one exception: an offer that was on
-- sale comes back PAUSED. Back office never puts an offer in front of customers itself. Its provider
-- resumes it, and resuming runs the publish rules again, which a photo removed or a pin cleared during
-- the hold may now fail.
--
-- Existing rows need nothing. The hold columns start null, which means "not taken down", and every row
-- passes the CHECK. version starts at 0, where Hibernate starts a product it creates, and a column with a
-- constant default is added without rewriting the table.

ALTER TABLE products
    ADD COLUMN taken_down_at          timestamptz,
    ADD COLUMN takedown_reason        varchar(500),
    ADD COLUMN status_before_takedown varchar(16),
    ADD COLUMN version                bigint NOT NULL DEFAULT 0;

ALTER TABLE products ADD CONSTRAINT chk_product_takedown CHECK (
    (taken_down_at IS NULL AND takedown_reason IS NULL AND status_before_takedown IS NULL)
    OR (taken_down_at IS NOT NULL
        AND takedown_reason IS NOT NULL AND btrim(takedown_reason) <> ''
        AND status = 'ARCHIVED'
        AND status_before_takedown IN ('DRAFT', 'ACTIVE', 'PAUSED', 'ARCHIVED')));

-- Back office's "Taken down" filter reads the held rows only, and a hold is rare.
CREATE INDEX idx_products_taken_down ON products (taken_down_at DESC) WHERE taken_down_at IS NOT NULL;

CREATE TABLE offer_moderation_actions (
    id         uuid         PRIMARY KEY,
    product_id uuid         NOT NULL REFERENCES products (id),
    -- The offer's shop. A product never changes shop, so "everything back office did to this provider's
    -- offers" is one read.
    store_id   uuid         NOT NULL REFERENCES stores (id),
    action     varchar(16)  NOT NULL,
    -- Required for both acts, as for every chat moderation act: the trail says why, not only that.
    reason     varchar(500) NOT NULL,
    -- The staff member's Keycloak sub, from the token. Nothing in a request can name another actor.
    actor_id   varchar(64)  NOT NULL,
    -- The username the token carried, so the history names a person rather than an id. Null when the
    -- token carried none.
    actor_name varchar(255),
    created_at timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT chk_offer_moderation_action CHECK (action IN ('TAKE_DOWN', 'RESTORE')),
    CONSTRAINT chk_offer_moderation_reason CHECK (btrim(reason) <> '')
);

-- An offer's history, newest first; and everything one staff member did.
CREATE INDEX idx_offer_moderation_product ON offer_moderation_actions (product_id, created_at DESC);
CREATE INDEX idx_offer_moderation_actor   ON offer_moderation_actions (actor_id, created_at DESC);
