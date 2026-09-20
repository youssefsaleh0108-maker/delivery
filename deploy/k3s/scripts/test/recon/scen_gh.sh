#!/bin/sh
# G: a merchant payout through points. H: every role's report against the ledger, and who may
# read or change whose money.
. /dev/shm/recon/lib.sh
CUST=$(tok customer); RIDER=$(tok rider); MERCH=$(tok merchant); CARR=$(tok carrier)
BACK=$(tok backoffice)
MSUB=$(sub_of "$MERCH"); RSUB=$(sub_of "$RIDER")
COMPANY=5857ac51-ef54-4c80-b50c-750998e50986
INHOUSE=00000000-0000-4000-8000-00000000d001
FROM=$(date -u +%Y-%m-01); TO=$(date -u +%Y-%m-%d)
F="${FROM}T00:00:00Z"; T=$(date -u -d "$TO + 1 day" +%Y-%m-%dT00:00:00Z)
E_OTHER=$(sed -n 's/.*E_OTHER=\([^ ]*\).*/\1/p' /dev/shm/recon/orders.txt | tail -1)

echo "=== G. the merchant turns 1000 points into money"
c=$(api "$MERCH" GET "/api/points/balance"); BEFORE=$(j '.points'); note "balance HTTP $c points=$BEFORE value=$(j '.value')"
if [ "${BEFORE:-0}" -lt 1000 ]; then
  note "G skipped: the merchant holds $BEFORE points, and this section spends 1000 — top them up to run it again"
  RID=
else
c=$(api "$MERCH" POST "/api/points/redemptions" '{"points":1000,"payoutNote":"recon test"}')
RID=$(j '.id // empty'); note "request HTTP $c id=$RID amount=$(j '.amount') status=$(j '.status') $(err)"
c=$(api "$BACK" POST "/api/points/redemptions/$RID/approve" '{"note":"recon test"}'); note "approve HTTP $c status=$(j '.status')"
c=$(api "$BACK" POST "/api/points/redemptions/$RID/paid" '{"note":"recon-ref"}'); note "paid HTTP $c status=$(j '.status')"
c=$(api "$BACK" POST "/api/points/redemptions/$RID/paid" '{"note":"recon-ref"}'); note "paid again HTTP $c ($(err | head -c 60))"
c=$(api "$MERCH" POST "/api/points/redemptions/$RID/cancel"); note "owner cancels a PAID request HTTP $c ($(err | head -c 60))"
c=$(api "$MERCH" GET "/api/points/balance"); AFTER=$(j '.points')
[ "$AFTER" -eq $((BEFORE-1000)) ] && ok "points fell by exactly 1000 ($BEFORE -> $AFTER)" || bad "points balance" "$BEFORE -> $AFTER"
printf '%s\n' "select 'points rows|' || reason || '|' || points from accounting.points_ledger where redemption_id = '$RID' order by created_at;" | sql
echo "RID=$RID" >> /dev/shm/recon/orders.txt

fi

echo "=== H1. statements per role vs the ledger ($FROM..$TO, as sent)"
kubectl -n "$NS" exec -i postgres-0 -- psql -U delivery -d delivery -At -F'|' -v f="$F" -v t="$T" \
  -v m="$MSUB" -v r="$RSUB" -v c="$COMPANY" < /dev/shm/recon/report.sql > "$W/ledger.txt"
sed 's/^/     ledger: /' "$W/ledger.txt"
signed() { # the API's net as a signed figure: WE_OWE positive
  jq -r '(.net.amount | tonumber) * (if .net.direction == "THEY_OWE" then -1 else 1 end)' "$W/body"; }
cmp() { # cmp <label> <api figure> <ledger figure>
  awk "BEGIN{exit !($2 == $3)}" && ok "$1 statement equals the ledger ($2)" || bad "$1 statement" "api=$2 ledger=$3"; }
c=$(api "$MERCH" GET "/api/accounting/statements/mine?from=$FROM&to=$TO"); MNET=$(signed)
note "merchant lines: $(j '[.lines[] | "\(.label)=\(.amount)"] | join("; ")')"
cmp merchant "$MNET" "$(sed -n 's/^merchant|//p' "$W/ledger.txt")"
c=$(api "$RIDER" GET "/api/accounting/statements/mine?from=$FROM&to=$TO"); RNET=$(signed)
note "rider lines: $(j '[.lines[] | "\(.label)=\(.amount)"] | join("; ")')"
cmp rider "$RNET" "$(sed -n 's/^rider|//p' "$W/ledger.txt")"
c=$(api "$CARR" GET "/api/accounting/statements/mine?from=$FROM&to=$TO"); CNET=$(signed)
note "carrier lines: $(j '[.lines[] | "\(.label)=\(.amount)"] | join("; ")')"
cmp carrier "$CNET" "$(sed -n 's/^carrier|//p' "$W/ledger.txt")"
c=$(api "$BACK" GET "/api/accounting/statements/PLATFORM/PLATFORM?from=$FROM&to=$TO"); PNET=$(signed)
note "platform HTTP $c lines: $(j '[.lines[] | "\(.label)=\(.amount)"] | join("; ")')"
cmp platform "$PNET" "$(sed -n 's/^platform|//p' "$W/ledger.txt")"
c=$(api "$BACK" GET "/api/accounting/statements/counterparties?from=$FROM&to=$TO")
note "counterparties HTTP $c: $(j '[.counterparties[] | "\(.kind)=\(.net)/\(.direction)"] | join(", ")') unattributed=$(j '.unattributed.amount')"
BO_M=$(jq -r --arg m "$MSUB" '.counterparties[] | select(.kind == "MERCHANT" and .ref == $m) | (.net | tonumber) * (if .direction == "THEY_OWE" then -1 else 1 end)' "$W/body")
cmp "backoffice list, merchant row" "${BO_M:-0}" "$MNET"

