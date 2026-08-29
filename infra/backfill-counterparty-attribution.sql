-- Attribute the ledger rows written before accounting knew who a leg belonged to.
--
-- Deliberately NOT a Flyway migration. accounting-service's own DB role cannot be assumed to read
-- the orders schema, and a migration that fails on a permission leaves the service unable to start
-- — so this is run once, by hand, by somebody who has access to both schemas. New rows are
-- attributed at settlement and never need this.
--
-- Idempotent: only fills rows that are still NULL, so re-running it is a no-op.
BEGIN;

\echo '--- before ---'
SELECT leg,
       count(*) AS rows,
       count(counterparty_ref) AS attributed
FROM accounting.transactions
GROUP BY leg ORDER BY leg;

-- The merchant is the shop that sold the goods.
UPDATE accounting.transactions t
   SET counterparty_kind = 'MERCHANT',
       counterparty_ref  = o.merchant_id::text
  FROM orders.orders o
 WHERE o.id = t.order_id
   AND t.leg = 'MERCHANT_CREDIT'
   AND t.counterparty_ref IS NULL
   AND o.merchant_id IS NOT NULL;

-- Cash collected is held by the rider who took it, and the rider credit is owed to the same person.
UPDATE accounting.transactions t
   SET counterparty_kind = 'RIDER',
       counterparty_ref  = o.rider_id::text
  FROM orders.orders o
 WHERE o.id = t.order_id
   AND t.leg IN ('CASH_COLLECTED', 'RIDER_CREDIT')
   AND t.counterparty_ref IS NULL
   AND o.rider_id IS NOT NULL;

-- A carrier's leg belongs to the delivery company, not to the rider who carried for them.
UPDATE accounting.transactions t
   SET counterparty_kind = 'CARRIER',
       counterparty_ref  = o.delivery_provider_id::text
  FROM orders.orders o
 WHERE o.id = t.order_id
   AND t.leg = 'PROVIDER_CREDIT'
   AND t.counterparty_ref IS NULL
   AND o.delivery_provider_id IS NOT NULL;

-- The platform's own legs name the platform. No join needed, and no order can change that.
UPDATE accounting.transactions
   SET counterparty_kind = 'PLATFORM',
       counterparty_ref  = 'PLATFORM'
 WHERE leg IN ('PLATFORM_COMMISSION', 'PLATFORM_SUBSIDY')
   AND counterparty_ref IS NULL;

-- CUSTOMER_DEBIT is deliberately left unattributed. chk_txn_counterparty_kind admits only
-- MERCHANT, RIDER, CARRIER and PLATFORM, because a customer is not somebody the platform
-- reconciles WITH — they paid and left. Writing a customer id here would fail the constraint, and
-- rightly: it would put a person who is owed nothing into a statement run.

\echo '--- after ---'
SELECT leg,
       count(*) AS rows,
       count(counterparty_ref) AS attributed,
       count(*) - count(counterparty_ref) AS still_unattributed
FROM accounting.transactions
GROUP BY leg ORDER BY leg;

\echo '--- what each counterparty is now owed, which is the whole point ---'
SELECT counterparty_kind,
       counterparty_ref,
       count(*) AS legs,
       round(sum(CASE WHEN direction = 'CREDIT' THEN amount ELSE -amount END), 2) AS net
FROM accounting.transactions
WHERE counterparty_ref IS NOT NULL
GROUP BY counterparty_kind, counterparty_ref
ORDER BY counterparty_kind, net DESC;

COMMIT;
