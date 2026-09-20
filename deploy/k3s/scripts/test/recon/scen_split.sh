#!/bin/sh
# S: a friend-split cash order, as the rider's cash checklist reads it, and a lira intent that
# does not match the order. Prints ids, statuses and amounts only (the plan carries names).
. /dev/shm/recon/lib.sh
CUST=$(tok customer); RIDER=$(tok rider); MERCH=$(tok merchant); BACK=$(tok backoffice)
P1=1acf044c-486f-4aee-b93b-f15daca667bd   # 9.75
ADDR='"deliveryAddress":"Recon deep test, Hamra, Beirut","contactPhone":"+96170000001"'

echo "=== S1. a cash order split with a guest the host covers"
place "{\"items\":[{\"productId\":\"$P1\",\"qty\":2}],$ADDR,\"paymentMethod\":\"CASH\"}"
S=$ORDER; TOTAL=$(j '.totalAmount')
c=$(api "$CUST" POST "/api/transfers/splits" "{\"mode\":\"EVEN\",\"totalUsd\":$TOTAL,\"storeName\":\"Recon\",\"shares\":[{\"username\":\"\",\"name\":\"Recon guest\",\"amountUsd\":5.00,\"itemsCount\":1}]}")
PLAN=$(j '.id // empty'); note "plan HTTP $c id=$PLAN status=$(j '.status') shares=$(j '[.shares[] | "\(.amountUsd)/\(.status)/\(.method // "-")"] | join(", ")')"
c=$(api "$CUST" POST "/api/transfers/splits/$PLAN/cover"); note "host covers the guest HTTP $c status=$(j '.status')"
c=$(api "$CUST" POST "/api/transfers/splits/$PLAN/attach-order" "{\"orderId\":\"$S\"}"); note "attach HTTP $c status=$(j '.status')"

echo "=== S2. read by a rider who has not claimed the order"
c=$(api "$RIDER" GET "/api/orders/$S"); note "rider reads the order itself: HTTP $c"
c=$(api "$RIDER" GET "/api/transfers/splits/for-order/$S")
note "rider reads its split plan: HTTP $c (fields returned: $(j 'keys | join(",")'); share fields: $(j '.shares[0] | keys | join(",")'))"
CASH_AT_DOOR=$(j '[.shares[] | select(.method == "CASH_AT_DOOR") | .amountUsd | tonumber] | add // 0')
SHOWN_PAID=$(j '[.shares[] | select(.method != "CASH_AT_DOOR" and .status != "PENDING" and .status != "DECLINED") | .amountUsd | tonumber] | add // 0')
note "checklist: 'total cash to collect' = $CASH_AT_DOOR, listed as 'already paid' = $SHOWN_PAID, order total (cash) = $TOTAL"

echo "=== S3. the order delivered: what the ledger books against the rider"
merchant_to "$S" accept prepare ready && rider_to "$S" claim pick-up deliver && wait_legs "$S" "$BACK" \
  && note "legs: $(j '[.[] | "\(.leg)=\(.amount)"] | join(", ")')"

echo "=== S4. a lira intent that does not match the order"
place "{\"items\":[{\"productId\":\"$P1\",\"qty\":1}],$ADDR,\"paymentMethod\":\"CASH\"}"
S4=$ORDER; S4_TOTAL=$(j '.totalAmount')
c=$(api "$CUST" POST "/api/transfers" "{\"orderId\":\"$S4\",\"method\":\"CASH_ON_DELIVERY\",\"amountUsd\":0.01}")
note "intent of 0.01 for an order of $S4_TOTAL: HTTP $c amountUsd=$(j '.amountUsd') splitLbpFace=$(j '.splitLbpFace')"
c=$(api "$CUST" GET "/api/transfers/order/$S4"); note "read back HTTP $c amountUsd=$(j '.amountUsd') method=$(j '.method')"
c=$(api "$CUST" POST "/api/orders/$S4/cancel" '{"reason":"recon test"}'); note "cancelled the S4 order HTTP $c"
echo "S=$S PLAN=$PLAN S4=$S4" >> /dev/shm/recon/orders.txt
echo "=== S done: $PASS pass $FAIL fail"
