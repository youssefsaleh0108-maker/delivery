#!/bin/sh
# F: the carrier's hand-over (twice at once), the company paying the platform (twice at once), and
# the platform rider banking their takings. Then the float and ledger invariants.
. /dev/shm/recon/lib.sh
RIDER=$(tok rider); CARR=$(tok carrier); BACK=$(tok backoffice delivery-portal)
RSUB=$(sub_of "$RIDER")
COMPANY=5857ac51-ef54-4c80-b50c-750998e50986

echo "=== F0. what the Back Office list shows for the rider (the figure its Banked button clears)"
c=$(api "$BACK" GET "/api/accounting/float")
note "float HTTP $c rider line: $(jq -r --arg r "$RSUB" '.[] | select(.holderRef == $r) | "\(.holderKind) amount=\(.amount) orders=\(.orders)"' "$W/body")"
printf '%s\n' "select 'rider float by owner|' || coalesce(carrier_ref, 'platform') || '|' || count(*) || '|' || sum(amount) from accounting.cash_float where holder_ref = '$RSUB' and entry_kind = 'COLLECTED' and cleared_by is null group by carrier_ref;" | sql

echo "=== F1. the company records the rider's hand-over, two counters at once"
c=$(api "$CARR" GET "/api/accounting/carrier/cash/riders/$RSUB")
HOLD=$(j '.holding'); note "rider page HTTP $c holding=$HOLD standing=$(j '.standing') held rows=$(j '.held | length')"
K1="recon-h1-$(date +%s)"; K2="recon-h2-$(date +%s)"
curl -s -o "$W/h1" -w "%{http_code}" -X POST -H "Authorization: Bearer $CARR" -H "Content-Type: application/json" \
  -d "{\"expectedAmount\":\"$HOLD\",\"method\":\"CASH\",\"note\":\"recon test\",\"requestKey\":\"$K1\"}" \
  "$API/api/accounting/carrier/cash/riders/$RSUB/handovers" > "$W/h1.code" &
curl -s -o "$W/h2" -w "%{http_code}" -X POST -H "Authorization: Bearer $CARR" -H "Content-Type: application/json" \
  -d "{\"expectedAmount\":\"$HOLD\",\"method\":\"CASH\",\"note\":\"recon test\",\"requestKey\":\"$K2\"}" \
  "$API/api/accounting/carrier/cash/riders/$RSUB/handovers" > "$W/h2.code" &
wait
note "hand-over #1 HTTP $(cat "$W/h1.code") $(jq -c '{amount, collections, replayed, code, current}' "$W/h1")"
note "hand-over #2 HTTP $(cat "$W/h2.code") $(jq -c '{amount, collections, replayed, code, current}' "$W/h2")"
WIN=$K1; [ "$(cat "$W/h1.code")" = 200 ] || WIN=$K2
c=$(api "$CARR" POST "/api/accounting/carrier/cash/riders/$RSUB/handovers" "{\"expectedAmount\":\"$HOLD\",\"method\":\"CASH\",\"note\":\"recon test\",\"requestKey\":\"$WIN\"}")
note "replay of the winning key HTTP $c replayed=$(j '.replayed') amount=$(j '.amount')"
printf '%s\n' "select 'transfers by rider|' || count(*) || '|' || sum(amount) from accounting.cash_float where holder_ref = '$RSUB' and entry_kind = 'TRANSFERRED';" | sql

echo "=== F2. the Back Office records the company paying the platform, twice at once"
c=$(api "$BACK" GET "/api/accounting/float/carriers")
HELD=$(jq -r --arg c "$COMPANY" '.carriers[] | select(.carrierRef == $c) | .held' "$W/body")
note "company held=$HELD withRiders=$(jq -r --arg c "$COMPANY" '.carriers[] | select(.carrierRef == $c) | .withRiders' "$W/body")"
c=$(api "$CARR" GET "/api/accounting/carrier/cash/owed"); note "company's own owed page: held=$(j '.held') withRiders=$(j '.withRiders') payments=$(j '.payments | length')"
K3="recon-r1-$(date +%s)"; K4="recon-r2-$(date +%s)"
for k in "$K3" "$K4"; do
  curl -s -o "$W/$k" -w "%{http_code}" -X POST -H "Authorization: Bearer $BACK" -H "Content-Type: application/json" \
    -d "{\"expectedAmount\":\"$HELD\",\"method\":\"BANK_DEPOSIT\",\"note\":\"recon test\",\"requestKey\":\"$k\",\"holderKind\":\"PROVIDER\"}" \
    "$API/api/accounting/float/$COMPANY/remit" > "$W/$k.code" &
done
wait
for k in "$K3" "$K4"; do note "remit $k HTTP $(cat "$W/$k.code") $(jq -c '{amount, collections, replayed, code, current}' "$W/$k")"; done

echo "=== F3. the platform rider banks their own-fleet takings, against the counted figure"
c=$(api "$BACK" GET "/api/accounting/float")
RAMT=$(jq -r --arg r "$RSUB" '.[] | select(.holderRef == $r and .holderKind == "RIDER") | .amount' "$W/body")
note "rider now holds $RAMT"
c=$(api "$BACK" POST "/api/accounting/float/$RSUB/remit" "{\"expectedAmount\":$RAMT,\"method\":\"CASH\",\"note\":\"recon test\",\"requestKey\":\"recon-r3-$(date +%s)\",\"holderKind\":\"RIDER\"}")
note "rider remit HTTP $c amount=$(j '.amount') collections=$(j '.collections') $(err)"

echo "=== F4. what the ledger says now"
printf '%s\n' "select 'remittance legs|' || status || '|' || count(*) || '|' || sum(amount) from accounting.transactions where leg = 'CASH_REMITTANCE' group by status;" | sql
c=$(api "$BACK" GET "/api/accounting/summary"); note "summary: $(jq -c '.' "$W/body")"
c=$(api "$BACK" GET "/api/accounting/unsettled?limit=10"); note "unsettled list: $(j '[.[] | "\(.leg)=\(.amount)/\(.status)"] | join(", ")')"
kubectl -n "$NS" exec -i postgres-0 -- psql -U delivery -d delivery -At -F'|' < /dev/shm/recon/invariants.sql 2>&1 | sed -n '/I6/,/I11/p' | sed 's/^/     /'
echo "=== F done: $PASS pass $FAIL fail"
