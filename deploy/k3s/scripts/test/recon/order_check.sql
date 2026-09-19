\pset footer off
\pset null -
-- Invariants for ONE settled order (psql -v oid=<uuid>). Counts, sums and ids only.
select 'order|' || o.status || '|kind=' || o.kind || '|pay=' || o.payment_method || '/' || o.payment_status
       || '|subtotal=' || o.subtotal || '|fee=' || o.delivery_fee || '|feeWaived=' || o.delivery_fee_waived
       || '|merchWaived=' || o.merchant_fee_waived || '|carrWaived=' || o.carrier_fee_waived
       || '|express=' || o.express_surcharge || '|discount=' || o.discount_amount
       || '|wrap=' || o.gift_wrap_fee || '|total=' || o.total_amount
       || '|external=' || (o.delivery_provider_account is not null) || '|checkout=' || coalesce(o.checkout_id::text, '-')
  from orders.orders o where o.id = :'oid';
select 'leg|' || leg || '|' || direction || '|' || amount || '|' || status || '|' || coalesce(counterparty_kind, '-')
  from accounting.transactions where order_id = :'oid' order by leg;
select 'I1 debit=credit|' || case when coalesce(sum(case when direction = 'DEBIT' then amount else -amount end), 0) = 0
       then 'PASS' else 'FAIL net=' || sum(case when direction = 'DEBIT' then amount else -amount end) end
  from accounting.transactions where order_id = :'oid';
select 'I2 collected=total|' || case
         when o.total_amount = 0 and not exists (select 1 from accounting.transactions t where t.order_id = o.id
              and t.leg in ('CASH_COLLECTED', 'CUSTOMER_DEBIT')) then 'PASS (zero total, no collection)'
         when exists (select 1 from accounting.transactions t where t.order_id = o.id
              and t.leg in ('CASH_COLLECTED', 'CUSTOMER_DEBIT') and t.amount = o.total_amount) then 'PASS'
         else 'FAIL' end
  from orders.orders o where o.id = :'oid';
select 'I3 merchant credit|' || case
         when o.merchant_fee_waived and coalesce(t.amount, 0) = o.subtotal then 'PASS (waived: full subtotal)'
         when not o.merchant_fee_waived and coalesce(t.amount, 0) = o.subtotal - round(o.subtotal * 0.125, 2) then 'PASS'
         else 'FAIL credit=' || coalesce(t.amount::text, 'none') || ' subtotal=' || o.subtotal end
  from orders.orders o left join accounting.transactions t on t.order_id = o.id and t.leg = 'MERCHANT_CREDIT'
 where o.id = :'oid' and o.kind in ('CATALOG', 'SERVICE');
select 'I4 carrier/rider credit|' || case
         when o.delivery_fee = 0 and not exists (select 1 from accounting.transactions x where x.order_id = o.id
                                                  and x.leg in ('PROVIDER_CREDIT', 'RIDER_CREDIT')) then 'PASS (no fee, no credit)'
         when exists (select 1 from accounting.transactions x where x.order_id = o.id
                      and x.leg in ('PROVIDER_CREDIT', 'RIDER_CREDIT')
                      and x.amount = o.delivery_fee - case when o.carrier_fee_waived then 0 else round(o.delivery_fee * 0.10, 2) end)
              then 'PASS'
         else 'FAIL' end
  from orders.orders o where o.id = :'oid' and o.kind = 'CATALOG';
select 'I5 float|' || entry_kind || '|' || holder_kind || '|' || amount || '|carrier=' || coalesce(carrier_ref, '-')
       || '|cleared=' || (cleared_by is not null)
  from accounting.cash_float where order_id = :'oid' order by created_at;
select 'I6 rider ledger|' || entry_type || '|' || amount || '|' || payable_by || '|' || fleet
  from accounting.rider_ledger where order_id = :'oid';
select 'I7 points|' || owner_kind || '|' || points from accounting.points_ledger where order_id = :'oid' order by owner_kind;
select 'I8 promo redemption|amount=' || amount from orders.promo_redemptions where order_id = :'oid';
select 'I9 revenue ledger|earned=' || would_have_earned || '|givenCustomer=' || given_customer
       || '|givenMerchant=' || given_merchant || '|givenCarrier=' || given_carrier
  from orders.platform_revenue_ledger where order_id = :'oid';
select 'I10 outbox|' || event_type || '|' || status from orders.outbox_event
 where aggregate_id = :'oid' and event_type in ('order.delivered', 'order.cancelled') order by created_at;
