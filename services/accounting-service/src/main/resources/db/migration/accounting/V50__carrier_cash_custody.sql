-- Delivery companies hold their riders' cash.
--
-- THE DECISION THIS ENCODES. Until now every note taken at the door was an obligation from the rider
-- to the PLATFORM, whoever the rider rode for, and only somebody at the platform could record it
-- being handed over. The owner has decided otherwise for delivery companies: a carrier's rider owes
-- the door cash to their COMPANY, the company records the hand-over at its own hub, and the company
-- then owes the platform and settles with it. The platform's own riders are unchanged.
--
-- So custody has three stages for a carrier job, and one table records all of them:
--
--   COLLECTED   (holder RIDER,    carrier_ref = company)  notes taken at the door
--   TRANSFERRED (holder RIDER,    carrier_ref = company)  the rider handed them to the company;
--                                                          clears the rider's COLLECTED rows
--   COLLECTED   (holder PROVIDER, handover_id = transfer)  the same orders, now in the company's
--                                                          custody, one row per order
--   REMITTED    (holder PROVIDER)                         the company paid the platform; clears those
--
-- A hand-over therefore moves custody without creating or destroying a cent: the rows it clears and
-- the rows it creates are the same orders at the same amounts, written in one transaction. Money
-- only reaches the platform — and a CASH_REMITTANCE posting is only written — when the company
-- pays, exactly as it is when one of the platform's own riders banks their takings.
--
-- WHY COPIES AND NOT ONE ROW PER HAND-OVER. The company's custody is per ORDER so everything that
-- already reads the float keeps working unchanged: "what is still outstanding" is still the
-- COLLECTED rows nobody has cleared (the rider's are cleared, the company's copies are not, so the
-- platform-wide total does not move), the Back Office list still shows who holds how much across
-- how many orders, and the existing remittance clears a company exactly as it clears a rider.

ALTER TABLE cash_float
    -- The delivery company the job was carried for, decided when the cash was collected and never
    -- re-read from where the rider rides today: a rider who changes fleet leaves last week's cash
    -- with last week's company. Null on the platform's own fleet, which is what keeps that path
    -- byte-for-byte what it was.
    ADD COLUMN carrier_ref  varchar(64),
    -- On a company's custody copy, the TRANSFERRED row that put it there. What tells a copy apart
    -- from notes taken at the door, so a report that counts door cash does not count it twice.
    ADD COLUMN handover_id  uuid,
    -- Who recorded a hand-over or a remittance: a Keycloak subject, never a name typed in.
    ADD COLUMN recorded_by  varchar(64),
    -- How the money moved. Recorded, never acted on — nothing here moves money itself.
    ADD COLUMN method       varchar(24),
    ADD COLUMN note         text,
    -- The client's idempotency key. A double-clicked "Confirm" must record one hand-over, not two.
    ADD COLUMN request_key  varchar(64);

ALTER TABLE cash_float
    DROP CONSTRAINT chk_float_kind;

ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_kind
        CHECK (entry_kind IN ('COLLECTED', 'REMITTED', 'TRANSFERRED', 'WRITTEN_OFF'));

-- One collection per order PER HOLDER KIND. The rider's row and the company's copy of the same order
-- are both COLLECTED, and the old (order_id, entry_kind) key would refuse the copy. Still at most one
-- of each: the bus cannot book the rider's cash twice, and a hand-over cannot copy an order twice.
ALTER TABLE cash_float
    DROP CONSTRAINT uq_float_order;

ALTER TABLE cash_float
    ADD CONSTRAINT uq_float_order UNIQUE (order_id, entry_kind, holder_kind);

ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_method
        CHECK (method IS NULL OR method IN ('CASH', 'BANK_DEPOSIT', 'WALLET'));

-- Only a company's custody copy points at a hand-over.
ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_custody
        CHECK (handover_id IS NULL OR (entry_kind = 'COLLECTED' AND holder_kind = 'PROVIDER'));

-- A hand-over always names the company that took the cash.
ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_transfer_carrier
        CHECK (entry_kind <> 'TRANSFERRED' OR carrier_ref IS NOT NULL);

-- A company's own rows always carry its own id as the carrier, so "everything this company is
-- answerable for" is one column to filter on rather than two that could disagree.
ALTER TABLE cash_float
    ADD CONSTRAINT chk_float_provider_carrier
        CHECK (holder_kind <> 'PROVIDER' OR carrier_ref = holder_ref);

CREATE UNIQUE INDEX uq_float_request_key
    ON cash_float (request_key)
    WHERE request_key IS NOT NULL;

-- The carrier's reconciliation page: what each of this company's riders is still holding.
CREATE INDEX idx_float_carrier_outstanding
    ON cash_float (carrier_ref, holder_ref)
    WHERE entry_kind = 'COLLECTED' AND cleared_by IS NULL;

-- The same page's day-scoped figures and its hand-over history.
CREATE INDEX idx_float_carrier_created
    ON cash_float (carrier_ref, entry_kind, created_at DESC)
    WHERE carrier_ref IS NOT NULL;

-- BACKFILL: which company each historical collection was carried for.
--
-- From the order's own PROVIDER_CREDIT leg, which settlement attributes to the company (V47) — the
-- same fact the new write path records, read from where it was already written. Only rider door
-- collections are touched; nothing is cleared or re-owned, so every outstanding balance, statement
-- and float total reads exactly as it did before this ran.
UPDATE cash_float f
   SET carrier_ref = t.counterparty_ref
  FROM transactions t
 WHERE t.order_id = f.order_id
   AND t.leg = 'PROVIDER_CREDIT'
   AND t.counterparty_kind = 'CARRIER'
   AND f.entry_kind = 'COLLECTED'
   AND f.holder_kind = 'RIDER'
   AND f.carrier_ref IS NULL;

-- A second source for orders settled before V47 attributed legs: the rider's own job row names the
-- company (V46). Both sources need a delivery fee above zero, because a zero earning writes neither
-- a PROVIDER_CREDIT leg nor a rider row — so a fee-less carrier order from before this migration
-- stays the platform's to collect, as it always was. That gap is closed, not growing: every cash
-- order settled from now on records its company at collection.
UPDATE cash_float f
   SET carrier_ref = r.carrier_ref
  FROM rider_ledger r
 WHERE r.order_id = f.order_id
   AND r.rider_ref = f.holder_ref
   AND r.entry_type = 'JOB_EARNING'
   AND r.fleet = 'CARRIER'
   AND r.carrier_ref IS NOT NULL
   AND f.entry_kind = 'COLLECTED'
   AND f.holder_kind = 'RIDER'
   AND f.carrier_ref IS NULL;
