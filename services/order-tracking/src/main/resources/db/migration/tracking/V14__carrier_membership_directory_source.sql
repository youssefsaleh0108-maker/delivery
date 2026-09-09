-- ---------------------------------------------------------------------------------------------
-- A third way to learn who works for a delivery company: ask the service that knows.
--
-- V12 shipped two sources. ORDER_EVENT is an inference drawn from an order that named both a
-- rider and a provider, and it is the only one anything ever wrote. MEMBERSHIP was reserved for a
-- `carrier.member_*` event from Order Manager, and that event was never built.
--
-- The consequence was total and silent: a delivery company's office staff carry no orders, so no
-- order event ever mentions them, so they never got a row — and every endpoint that resolves a
-- caller's fleet from this table answered "You are not a member of any delivery company" to every
-- carrier account on the platform, from provisioning onwards. The fleet roster, a rider's live
-- position and the hours columns were all permanently 403 for the console they exist to serve.
--
-- DIRECTORY is that gap closed with what already exists: Order Manager answers
-- GET /api/delivery-providers/my-company for exactly this caller, and order-tracking now asks it
-- with the caller's own token when it holds no row for them. Authoritative at the moment it was
-- read, which is weaker than an event that also reports departures — so a DIRECTORY row carries a
-- re-validation window rather than standing forever, and a caller Order Manager no longer places
-- in a company has their row deleted. See CarrierScopeResolver.
-- ---------------------------------------------------------------------------------------------

ALTER TABLE carrier_membership DROP CONSTRAINT chk_member_source;

ALTER TABLE carrier_membership ADD CONSTRAINT chk_member_source
    CHECK (source IN ('ORDER_EVENT', 'DIRECTORY', 'MEMBERSHIP'));
