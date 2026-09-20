\pset footer off
-- The ledger's own answer for each statement, computed independently of the service's Java.
-- psql -v f=<from instant> -v t=<to exclusive instant> -v m=<merchant sub> -v r=<rider sub> -v c=<company id>
select 'merchant|' || (coalesce((select sum(amount) from accounting.transactions
         where counterparty_kind = 'MERCHANT' and counterparty_ref = :'m'
           and leg in ('MERCHANT_CREDIT', 'GIFT_WRAP_CREDIT')
           and created_at >= :'f'::timestamptz and created_at < :'t'::timestamptz), 0))::numeric(12,2);
select 'rider|' || (coalesce((select sum(amount) from accounting.rider_ledger
         where rider_ref = :'r' and payable_by = 'PLATFORM'
           and earned_at >= :'f'::timestamptz and earned_at < :'t'::timestamptz), 0)
     + coalesce((select sum(amount) from accounting.cash_float where holder_ref = :'r' and holder_kind = 'RIDER'
           and entry_kind in ('REMITTED', 'TRANSFERRED')
           and created_at >= :'f'::timestamptz and created_at < :'t'::timestamptz), 0)
     - coalesce((select sum(amount) from accounting.cash_float where holder_ref = :'r' and holder_kind = 'RIDER'
           and entry_kind = 'COLLECTED'
           and created_at >= :'f'::timestamptz and created_at < :'t'::timestamptz), 0))::numeric(12,2);
select 'carrier|' || (coalesce((select sum(amount) from accounting.transactions
         where counterparty_kind = 'CARRIER' and counterparty_ref = :'c' and leg = 'PROVIDER_CREDIT'
           and created_at >= :'f'::timestamptz and created_at < :'t'::timestamptz), 0)
     + coalesce((select sum(amount) from accounting.cash_float where holder_ref = :'c' and holder_kind = 'PROVIDER'
           and entry_kind = 'REMITTED' and created_at >= :'f'::timestamptz and created_at < :'t'::timestamptz), 0)
     - coalesce((select sum(amount) from accounting.cash_float where holder_ref = :'c' and holder_kind = 'PROVIDER'
           and entry_kind = 'COLLECTED' and handover_id is not null
           and created_at >= :'f'::timestamptz and created_at < :'t'::timestamptz), 0))::numeric(12,2);
-- Commission earned, less what the platform gave away (PLATFORM_SUBSIDY), absorbed on an order
-- closed after pickup (PLATFORM_LOSS, RECON-10) and paid out in redemptions and cash-outs (PAYOUT,
-- RECON-11) - which is what the platform's statement now adds up.
select 'platform|' || (coalesce((select sum(case when leg = 'PLATFORM_COMMISSION' then -amount else amount end)
         from accounting.transactions
        where leg in ('PLATFORM_COMMISSION', 'PLATFORM_SUBSIDY', 'PLATFORM_LOSS', 'PAYOUT')
           and created_at >= :'f'::timestamptz and created_at < :'t'::timestamptz), 0))::numeric(12,2);
select 'merchant goods sold (orders.subtotal of settled orders)|' || coalesce(sum(o.subtotal), 0)
  from orders.orders o where exists (select 1 from accounting.transactions t where t.order_id = o.id
       and t.leg = 'MERCHANT_CREDIT' and t.counterparty_ref = :'m'
       and t.created_at >= :'f'::timestamptz and t.created_at < :'t'::timestamptz);
select 'merchant commission actually charged|' || coalesce(sum(o.subtotal - t.amount), 0)
  from orders.orders o join accounting.transactions t on t.order_id = o.id and t.leg = 'MERCHANT_CREDIT'
 where t.counterparty_ref = :'m' and t.created_at >= :'f'::timestamptz and t.created_at < :'t'::timestamptz;
select 'carrier withRiders now|' || coalesce(sum(amount), 0) from accounting.cash_float
 where carrier_ref = :'c' and holder_kind = 'RIDER' and entry_kind = 'COLLECTED' and cleared_by is null;
select 'carrier held now|' || coalesce(sum(amount), 0) from accounting.cash_float
 where holder_ref = :'c' and holder_kind = 'PROVIDER' and entry_kind = 'COLLECTED' and cleared_by is null;
select 'merchant delivered orders (Beirut days) and ledger (UTC days) around midnight|'
       || count(*) filter (where (o.delivered_at at time zone 'Asia/Beirut')::date <> (o.delivered_at at time zone 'UTC')::date)
       || ' of ' || count(*) || ' delivered orders fall on a different calendar day in Beirut than in UTC'
  from orders.orders o where o.status = 'DELIVERED';
