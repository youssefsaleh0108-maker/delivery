#!/bin/sh
# The same calendar day asked of the statement (accounting) and of the dashboard series (Order
# Manager), for two orders delivered around Beirut midnight; and one statement row per order kind.
. /dev/shm/recon/lib.sh
MERCH=$(tok merchant)
B2=$(sed -n 's/.*B2=\([^ ]*\).*/\1/p' /dev/shm/recon/orders.txt | tail -1)
B1=$(sed -n 's/.*B1=\([^ ]*\).*/\1/p' /dev/shm/recon/orders.txt | tail -1)

for d in 2026-09-08 2026-09-09; do
  c=$(api "$MERCH" GET "/api/accounting/statements/mine?from=$d&to=$d")
  note "statement for $d (window $(j '.from')..$(j '.to')): net=$(j '.net.amount') orders=$(j '.entries | length') has 23ad6245=$(j '[.entries[].orderId | startswith("23ad6245")] | any') has 26fae838=$(j '[.entries[].orderId | startswith("26fae838")] | any')"
done
c=$(api "$MERCH" GET "/api/orders/merchant/daily?days=14")
note "dashboard series HTTP $c zone=$(j '.zone // "-"')"
j '(.days // .series // .)[]? | select(.day == "2026-09-08" or .day == "2026-09-09") | "     dashboard \(.day): orders=\(.orders // "-") delivered=\(.delivered // "-") money=\(.money // .gross // "-")"'

TODAY=$(date -u +%Y-%m-%d)
c=$(api "$MERCH" GET "/api/accounting/statements/mine?from=$TODAY&to=$TODAY")
note "today's statement lines: $(j '[.lines[] | "\(.label)=\(.amount)"] | join("; ")')"
j --arg x "$B2" '.entries[]' >/dev/null 2>&1
jq -r --arg b2 "$B2" --arg b1 "$B1" '.entries[] | select(.orderId == $b2 or .orderId == $b1)
  | "     entry \(.orderId[0:8]): gross=\(.gross) commission=\(.commission) net=\(.net) method=\(.paymentMethod)"' "$W/body"
note "note: $(j '.note' | head -c 400)"
