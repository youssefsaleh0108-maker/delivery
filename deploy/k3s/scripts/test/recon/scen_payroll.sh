#!/bin/sh
# P: the demo carrier's first pay run, 1-15 September (Asia/Beirut), 1.00 a delivery, against the
# orders and the ledger. Prints ids, counts and amounts only.
. /dev/shm/recon/lib.sh
CARR=$(tok carrier)
COMPANY=5857ac51-ef54-4c80-b50c-750998e50986

echo "=== P0. the counts the run must match"
printf '%s\n' "select 'orders delivered by the company, 1-15 Sep Beirut|' || count(*) || '|riders ' || count(distinct rider_id)
  from orders.orders where status = 'DELIVERED' and delivery_provider_id = '$COMPANY'
   and delivered_at >= timestamptz '2026-09-01 00:00 Asia/Beirut' and delivered_at < timestamptz '2026-09-16 00:00 Asia/Beirut';
select 'same, UTC days|' || count(*) from orders.orders where status = 'DELIVERED' and delivery_provider_id = '$COMPANY'
   and delivered_at >= timestamptz '2026-09-01 00:00 UTC' and delivered_at < timestamptz '2026-09-16 00:00 UTC';
select 'ledger job rows for the company, same period|' || count(*) from accounting.rider_ledger
 where carrier_ref = '$COMPANY' and fleet = 'CARRIER' and entry_type = 'JOB_EARNING'
   and earned_at >= timestamptz '2026-09-01 00:00 Asia/Beirut' and earned_at < timestamptz '2026-09-16 00:00 Asia/Beirut';
select 'company cash still with riders, collected before 16 Sep Beirut|' || coalesce(sum(amount), 0) from accounting.cash_float
 where carrier_ref = '$COMPANY' and holder_kind = 'RIDER' and entry_kind = 'COLLECTED' and cleared_by is null
   and created_at < timestamptz '2026-09-16 00:00 Asia/Beirut';" | sql

echo "=== P1. policy from 1 September, semi-monthly, 1.00 a delivery"
c=$(api "$CARR" POST "/api/accounting/carrier/payroll/policy" '{"effectiveFrom":"2026-09-01","payCycle":"SEMI_MONTHLY","perDeliveryRate":1.00}')
note "policy HTTP $c $(err | head -c 160) effectiveFrom=$(j '.policy.effectiveFrom // .effectiveFrom // "-"')"
c=$(api "$CARR" GET "/api/accounting/carrier/payroll/periods"); note "periods HTTP $c: $(j -c '[.periods[]? | "\(.from)..\(.to) over=\(.over) payable=\(.payable)"] | .[0:3]' 2>/dev/null)"

echo "=== P2. run for 1-15 September"
c=$(api "$CARR" POST "/api/accounting/carrier/payroll/runs" '{"periodFrom":"2026-09-01"}')
RUN=$(j '.id // empty'); REV=$(j '.revision')
note "run HTTP $c id=$RUN status=$(j '.status') deliveries=$(j '.deliveries') attendance=$(j '.attendance') revision=$REV $(err | head -c 160)"
[ -n "$RUN" ] || { echo "no run"; exit 0; }
note "totals: $(jq -c '.totals' "$W/body")"
note "payslips: $(j '[.payslips[] | "\(.riderRef[0:8]) deliveries=\(.deliveries) deliveryPay=\(.deliveryPay) gross=\(.gross) deductions=\(.deductions) cashHeld=\(.cashHeld) cashNetted=\(.cashNetted) net=\(.net) status=\(.status)"] | join(" ; ")')"

echo "=== P3. approve, then pay everything against the confirmed total"
c=$(api "$CARR" POST "/api/accounting/carrier/payroll/runs/$RUN/approve" "{\"revision\":$REV,\"acknowledgeMissing\":true}")
note "approve HTTP $c status=$(j '.status') code=$(j '.code // "-"') $(err | head -c 120)"
TOTAL=$(j '.totals.outstanding // .run.totals.outstanding')
c=$(api "$CARR" POST "/api/accounting/carrier/payroll/runs/$RUN/pay" "{\"expectedTotal\":$TOTAL,\"method\":\"BANK_DEPOSIT\",\"reference\":\"recon-payroll\"}")
note "pay all $TOTAL HTTP $c status=$(j '.status') paid=$(j '.totals.paid') outstanding=$(j '.totals.outstanding') $(err | head -c 120)"
c=$(api "$CARR" POST "/api/accounting/carrier/payroll/runs/$RUN/pay" "{\"expectedTotal\":$TOTAL,\"method\":\"BANK_DEPOSIT\",\"reference\":\"recon-payroll\"}")
note "pay all again HTTP $c code=$(j '.code // "-"')"
printf '%s\n' "select 'payslips in the run|' || count(*) || '|' || coalesce(sum(net), 0) || '|' || string_agg(status, ',') from accounting.carrier_payslip where run_id = '$RUN';" | sql
echo "RUN=$RUN" >> /dev/shm/recon/orders.txt
echo "=== P done"