echo "=== H2. the carrier's cash page vs the float"
c=$(api "$CARR" GET "/api/accounting/carrier/cash"); note "overview HTTP $c day=$(j '.day') totals=$(jq -c '.totals' "$W/body")"
cmp "carrier withRiders" "$(j '.totals.withRiders')" "$(sed -n 's/^carrier withRiders now|//p' "$W/ledger.txt")"
cmp "carrier held" "$(j '.totals.held')" "$(sed -n 's/^carrier held now|//p' "$W/ledger.txt")"

echo "=== H3. dashboards beside the ledger"
c=$(api "$MERCH" GET "/api/orders/merchant/summary?days=1"); note "merchant summary HTTP $c: $(jq -c '{today: .today, totals: .totals}' "$W/body" | head -c 300)"
c=$(api "$CARR" GET "/api/orders/carrier/earnings"); note "carrier earnings HTTP $c: $(jq -c '.' "$W/body" | head -c 300)"
c=$(api "$RIDER" GET "/api/rider/balance"); note "rider balance HTTP $c: $(jq -c '.' "$W/body" | head -c 300)"

echo "=== H4. who may read or change whose money"
expect() { # expect <label> <want> <token> <method> <path> [json]
  c=$(api "$3" "$4" "$5" "${6:-}"); [ "$c" = "$2" ] && ok "$1 -> $c" || bad "$1" "wanted $2, got $c $(err | head -c 80)"; }
expect "merchant reads the reconciliation summary" 403 "$MERCH" GET "/api/accounting/summary"
expect "merchant reads its own statement by path" 403 "$MERCH" GET "/api/accounting/statements/MERCHANT/$MSUB?from=$FROM&to=$TO"
expect "carrier reads a merchant's statement" 403 "$CARR" GET "/api/accounting/statements/MERCHANT/$MSUB?from=$FROM&to=$TO"
expect "customer reads a statement of its own" 403 "$CUST" GET "/api/accounting/statements/mine?from=$FROM&to=$TO"
expect "rider opens the carrier cash page" 403 "$RIDER" GET "/api/accounting/carrier/cash"
expect "merchant opens a rider's carrier settlement" 403 "$MERCH" GET "/api/accounting/carrier/cash/riders/$RSUB"
expect "carrier opens a stranger as its rider" 404 "$CARR" GET "/api/accounting/carrier/cash/riders/$MSUB"
expect "carrier records a hand-over for a stranger" 404 "$CARR" POST "/api/accounting/carrier/cash/riders/$MSUB/handovers" '{"expectedAmount":"1.00"}'
expect "carrier reads another company's points" 403 "$CARR" GET "/api/points/carriers/$INHOUSE/balance"
expect "carrier redeems another company's points" 403 "$CARR" POST "/api/points/redemptions" "{\"ownerKind\":\"CARRIER\",\"ownerRef\":\"$INHOUSE\",\"points\":1000}"
expect "merchant redeems as a carrier" 403 "$MERCH" POST "/api/points/redemptions" "{\"ownerKind\":\"CARRIER\",\"ownerRef\":\"$COMPANY\",\"points\":1000}"
[ -n "$RID" ] && expect "rider cancels the merchant's redemption" 403 "$RIDER" POST "/api/points/redemptions/$RID/cancel" || note "skipped: no redemption of this run to cancel"
expect "rider records their own banking" 403 "$RIDER" POST "/api/accounting/float/$RSUB/remit" '{}'
expect "carrier records its own payment to the platform" 403 "$CARR" POST "/api/accounting/float/$COMPANY/remit" '{}'
expect "rider reads the cash-out queue" 403 "$RIDER" GET "/api/rider/cash-outs/queue"
expect "merchant reads another shop's order" 404 "$MERCH" GET "/api/orders/$E_OTHER"
expect "carrier reads payroll without a company scope leak (policy)" 200 "$CARR" GET "/api/accounting/carrier/payroll/policy"
c=$(api "$RIDER" GET "/api/transfers/splits/for-order/$E_OTHER"); note "rider reads the split checklist of an order that is not theirs: HTTP $c ($(err | head -c 60)) - 404 only because that order has no plan"

echo "=== H5. calendars: the same 'today' asked of each surface"
BEIRUT=$(TZ=Asia/Beirut date +%Y-%m-%d); note "UTC date $TO, Beirut date $BEIRUT, now $(date -u +%H:%M)Z"
tail -1 "$W/ledger.txt" | sed 's/^/     /'
c=$(api "$CARR" GET "/api/accounting/carrier/payroll/policy"); note "payroll zone: $(j '.zone')"
c=$(api "$RIDER" GET "/api/rider/earnings"); note "rider earnings zone: $(j '.zone')"
echo "=== GH done: $PASS pass $FAIL fail"
