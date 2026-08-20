-- Vendor delivery receipts (DLRs): what actually reached the handset, as opposed to what the
-- provider accepted from us.
--
-- WHY A SEPARATE AXIS AND NOT NEW `status` VALUES: `status` records OUR side of the exchange —
-- whether the provider took the message off our hands. A DLR records the CARRIER's side, and the
-- two genuinely disagree: a message can be SENT (accepted, billed) and hours later come back
-- UNDELIVERED. Folding delivery into `status` would overwrite the acceptance fact, break the
-- existing sent/failed counts, and make the "what is stuck" index start hiding rows. Keeping them
-- orthogonal means the rate report can say "accepted 100%, delivered 62%", which is the sentence
-- the vendor decision actually turns on.
--
-- NULL delivery_status means "no DLR has arrived", which is NOT the same as "not delivered" and must
-- never be rendered as 0% — the same null-vs-zero rule the acceptance successRate already follows.
-- Most of the world's SMS traffic never produces a DLR at all, so null is the normal case, not an
-- error case.
ALTER TABLE notification_log
    ADD COLUMN delivery_status  varchar(16),
    ADD COLUMN delivered_at     timestamptz,
    ADD COLUMN delivery_detail  text,
    ADD COLUMN dlr_received_at  timestamptz;

-- Deliberately short. Vendors have a dozen intermediate states each ("queued", "sending",
-- "accepted", "buffered"); those are transitions, not outcomes, and storing them would make the
-- report depend on which vendor's vocabulary was in use. Only the two terminal answers are
-- recorded, with the vendor's own wording preserved verbatim in delivery_detail for forensics.
ALTER TABLE notification_log
    ADD CONSTRAINT chk_log_delivery_status
    CHECK (delivery_status IS NULL OR delivery_status IN ('DELIVERED', 'UNDELIVERED'));

-- A DLR identifies its message by the VENDOR's id, not ours — the callback comes from a system that
-- has never seen our notification id. Without this index every incoming receipt is a sequential scan
-- of the whole log, and DLRs arrive at the same rate as sends.
--
-- Partial, because rows that never reached a provider have no provider_message_id and can never be
-- the target of a lookup.
CREATE INDEX idx_notification_log_provider_message_id
    ON notification_log (provider, provider_message_id)
    WHERE provider_message_id IS NOT NULL;

-- The operator's second question, after "what is stuck": what did we pay to send and never arrive.
CREATE INDEX idx_notification_log_undelivered
    ON notification_log (created_at)
    WHERE delivery_status = 'UNDELIVERED';
