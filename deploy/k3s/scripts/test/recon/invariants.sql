\pset footer off
\pset null '(null)'
-- Read-only invariant checks: counts, sums and ids only.
select '== I0 legs by leg/status/direction: leg|status|dir|count|sum';
select leg, status, direction, count(*), sum(amount) from accounting.transactions
 group by 1,2,3 order by 1,2,3;

select '== I1 orders whose legs do not balance (debit-credit), excl remittances and payouts: order|net';
select order_id, sum(case when direction='DEBIT' then amount else -amount end) as net
  from accounting.transactions where leg not in ('CASH_REMITTANCE','PAYOUT')
 group by order_id
having sum(case when direction='DEBIT' then amount else -amount end) <> 0;

select '== I2 collection leg vs orders.total_amount mismatches: order|collected|total';
select t.order_id, t.amount, o.total_amount
  from accounting.transactions t join orders.orders o on o.id = t.order_id
 where t.leg in ('CASH_COLLECTED','CUSTOMER_DEBIT') and t.amount <> o.total_amount;

select '== I2b settled orders with zero total (no collection leg) count';
select count(distinct t.order_id) from accounting.transactions t
 where t.leg not in ('CASH_REMITTANCE','PAYOUT')
   and not exists (select 1 from accounting.transactions c where c.order_id=t.order_id
                   and c.leg in ('CASH_COLLECTED','CUSTOMER_DEBIT'));

select '== I3 delivered orders by settled? payment_method|payment_status|kind|settled|count';
select o.payment_method, o.payment_status, o.kind,
       exists (select 1 from accounting.transactions t where t.order_id = o.id) as settled,
       count(*)
  from orders.orders o where o.status = 'DELIVERED' group by 1,2,3,4 order by 1,2,3,4;

select '== I4 legs on orders that are NOT delivered: status|count';
select o.status, count(distinct o.id) from orders.orders o
 where o.status <> 'DELIVERED'
   and exists (select 1 from accounting.transactions t where t.order_id = o.id)
 group by 1;

select '== I5 cash orders delivered: collected float vs total mismatch count';
select count(*) from orders.orders o join accounting.cash_float f
    on f.order_id = o.id and f.entry_kind = 'COLLECTED' and f.handover_id is null
 where f.amount <> o.total_amount;

select '== I6 float rows by kind/holder: kind|holder|cleared?|count|sum';
select entry_kind, holder_kind, cleared_by is not null, count(*), sum(amount)
  from accounting.cash_float group by 1,2,3 order by 1,2,3;

select '== I7 remittances (rider/provider) whose amount <> cleared rows: id|amount|cleared';
select r.id, r.amount, coalesce(sum(c.amount),0)
  from accounting.cash_float r left join accounting.cash_float c on c.cleared_by = r.id
 where r.entry_kind = 'REMITTED' and r.holder_kind <> 'MERCHANT'
 group by r.id, r.amount having r.amount <> coalesce(sum(c.amount),0);

select '== I8 transfers: amount vs cleared rider rows vs custody copies: id|amount|cleared|copies';
select x.id, x.amount,
       (select coalesce(sum(amount),0) from accounting.cash_float c where c.cleared_by = x.id),
       (select coalesce(sum(amount),0) from accounting.cash_float c where c.handover_id = x.id)
  from accounting.cash_float x where x.entry_kind = 'TRANSFERRED'
   and (x.amount <> (select coalesce(sum(amount),0) from accounting.cash_float c where c.cleared_by = x.id)
     or x.amount <> (select coalesce(sum(amount),0) from accounting.cash_float c where c.handover_id = x.id));

select '== I9 cleared_by pointing at nothing or at a non-clearing row: count';
select count(*) from accounting.cash_float c
 where c.cleared_by is not null
   and not exists (select 1 from accounting.cash_float r where r.id = c.cleared_by
                   and r.entry_kind in ('REMITTED','TRANSFERRED','RETAINED'));

select '== I10 CASH_REMITTANCE legs vs REMITTED float rows: legs|sum|float rows|sum';
select (select count(*) from accounting.transactions where leg='CASH_REMITTANCE'),
       (select coalesce(sum(amount),0) from accounting.transactions where leg='CASH_REMITTANCE'),
       (select count(*) from accounting.cash_float where entry_kind='REMITTED'),
       (select coalesce(sum(amount),0) from accounting.cash_float where entry_kind='REMITTED');

select '== I11 rider JOB_EARNING vs RIDER/PROVIDER credit mismatch: order|fleet|earning|credit';
select r.order_id, r.fleet, r.amount,
       (select sum(t.amount) from accounting.transactions t where t.order_id = r.order_id
          and t.leg = case when r.fleet = 'CARRIER' then 'PROVIDER_CREDIT' else 'RIDER_CREDIT' end)
  from accounting.rider_ledger r where r.entry_type = 'JOB_EARNING'
   and r.amount <> coalesce((select sum(t.amount) from accounting.transactions t where t.order_id = r.order_id
          and t.leg = case when r.fleet = 'CARRIER' then 'PROVIDER_CREDIT' else 'RIDER_CREDIT' end), -1);

select '== I12 points: redemptions with more than one release or release+paid: id|releases|paid';
select redemption_id, sum(case when reason='REDEMPTION_RELEASED' then 1 else 0 end),
       sum(case when reason='REDEMPTION_PAID' then 1 else 0 end)
  from accounting.points_ledger where redemption_id is not null group by 1
having sum(case when reason='REDEMPTION_RELEASED' then 1 else 0 end) > 1
    or (sum(case when reason='REDEMPTION_RELEASED' then 1 else 0 end) > 0
        and sum(case when reason='REDEMPTION_PAID' then 1 else 0 end) > 0);

select '== I13 negative points balances: kind|count';
select owner_kind, count(*) from (select owner_kind, owner_ref, sum(points) s
  from accounting.points_ledger group by 1,2) b where s < 0 group by 1;

select '== I14 rider cash-outs by status: status|count|sum';
select status, count(*), sum(amount) from accounting.rider_cash_out group by 1;

select '== I15 orders status summary: status|payment_method|count|sum(total)';
select status, payment_method, count(*), sum(total_amount) from orders.orders group by 1,2 order by 1,2;

select '== I16 total = subtotal + fee(charged) + express - discount + wrap violations: count';
select count(*) from orders.orders
 where total_amount <> subtotal + case when delivery_fee_waived then 0 else coalesce(delivery_fee,0) end
       + coalesce(express_surcharge,0) - coalesce(discount_amount,0) + coalesce(gift_wrap_fee,0);

select '== I17 checkouts: checkout|orders|size';
select checkout_id, count(*), max(checkout_size) from orders.orders where checkout_id is not null
 group by 1 having count(*) <> max(checkout_size);

select '== I18 platform_revenue_ledger columns';
select column_name || ':' || data_type from information_schema.columns
 where table_schema = 'orders' and table_name = 'platform_revenue_ledger' order by ordinal_position;
