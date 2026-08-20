-- Which of the shop's numbers this conversation arrived on.
--
-- Needed the moment replies exist: a shop with a branch line has two numbers, and answering from
-- the wrong one puts the reply in a thread the customer is not looking at. Inbound already knew
-- this and was throwing it away.
ALTER TABLE wa_conversations ADD COLUMN phone_number_id varchar(64);

-- Backfilled for conversations that predate replies, where there is exactly one candidate. A shop
-- with several numbers is left null rather than guessed at: a wrong guess sends the reply to the
-- wrong place, which is worse than the sender falling back to the shop's only other option.
UPDATE wa_conversations c
SET phone_number_id = n.phone_number_id
FROM wa_connected_numbers n
WHERE n.merchant_ref = c.merchant_ref
  AND (SELECT count(*) FROM wa_connected_numbers x WHERE x.merchant_ref = c.merchant_ref) = 1;

-- Nullable on purpose. A conversation whose number was disconnected still has its history, and
-- forcing a value here would mean either deleting that history or inventing a number for it.
