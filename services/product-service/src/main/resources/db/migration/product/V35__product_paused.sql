-- The services marketplace, slice 2: a provider can pause an offer, and resume it.
--
-- A print shop whose press is down, or a tailor away for a week, has to stop taking orders for an offer
-- without losing it. Archiving is the wrong tool: it means "no longer sold", it takes a product off the
-- gift hub for good, and it is what the goods apps' availability switch already sends. PAUSED means
-- "not now". The offer keeps its photos, options and terms, and resuming it runs the publish rules again
-- and puts it back as it was.
--
-- A paused offer needs no other change to disappear. Every customer read asks for status = 'ACTIVE'
-- (a shop's shelf, the catalogue, the services search, a product read by anyone but its owner), and
-- order-manager refuses a product that is not ACTIVE when an order is placed.
--
-- Only service offers are paused (CatalogService). Installed goods merchant apps read a status they do
-- not know as DRAFT, so a goods product never takes a value those apps would draw wrongly.
--
-- Every existing row is DRAFT, ACTIVE or ARCHIVED, and all three stay valid.

ALTER TABLE products DROP CONSTRAINT chk_product_status;
ALTER TABLE products ADD CONSTRAINT chk_product_status
    CHECK (status IN ('DRAFT', 'ACTIVE', 'PAUSED', 'ARCHIVED'));
